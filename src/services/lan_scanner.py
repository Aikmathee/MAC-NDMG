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
from src.services import host_identity, network_mounts

log = logging.getLogger(__name__)


@dataclass
class DiscoveredHost:
    """A LAN host found via Bonjour or IP scan."""
    name: str
    host: str
    ip: str
    source: str = "network"

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

        # Resolve concurrently and allow time for uncached mDNS responses.
        with ThreadPoolExecutor(max_workers=12) as pool:
            for inst, (target_host, target_ip) in zip(sorted(raw_instances), pool.map(_resolve_bonjour_instance, sorted(raw_instances))):
                if target_host or target_ip:
                    hosts.append(DiscoveredHost(inst, target_host, target_ip, "bonjour"))

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
        time.sleep(1.5)
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


def resolve_subnet_host(ip):
    """Read the server's SMB name, including machines absent from Bonjour/DNS."""
    try:
        hostname = socket.gethostbyaddr(ip)[0].rstrip('.')
        if host_identity.hostname(hostname) and ip in host_identity.current_addresses(hostname):
            return DiscoveredHost(hostname, hostname, ip, 'network')
    except OSError:
        pass
    try:
        result = subprocess.run(['/usr/bin/smbutil', 'status', ip], capture_output=True, text=True, timeout=2)
        match = re.search(r'^Server:\s*(.+?)\s*$', result.stdout, re.M) if result.returncode == 0 else None
        name = match.group(1).strip() if match else ''
        # Keep the friendly name even if broadcast lookup is blocked. Use the
        # hostname as destination only after confirming it resolves to this IP.
        if host_identity.hostname(name) and not host_identity.is_ip(name):
            target = name.lower() if ip in host_identity.current_addresses(name.lower()) else ip
            return DiscoveredHost(name, target, ip, 'netbios')
    except (OSError, subprocess.SubprocessError):
        pass
    return DiscoveredHost(f'SMB Host ({ip})', ip, ip)


def scan_all_network_hosts() -> List[DiscoveredHost]:
    """
    Combines Bonjour mDNS discovery with subnet IP scanning for maximum coverage.
    """
    bonjour_hosts = discover_bonjour_smb(timeout=3.0)
    known_ips = {h.ip for h in bonjour_hosts if h.ip}

    # Supplement with subnet scan for non-Bonjour SMB devices (e.g. Linux/Windows NAS)
    try:
        subnet_ips = scan_subnet_fast()
        candidates = [ip for ip in subnet_ips if ip not in known_ips]
        with ThreadPoolExecutor(max_workers=12) as pool:
            bonjour_hosts.extend(pool.map(resolve_subnet_host, candidates))
    except Exception as exc:
        log.debug("Subnet scan supplement error: %s", exc)

    try:
        bonjour_hosts = merge_connected_hosts(bonjour_hosts, network_mounts.list_network_mounts())
    except (OSError, RuntimeError, subprocess.SubprocessError):
        pass
    return bonjour_hosts


def merge_connected_hosts(hosts, volumes):
    """A live Finder mount must remain visible even without a Bonjour broadcast."""
    result = list(hosts)
    known = {network_mounts._host_key(h.host) for h in result if h.host}
    known_ips = {h.ip for h in result if h.ip}
    for volume in volumes:
        if volume.filesystem != 'smbfs':
            continue
        address = volume.address
        if not (host_identity.hostname(address) or host_identity.is_ip(address) or host_identity.bonjour_service_address(address)):
            continue
        if (network_mounts._host_key(address) in known or address in known_ips
                or (host_identity.bonjour_service_address(address)
                    and any(h.source == 'bonjour' and h.name.casefold() == volume.server_name.casefold() for h in result))):
            continue
        resolved = host_identity.current_addresses(address)
        matching = next((i for i, h in enumerate(result) if h.ip and h.ip in resolved), None)
        if matching is not None:
            if result[matching].source == 'network':
                old = result[matching]
                result[matching] = DiscoveredHost(volume.server_name, address, old.ip, 'connected')
            known.add(network_mounts._host_key(address))
            continue
        result.append(DiscoveredHost(volume.server_name, address,
                                     address if host_identity.is_ip(address) else next(iter(resolved), ''), 'connected'))
        known.add(network_mounts._host_key(address))
    return result


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
    if password and not username:
        return [], "Enter a username."
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
    if not password:
        cmd.append("-N")  # Reuse a system SMB session without prompting on stdin.
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
            return [], "No shared drives found."

        return shares, ""

    except subprocess.TimeoutExpired:
        return [], "Timed out connecting to host (10s)"
    except Exception as exc:
        return [], str(exc)
