"""
config_loader.py - Reads and parses config/shares.json.

Provides a single function ``load_hosts()`` that returns a list of
HostEntry objects from the JSON configuration file.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import List

from src.models.share_item import HostEntry


# Default config path relative to project root
_DEFAULT_CONFIG = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "config",
    "shares.json",
)


def load_hosts(config_path: str | None = None) -> List[HostEntry]:
    """
    Load host definitions from a JSON configuration file.

    Parameters
    ----------
    config_path : str or None
        Absolute or relative path to the JSON config file.
        Falls back to ``config/shares.json`` in the project root if *None*.

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
    path = Path(config_path) if config_path else Path(_DEFAULT_CONFIG)

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
    path = Path(config_path) if config_path else Path(_DEFAULT_CONFIG)

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
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
