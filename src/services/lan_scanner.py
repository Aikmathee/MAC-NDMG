"""
lan_scanner.py - Live LAN scanning and SMB share discovery for macOS.

Features:
  1. Bonjour / mDNS discovery (_smb._tcp) - automatically finds Macs, NAS,
     and SMB-enabled workstations broadcasting on the local network.
  2. Subnet port 445 probe - scans the local IPv4 subnet for devices.
  3. Dynamic share enumeration - uses `smbutil view` to query a host with
     credentials and list all exported HDD / Disk shares.
"""

from __future__ import annotations

import logging
import re
import socket
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from typing import List, Optional
from urllib.parse import quote as url_quote
from src.services import host_identity

log = logging.getLogger(__name__)


@dataclass
class DiscoveredHost:
    """A LAN host found via Bonjour or IP scan."""
    name: str
    host: str
    ip: str

    @property
    def display_label(self) -> str:
        if self.ip and self.ip != self.host:
            return f"{self.name} ({self.ip})"
        return f"{self.name} ({self.host})"


def get_local_ip() -> str:
    """Detect the machine's primary local LAN IP address."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


def discover_bonjour_smb(timeout: float = 1.5) -> List[DiscoveredHost]:
    """
    Discover SMB hosts on the local network using macOS Bonjour / mDNS.
    Runs `dns-sd -B _smb._tcp local.` and resolves discovered instances.
    """
    hosts: List[DiscoveredHost] = []
    seen_names = set()

    try:
        proc = subprocess.Popen(
            ["dns-sd", "-B", "_smb._tcp", "local."],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        time.sleep(timeout)
        proc.terminate()
        stdout, _ = proc.communicate()

        raw_instances = set()
        for line in stdout.splitlines():
            parts = line.split()
            if len(parts) >= 7 and parts[1] == "Add":
                instance_name = " ".join(parts[6:])
                raw_instances.add(instance_name)

        # Resolve each instance to hostname and IP
        for inst in sorted(raw_instances):
            if inst in seen_names:
                continue
            seen_names.add(inst)

            target_host, target_ip = _resolve_bonjour_instance(inst)
            hosts.append(
                DiscoveredHost(
                    name=inst,
                    host=target_host or inst,
                    ip=target_ip,
                )
            )

    except Exception as exc:
        log.warning("Bonjour SMB discovery error: %s", exc)

    return hosts


def _resolve_bonjour_instance(instance_name: str) -> tuple[str, str]:
    """Resolve a Bonjour instance to (hostname, ip)."""
    target_host = ""
    target_ip = ""
    try:
        proc = subprocess.Popen(
            ["dns-sd", "-L", instance_name, "_smb._tcp", "local."],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        time.sleep(0.4)
        proc.terminate()
        stdout, _ = proc.communicate()

        match = re.search(r"can be reached at (.*?):", stdout)
        if match:
            target_host = match.group(1).rstrip(".")

        if target_host:
            try:
                target_ip = socket.gethostbyname(target_host)
            except Exception:
                target_ip = ""

    except Exception as exc:
        log.debug("Error resolving instance %s: %s", instance_name, exc)

    return target_host, target_ip


def probe_smb_host(ip: str, timeout: float = 0.5) -> bool:
    """Check whether *ip* responds on SMB port 445."""
    try:
        with socket.create_connection((ip, 445), timeout=timeout):
            return True
    except (OSError, socket.timeout):
        return False


def scan_subnet_fast(base_subnet: Optional[str] = None) -> List[str]:
    """
    Fast multithreaded probe of the /24 subnet for open port 445.
    """
    if not base_subnet:
        local_ip = get_local_ip()
        parts = local_ip.split(".")
        if len(parts) == 4:
            base_subnet = f"{parts[0]}.{parts[1]}.{parts[2]}"
        else:
            base_subnet = "192.168.1"

    ips = [f"{base_subnet}.{i}" for i in range(1, 255)]
    found = []

    with ThreadPoolExecutor(max_workers=60) as pool:
        future_map = {pool.submit(probe_smb_host, ip): ip for ip in ips}
        for future in as_completed(future_map):
            ip = future_map[future]
            try:
                if future.result():
                    found.append(ip)
            except Exception:
                pass

    return sorted(found, key=lambda x: [int(p) for p in x.split(".")])


def scan_all_network_hosts() -> List[DiscoveredHost]:
    """
    Combines Bonjour mDNS discovery with subnet IP scanning for maximum coverage.
    """
    bonjour_hosts = discover_bonjour_smb(timeout=1.2)
    known_ips = {h.ip for h in bonjour_hosts if h.ip}
    known_hosts = {h.host.lower() for h in bonjour_hosts if h.host}

    # Supplement with subnet scan for non-Bonjour SMB devices (e.g. Linux/Windows NAS)
    try:
        subnet_ips = scan_subnet_fast()
        for ip in subnet_ips:
            if ip not in known_ips:
                # Try reverse lookup
                try:
                    hostname = socket.gethostbyaddr(ip)[0].rstrip('.')
                    if ip not in host_identity.current_addresses(hostname):
                        hostname = ip
                except Exception:
                    hostname = ip
                bonjour_hosts.append(
                    DiscoveredHost(
                        name=f"SMB Host ({ip})",
                        host=hostname,
                        ip=ip,
                    )
                )
    except Exception as exc:
        log.debug("Subnet scan supplement error: %s", exc)

    return bonjour_hosts


def list_shares_for_host(
    host_or_ip: str,
    username: Optional[str] = None,
    password: Optional[str] = None,
) -> tuple[List[str], str]:
    """
    Query an SMB host for its exported shares using `smbutil view`.

    Returns:
        (list_of_share_names, error_or_status_message)
    """
    # Build target specifier
    if username and password:
        enc_user = url_quote(username, safe="")
        enc_pass = url_quote(password, safe="")
        target = f"//{enc_user}:{enc_pass}@{host_or_ip}"
    elif username:
        enc_user = url_quote(username, safe="")
        target = f"//{enc_user}@{host_or_ip}"
    else:
        target = f"//{host_or_ip}"

    cmd = ["smbutil", "view"]
    if not username and not password:
        cmd.append("-g")  # guest
    cmd.append(target)

    log.info("Querying shares on %s...", host_or_ip)
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10,
        )

        stdout = result.stdout
        stderr = result.stderr

        if result.returncode != 0:
            err = stderr.strip() or stdout.strip() or "Connection or authentication failed"
            return [], err

        # Parse output table:
        # Share        Type       Comments
        # -------------------------------
        # Video        Disk       
        # Cache        Disk       
        shares: List[str] = []
        for line in stdout.splitlines():
            line_clean = line.strip()
            if not line_clean or line_clean.startswith("-") or "Share" in line_clean and "Type" in line_clean:
                continue
            match = re.match(r"^(.+?)\s+(Disk|Printer|IPC)\b", line_clean, re.IGNORECASE)
            if match and match.group(2).lower() == "disk":
                shares.append(match.group(1).strip())

        if not shares:
            return [], "No exported disk shares found on this host"

        return shares, ""

    except subprocess.TimeoutExpired:
        return [], "Timed out connecting to host (10s)"
    except Exception as exc:
        return [], str(exc)
