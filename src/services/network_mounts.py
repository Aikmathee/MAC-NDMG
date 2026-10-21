"""Read macOS's live network mount table and operate on a verified mount identity."""
from __future__ import annotations

from dataclasses import dataclass, asdict
import hashlib
import re
import subprocess
from urllib.parse import unquote, urlsplit

NETWORK_FILESYSTEMS = {"smbfs", "afpfs", "nfs", "webdav"}


def _unescape(value: str) -> str:
    return re.sub(r"\\([0-7]{3})", lambda m: chr(int(m.group(1), 8)), value)


@dataclass(frozen=True)
class MountedVolume:
    id: str
    name: str
    address: str
    server_name: str
    share: str
    mount_point: str
    filesystem: str

    def to_dict(self):
        return asdict(self)


def parse_mounts(output: str) -> list[MountedVolume]:
    volumes = []
    for line in output.splitlines():
        match = re.match(r"^(.+?) on (/.*?) \((smbfs|afpfs|nfs|webdav)(?:, [^\n]*)?\)$", line)
        if not match:
            continue
        source, mount_point, filesystem = match.groups()
        mount_point = _unescape(mount_point)
        address, share = "", ""
        if filesystem == "nfs":
            nfs = re.match(r"^(\[[^\]]+\]|[^:]+):(/.*)$", source)
            if nfs:
                address, share = nfs.group(1).strip("[]"), _unescape(nfs.group(2)).rstrip("/")
        else:
            uri = source if "://" in source else "smb:" + source
            try:
                parts = urlsplit(uri)
                address = unquote(parts.hostname or "")
                share = unquote(parts.path).strip("/")
            except ValueError:
                continue
        if not address or not share:
            continue
        display = re.sub(r"\._(?:smb|afpovertcp)\._tcp\.local\.?$", "", address, flags=re.I)
        identity = hashlib.sha256(f"{filesystem}\0{source}\0{mount_point}".encode()).hexdigest()
        volumes.append(MountedVolume(identity, mount_point.rsplit("/", 1)[-1], address,
                                     display, share, mount_point, filesystem))
    return sorted(volumes, key=lambda v: (v.server_name.casefold(), v.name.casefold(), v.mount_point))


def list_network_mounts() -> list[MountedVolume]:
    result = subprocess.run(["/sbin/mount", "-t", ",".join(sorted(NETWORK_FILESYSTEMS))],
                            capture_output=True, text=True, timeout=5)
    if result.returncode:
        raise RuntimeError("Could not read connected network drives.")
    return parse_mounts(result.stdout)


def _host_key(value: str) -> str:
    value = unquote(value).rstrip(".").casefold()
    value = re.sub(r"\._(?:smb|afpovertcp)\._tcp\.local$", "", value)
    return re.sub(r"\.local$", "", value)


def find_mount(host: str, share: str, host_name: str = "") -> MountedVolume | None:
    """Match both server and share, never a /Volumes name alone."""
    keys = {_host_key(value) for value in (host, host_name) if value}
    return next((volume for volume in list_network_mounts()
                 if volume.filesystem == "smbfs" and volume.share == share
                 and keys.intersection({_host_key(volume.address), _host_key(volume.server_name)})), None)


def eject_volume(volume_id: str) -> tuple[bool, str]:
    # Resolve the identity again immediately before ejecting. The UI cannot supply
    # an arbitrary filesystem path or accidentally eject a new mount at an old path.
    volume = next((v for v in list_network_mounts() if v.id == volume_id), None)
    if volume is None:
        return True, ""  # Already disconnected.
    result = subprocess.run(["/usr/sbin/diskutil", "unmount", volume.mount_point],
                            capture_output=True, text=True, timeout=20)
    if result.returncode:
        return False, (result.stderr.strip() or result.stdout.strip() or "The drive is in use. Close its files and try again.")
    if any(v.id == volume_id for v in list_network_mounts()):
        return False, "The drive is still connected. Close its files and try again."
    return True, ""


def reveal_volume(volume_id: str) -> bool:
    volume = next((v for v in list_network_mounts() if v.id == volume_id), None)
    if volume is None:
        return False
    result = subprocess.run(["/usr/bin/open", volume.mount_point], capture_output=True, timeout=10)
    return result.returncode == 0
