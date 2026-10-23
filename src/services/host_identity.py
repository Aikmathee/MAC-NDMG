"""Keep DNS/Bonjour names as destinations; resolve addresses only for live matching."""
from functools import lru_cache
import ipaddress
import re
import socket
import subprocess
from urllib.parse import quote, unquote


def is_ip(value):
    try:
        ipaddress.ip_address(value.strip('[]').split('%', 1)[0])
        return True
    except ValueError:
        return False


def hostname(value):
    """Accept a DNS target, never manufacture one from a computer display name."""
    value = value.rstrip('.')
    if not value or len(value) > 253 or is_ip(value):
        return ''
    if not all(re.fullmatch(r'[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?', label)
               for label in value.split('.')):
        return ''
    return value.lower()


@lru_cache(maxsize=256)
def current_addresses(host):
    # The bridge handles one request per process. Nothing is cached across scans,
    # reconnects or mount polls, so a DHCP change cannot leave a stale IP alias.
    if is_ip(host):
        return (host.strip('[]').lower(),)
    if not hostname(host):
        return ()
    try:
        return tuple(sorted({item[4][0].lower() for item in socket.getaddrinfo(host, 445, type=socket.SOCK_STREAM)}))
    except OSError:
        return netbios_addresses(host)


def netbios_addresses(host):
    """Resolve a real short SMB name using macOS NetBIOS, never a guessed IP."""
    if not hostname(host) or '.' in host or len(host) > 15:
        return ()
    try:
        result = subprocess.run(['/usr/bin/smbutil', 'lookup', host], capture_output=True, text=True, timeout=2)
        if result.returncode:
            return ()
        values = re.findall(r'^IP address of [^:]+:\s*(\S+)\s*$', result.stdout, re.M)
        return tuple(sorted({v for v in values if is_ip(v)}))
    except (OSError, subprocess.SubprocessError):
        return ()


def bonjour_service_address(value):
    value = unquote(value).rstrip('.')
    if (value.lower().endswith('._smb._tcp.local') and len(value) <= 253
            and not any(ord(c) < 32 or c in '/@?#\\' for c in value)):
        return quote(value, safe='-._').lower()
    return ''


def connection_address(host):
    return hostname(host.host) or bonjour_service_address(host.host) or host.ip or (host.host if is_ip(host.host) else '')


def matches_ip(host, address):
    """DNS is used only when the mounted endpoint is numeric, not for display names."""
    return is_ip(address) and not is_ip(host) and address.lower() in current_addresses(host)
