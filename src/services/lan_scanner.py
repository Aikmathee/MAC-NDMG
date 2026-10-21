"""
lan_scanner.py - (Optional) Probe LAN for active SMB hosts.

Provides basic LAN scanning to discover hosts with open SMB ports (445).
This module is optional and can be used to supplement the static
config/shares.json file with dynamically-discovered hosts.
"""

from __future__ import annotations

import logging
import socket
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import List

log = logging.getLogger(__name__)

SMB_PORT = 445
SCAN_TIMEOUT = 1.0  # seconds per probe


def probe_smb_host(ip: str, timeout: float = SCAN_TIMEOUT) -> bool:
    """
    Check whether *ip* has an open SMB port (445).

    Returns True if a TCP connection can be established within *timeout*.
    """
    try:
        with socket.create_connection((ip, SMB_PORT), timeout=timeout):
            return True
    except (OSError, socket.timeout):
        return False


def scan_subnet(
    subnet: str = "192.168.1",
    start: int = 1,
    end: int = 254,
    max_workers: int = 50,
) -> List[str]:
    """
    Scan a /24 subnet for hosts with open SMB ports.

    Parameters
    ----------
    subnet : str
        The first three octets of the subnet (e.g., ``"192.168.1"``).
    start, end : int
        The range of the final octet to scan.
    max_workers : int
        Thread pool size for parallel probing.

    Returns
    -------
    list[str]
        IP addresses that responded on port 445.
    """
    ips = [f"{subnet}.{i}" for i in range(start, end + 1)]
    active: List[str] = []

    log.info("Scanning %s.%d–%d for SMB hosts…", subnet, start, end)

    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        futures = {pool.submit(probe_smb_host, ip): ip for ip in ips}
        for future in as_completed(futures):
            ip = futures[future]
            try:
                if future.result():
                    log.info("  Found SMB host: %s", ip)
                    active.append(ip)
            except Exception:
                pass

    active.sort(key=lambda x: list(map(int, x.split("."))))
    log.info("Scan complete — %d host(s) found.", len(active))
    return active


def list_smb_shares(ip: str) -> List[str]:
    """
    Attempt to list SMB shares on a host using ``smbutil``.

    Note: This requires the host to allow guest/anonymous enumeration,
    which many setups do not.  Returns an empty list on failure.
    """
    try:
        result = subprocess.run(
            ["smbutil", "view", f"//{ip}"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        shares: List[str] = []
        for line in result.stdout.splitlines():
            # smbutil output lines look like: "ShareName     Disk     ..."
            parts = line.split()
            if len(parts) >= 2 and parts[1] == "Disk":
                shares.append(parts[0])
        return shares
    except Exception as exc:
        log.debug("Could not enumerate shares on %s: %s", ip, exc)
        return []
