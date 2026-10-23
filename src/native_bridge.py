"""One-request JSON bridge for the native macOS UI; no HTTP server or open port."""
from __future__ import annotations

import json
import logging
import sys
import subprocess
from urllib.parse import quote
from src.models.share_item import HostEntry, ShareItem
from src.services import config_loader, lan_scanner, mounter, network_mounts, connection_groups, host_identity, drive_recovery


def drive_dict(share):
    share.refresh_status()
    return {"id": share.name, "name": share.name, "status": share.status.value,
            "error": share.error_message}


def host_dict(host):
    return {"id": host.ip_or_hostname, "name": host.name, "address": host.ip_or_hostname,
            "saved": True, "drives": [drive_dict(s) for s in host.shares]}


def discovered_dict(host):
    address = host_identity.connection_address(host)
    if not address:
        return None
    return {"id": address.lower(), "name": host.name, "address": address,
            "ip": host.ip or None, "source": host.source, "discovered": True,
            "saved": False, "drives": []}


def connected_hosts(volumes):
    return [value for host in lan_scanner.merge_connected_hosts([], volumes)
            if (value := discovered_dict(host))]


def remembered_hosts(state):
    """Keep known SMB destinations visible independently of discovery success."""
    result = {}
    for drive in state['drives']:
        if drive.get('protocol') == 'webdav':
            continue
        address = drive.get('address', '')
        # Custom-port URLs need their original endpoint flow, not a portless server.
        if drive.get('url'):
            from urllib.parse import urlsplit
            if urlsplit(drive['url']).port not in (None, 445):
                continue
        if not (host_identity.hostname(address) or host_identity.is_ip(address)
                or host_identity.bonjour_service_address(address)):
            continue
        key = network_mounts._host_key(address)
        result.setdefault(key, {'id': address.lower(), 'name': drive.get('server_name') or address,
                               'address': address, 'saved': True, 'source': 'history', 'drives': []})
    return list(result.values())


def library_dict(state, volumes=()):
    # Live matching metadata is never written to history or used as a destination.
    return {"hosts": remembered_hosts(state), "remembered": [dict(drive, mounted_ids=[v.id for v in volumes
                if connection_groups.is_connected(drive, [v])]) for drive in state["drives"]],
            "groups": state["groups"]}


