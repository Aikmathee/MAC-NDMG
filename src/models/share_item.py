"""
share_item.py - Data structures for Hosts and Share Drives.

Defines the domain models used throughout the application:
  - ShareItem: represents a single SMB share on a host
  - HostEntry: represents a LAN machine exposing one or more shares
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from enum import Enum
from typing import List


class MountStatus(Enum):
    """Current mount state of a network share."""
    UNKNOWN = "unknown"
    DISCONNECTED = "disconnected"
    CONNECTING = "connecting"
    CONNECTED = "connected"
    ERROR = "error"


@dataclass
class ShareItem:
    """A single exported SMB share on a network host."""

    name: str
    host_ip: str
    host_name: str
    status: MountStatus = MountStatus.UNKNOWN
    error_message: str = ""
    selected: bool = False

    # --- derived helpers -------------------------------------------------- #

    @property
    def mount_point(self) -> str:
        """Expected mount location on macOS."""
        from src.services.network_mounts import find_mount
        volume = find_mount(self.host_ip, self.name, self.host_name)
        return volume.mount_point if volume else f"/Volumes/{self.name}"

    @property
    def is_mounted(self) -> bool:
        """Check whether this share is currently mounted."""
        from src.services.network_mounts import find_mount
        return find_mount(self.host_ip, self.name, self.host_name) is not None

    def refresh_status(self) -> MountStatus:
        """Re-examine the filesystem and update our status accordingly."""
        if self.is_mounted:
            self.status = MountStatus.CONNECTED
        elif self.status not in (MountStatus.CONNECTING, MountStatus.ERROR):
            self.status = MountStatus.DISCONNECTED
        return self.status

    def smb_uri(self, username: str, password_encoded: str) -> str:
        """Build a fully-qualified SMB URI with embedded credentials."""
        return f"smb://{username}:{password_encoded}@{self.host_ip}/{self.name}"

    def __str__(self) -> str:
        return f"{self.host_name} ({self.host_ip}) → {self.name} [{self.status.value}]"


@dataclass
class HostEntry:
    """A LAN machine that exposes one or more SMB shares."""

    id: str
    name: str
    ip_or_hostname: str
    shares: List[ShareItem] = field(default_factory=list)

    # --- factory ---------------------------------------------------------- #

    @classmethod
    def from_dict(cls, data: dict) -> "HostEntry":
        """Create a HostEntry from a config-file dictionary."""
        host = cls(
            id=data["id"],
            name=data["name"],
            ip_or_hostname=data["ip_or_hostname"],
        )
        for share_name in data.get("shares", []):
            host.shares.append(
                ShareItem(
                    name=share_name,
                    host_ip=host.ip_or_hostname,
                    host_name=host.name,
                )
            )
        return host

    # --- bulk helpers ----------------------------------------------------- #

    def select_all(self) -> None:
        for s in self.shares:
            s.selected = True

    def clear_all(self) -> None:
        for s in self.shares:
            s.selected = False

    @property
    def selected_shares(self) -> List[ShareItem]:
        return [s for s in self.shares if s.selected]

    def refresh_all(self) -> None:
        for s in self.shares:
            s.refresh_status()
