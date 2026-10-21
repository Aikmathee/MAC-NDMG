"""
config_loader.py - Reads and writes the current user's saved servers.

Provides a single function ``load_hosts()`` that returns a list of
HostEntry objects from the JSON configuration file.
"""

from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import List

from src.models.share_item import HostEntry


# User preferences must remain writable when running from /Applications.
def default_config_path() -> Path:
    return Path.home() / "Library" / "Application Support" / "MAC-NDMG" / "shares.json"


def _config_path(config_path: str | None) -> Path:
    if config_path:
        return Path(config_path).expanduser()
    return default_config_path()


def load_hosts(config_path: str | None = None) -> List[HostEntry]:
    """
    Load host definitions from a JSON configuration file.

    Parameters
    ----------
    config_path : str or None
        Absolute or relative path to the JSON config file.
        Uses the current user's Application Support/MAC-NDMG/shares.json if *None*.

    Returns
    -------
    list[HostEntry]
        Parsed host objects with their associated shares.

    Raises
    ------
    FileNotFoundError
        If the config file does not exist.
    json.JSONDecodeError
        If the file contains invalid JSON.
    KeyError
        If required keys are missing from the config data.
    """
    path = _config_path(config_path)

    if not path.exists() and config_path is None:
        return []

    if not path.exists():
        raise FileNotFoundError(f"Configuration file not found: {path}")

    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)

    hosts: List[HostEntry] = []
    for host_dict in data.get("hosts", []):
        hosts.append(HostEntry.from_dict(host_dict))

    return hosts


def save_hosts(hosts: List[HostEntry], config_path: str | None = None) -> None:
    """
    Write host definitions back to the JSON configuration file.

    This is useful when the user edits hosts/shares via the GUI and wants
    the changes persisted.
    """
    path = _config_path(config_path)

    data = {
        "hosts": [
            {
                "id": h.id,
                "name": h.name,
                "ip_or_hostname": h.ip_or_hostname,
                "shares": [s.name for s in h.shares],
            }
            for h in hosts
        ]
    }

    path.parent.mkdir(parents=True, exist_ok=True)
    # Replace atomically so a crash cannot leave a half-written configuration.
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".shares-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