def dispatch(request):
    action = request.get("action")
    config = request.get("config")
    if action == "find_drive":
        return {"ok": True, "hosts": drive_recovery.find_candidates(request.get("drive_id"))}
    if action == "relocate_drive":
        address = request.get("address", "")
        if not isinstance(address, str) or not address or len(address) > 253 or any(c in address for c in '/@?#\\\n\r\t '):
            raise ValueError("Enter a valid server address.")
        state = drive_recovery.relocate(request.get("drive_id"), address)
        return dict(ok=True, **library_dict(state, network_mounts.list_network_mounts()))
    if action in ("connections", "save_group", "delete_group", "reconnect", "save_endpoint"):
        state = None
        status = None
        volumes = None
        if action == "save_endpoint":
            state = connection_groups.save_endpoint(request.get("url"), request.get("name", ""))
        elif action == "save_group":
            state = connection_groups.save_group(request.get("name"), request.get("drive_ids"), request.get("group_id"))
        elif action == "delete_group":
            state = connection_groups.delete_group(request.get("group_id"))
        elif action == "reconnect":
            status, volumes = connection_groups.reconnect(request.get("drive_id"), request.get("username", ""), request.get("password", ""))
        else:
            volumes = network_mounts.list_network_mounts()
            state = connection_groups.remember_mounts(volumes)
        result = {"ok": True}
        if state is not None:
            result.update(library_dict(state, volumes or ()))
        if status is not None:
            result["connection_state"] = status
            result["volumes"] = [v.to_dict() for v in volumes]
        return result
    if action in ("mounted", "eject_volume", "reveal_volume"):
        ok, error = True, ""
        if action != "mounted":
            volume_id = request.get("volume_id", "")
            if not isinstance(volume_id, str) or len(volume_id) != 64:
                raise ValueError("Choose a connected network drive.")
            if action == "eject_volume":
                ok, error = network_mounts.eject_volume(volume_id)
            else:
                ok = network_mounts.reveal_volume(volume_id)
                if not ok:
                    error = "This drive is no longer connected."
        volumes = network_mounts.list_network_mounts()
        if action == "eject_volume" and not ok and not any(v.id == volume_id for v in volumes):
            ok, error = True, ""  # macOS completed it while the request was timing out.
        result = {"ok": ok, "error": error, "volumes": [v.to_dict() for v in volumes],
                  "hosts": connected_hosts(volumes)}
        if not ok and action == "eject_volume":
            try:
                result["eject_failure"] = network_mounts.eject_diagnostics(volume_id, error)
            except (OSError, RuntimeError, subprocess.SubprocessError):
                result["eject_failure"] = {"id": volume_id, "name": "Network drive", "message": error,
                                           "processes": [], "limited": True}
        try:
            state = connection_groups.remember_mounts(volumes)
            library = library_dict(state, volumes or ())
            library["hosts"] = result["hosts"] + library["hosts"]
            result.update(library)
        except (OSError, ValueError, KeyError, TypeError):
            # A damaged history file must not hide live drives or disable eject.
            result["storage_error"] = "Saved connections could not be read. Your connected drives are still available."
        return result
    if action == "saved":
        return {"hosts": [host_dict(h) for h in config_loader.load_hosts(config)], "ok": True}
    if action == "scan":
        hosts = lan_scanner.scan_all_network_hosts()
        return {"ok": True, "hosts": [value for host in hosts if (value := discovered_dict(host))]}
    address = request.get("address", "")
    if not isinstance(address, str) or not address or len(address) > 253 or any(c in address for c in '/@?#\\\n\r\t '):
        raise ValueError("Enter a valid server address.")
    username, password = request.get("username", ""), request.get("password", "")
    if action == "shares":
        shares, error = lan_scanner.list_shares_for_host(address, username, password)
        return {"ok": not bool(error), "error": error,
                "drives": [drive_dict(ShareItem(s, address, request.get("name") or address)) for s in shares]}
    if action == "save":
        hosts = config_loader.load_hosts(config)
        entry = HostEntry.from_dict({"id": address, "name": request.get("name") or address,
                                     "ip_or_hostname": address, "shares": request.get("shares", [])})
        hosts = [h for h in hosts if h.ip_or_hostname != address] + [entry]
        config_loader.save_hosts(hosts, config)
        return {"ok": True, "hosts": [host_dict(h) for h in hosts]}
    if action == "finder":
        return {"ok": mounter.open_server_in_finder(address, username or None, password or None)}
    name = request.get("share", "")
    if not isinstance(name, str) or not name or name in (".", "..") or '/' in name or '\x00' in name:
        raise ValueError("Choose a valid shared drive.")
    share = ShareItem(name, address, request.get("name") or address)
    if action == "mount":
        ok = mounter.mount_share(share, username, password)
        if ok and host_identity.hostname(address):
            try:
                connection_groups.save_endpoint(f"smb://{address}/{quote(name, safe='')}")
            except (OSError, ValueError):
                logging.warning("The drive connected, but its hostname could not be saved.")
    elif action == "eject":
        ok = mounter.unmount_share(share)
    elif action == "reveal":
        ok = share.is_mounted and mounter.reveal_in_finder(share.mount_point)
    elif action == "status":
        ok = True
    else:
        raise ValueError("Unknown action.")
    return {"ok": bool(ok), "error": share.error_message, "drives": [drive_dict(share)]}


def main():
    logging.basicConfig(stream=sys.stderr, level=logging.WARNING)
    try:
        raw = sys.stdin.buffer.readline(1024 * 1024 + 1)
        if len(raw) > 1024 * 1024:
            raise ValueError("Request is too large.")
        request = json.loads(raw)
        if not isinstance(request, dict):
            raise ValueError("Invalid request.")
        response = dispatch(request)
    except Exception as exc:
        response = {"ok": False, "error": str(exc)}
    sys.stdout.write(json.dumps(response, ensure_ascii=False) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
