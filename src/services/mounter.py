"""
mounter.py - macOS SMB mounting logic & status checks.

Handles credential encoding, SMB URI construction, subprocess execution
for the ``open`` command, and post-mount verification against /Volumes.
All public functions are designed to be called from a background thread.
"""

from __future__ import annotations

import logging
import os
import subprocess
import time
from typing import Callable, List, Optional
from urllib.parse import quote as url_quote

from src.models.share_item import MountStatus, ShareItem

log = logging.getLogger(__name__)

# How long to wait (seconds) after issuing the mount command before
# checking whether the volume appeared.
_POST_MOUNT_WAIT = 3.0
_MAX_RETRIES = 5
_RETRY_INTERVAL = 1.5  # seconds between retries


def encode_password(password: str) -> str:
    """
    URL-encode a password for safe embedding inside an SMB URI.

    Characters such as ``@``, ``:``, ``/``, ``#``, ``%`` are escaped.
    """
    return url_quote(password, safe="")


def build_smb_uri(username: str, password: str, ip: str, share_name: str) -> str:
    """
    Construct a fully-qualified ``smb://`` URI with encoded credentials.
    """
    if ':' in ip and not ip.startswith('['):
        ip = f'[{ip}]'
    credentials = ""
    if username:
        credentials = url_quote(username, safe="")
        if password:
            credentials += ":" + encode_password(password)
        credentials += "@"
    return f"smb://{credentials}{ip}/{url_quote(share_name, safe='')}"


def check_mount_status(share: ShareItem) -> MountStatus:
    """
    Examine /Volumes to determine whether *share* is currently mounted.
    Updates ``share.status`` in-place and returns the new status.
    """
    return share.refresh_status()


def mount_share(
    share: ShareItem,
    username: str,
    password: str,
    *,
    on_status_change: Optional[Callable[[ShareItem], None]] = None,
) -> bool:
    """
    Mount a single SMB share via the macOS ``open`` command.

    Parameters
    ----------
    share : ShareItem
        The share to mount.
    username, password : str
        SMB credentials (password will be URL-encoded automatically).
    on_status_change : callable, optional
        Callback fired whenever the share status changes (useful for
        pushing updates back to the GUI thread).

    Returns
    -------
    bool
        *True* if the share was verified as mounted after the command.
    """
    def _notify():
        if on_status_change:
            on_status_change(share)

    # If already mounted, skip
    if share.is_mounted:
        share.status = MountStatus.CONNECTED
        _notify()
        log.info("Already mounted: %s", share)
        return True

    share.status = MountStatus.CONNECTING
    share.error_message = ""
    _notify()

    uri = build_smb_uri(username, password, share.host_ip, share.name)

    # Log the URI with the password masked
    masked_uri = build_smb_uri(username, "****", share.host_ip, share.name)
    log.info("Mounting %s via: %s", share.name, masked_uri)

    try:
        result = subprocess.run(
            ["open", uri],
            capture_output=True,
            text=True,
            timeout=30,
        )

        if result.returncode != 0:
            stderr = result.stderr.strip()
            share.status = MountStatus.ERROR
            share.error_message = stderr or f"open exited with code {result.returncode}"
            _notify()
            log.error("Mount failed for %s: %s", share.name, share.error_message)
            return False

    except subprocess.TimeoutExpired:
        share.status = MountStatus.ERROR
        share.error_message = "Mount command timed out (30 s)"
        _notify()
        log.error("Timeout mounting %s", share.name)
        return False
    except Exception as exc:
        share.status = MountStatus.ERROR
        share.error_message = str(exc)
        _notify()
        log.exception("Unexpected error mounting %s", share.name)
        return False

    # Wait and verify
    time.sleep(_POST_MOUNT_WAIT)

    for attempt in range(1, _MAX_RETRIES + 1):
        if share.is_mounted:
            share.status = MountStatus.CONNECTED
            _notify()
            log.info("✅ Successfully mounted: %s", share.name)
            return True
        log.debug(
            "Waiting for mount… attempt %d/%d for %s",
            attempt, _MAX_RETRIES, share.name,
        )
        time.sleep(_RETRY_INTERVAL)

    # After retries, check one last time
    if share.is_mounted:
        share.status = MountStatus.CONNECTED
        _notify()
        return True

    share.status = MountStatus.ERROR
    share.error_message = "Volume did not appear at /Volumes after mount command"
    _notify()
    log.warning("Mount command succeeded but volume not found: %s", share.name)
    return False


def mount_batch(
    shares: List[ShareItem],
    username: str,
    password: str,
    *,
    on_status_change: Optional[Callable[[ShareItem], None]] = None,
    on_complete: Optional[Callable[[int, int], None]] = None,
) -> tuple[int, int]:
    """
    Mount multiple shares sequentially.

    Parameters
    ----------
    shares : list[ShareItem]
        Shares to mount.
    username, password : str
        SMB credentials.
    on_status_change : callable, optional
        Per-share status callback.
    on_complete : callable, optional
        Called at the end with ``(success_count, fail_count)``.

    Returns
    -------
    tuple[int, int]
        (success_count, fail_count)
    """
    success = 0
    fail = 0

    for share in shares:
        ok = mount_share(
            share, username, password,
            on_status_change=on_status_change,
        )
        if ok:
            success += 1
        else:
            fail += 1

    if on_complete:
        on_complete(success, fail)

    return success, fail


def unmount_share(share: ShareItem) -> bool:
    """
    Unmount (eject) a mounted share via ``diskutil unmount``.
    """
    from src.services.network_mounts import find_mount, eject_volume
    try:
        volume = find_mount(share.host_ip, share.name, share.host_name)
        ok, error = eject_volume(volume.id) if volume else (True, "")
        share.error_message = error
        if ok:
            share.status = MountStatus.DISCONNECTED
        return ok
    except Exception as exc:
        share.error_message = str(exc)
        return False


def reveal_in_finder(mount_point: str) -> bool:
    """Open a mounted volume folder directly in macOS Finder."""
    try:
        subprocess.run(["open", mount_point], check=True)
        return True
    except Exception as exc:
        log.error("Failed to open %s in Finder: %s", mount_point, exc)
        return False


def open_server_in_finder(
    host_or_ip: str,
    username: Optional[str] = None,
    password: Optional[str] = None,
) -> bool:
    """
    Open the server in macOS Finder via `open smb://...`.
    This brings up Finder's native 'Select volumes to mount' dialog.
    """
    if ':' in host_or_ip and not host_or_ip.startswith('['):
        host_or_ip = f'[{host_or_ip}]'
    if username and password:
        uri = f"smb://{url_quote(username, safe='')}:{encode_password(password)}@{host_or_ip}"
    elif username:
        uri = f"smb://{url_quote(username, safe='')}@{host_or_ip}"
    else:
        uri = f"smb://{host_or_ip}"

    try:
        subprocess.run(["open", uri], check=True)
        return True
    except Exception as exc:
        log.error("Failed to open server %s in Finder: %s", host_or_ip, exc)
        return False
