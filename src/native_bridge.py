"""One-request JSON bridge for the native macOS UI; no HTTP server or open port."""
from __future__ import annotations

import json
import logging
import sys
from src.models.share_item import HostEntry, ShareItem
from src.services import config_loader, lan_scanner, mounter


def drive_dict(share):
    share.refresh_status()
    return {"id": share.name, "name": share.name, "status": share.status.value,
            "error": share.error_message}


def host_dict(host):
    return {"id": host.ip_or_hostname, "name": host.name, "address": host.ip_or_hostname,
            "saved": True, "drives": [drive_dict(s) for s in host.shares]}


def dispatch(request):
    action = request.get("action")
    config = request.get("config")
    if action == "saved":
        return {"hosts": [host_dict(h) for h in config_loader.load_hosts(config)], "ok": True}
    if action == "scan":
        hosts = lan_scanner.scan_all_network_hosts()
        return {"ok": True, "hosts": [
            {"id": h.ip or h.host, "name": h.name, "address": h.ip or h.host,
             "saved": False, "drives": []} for h in hosts]}
    address = request.get("address", "")
    if not isinstance(address, str) or not address or len(address) > 253 or any(c in address for c in '/@?#\\\n\r\t '):
        raise ValueError("Enter a valid server address.")
    username, password = request.get("username", ""), request.get("password", "")
    if action == "shares":
        shares, error = lan_scanner.list_shares_for_host(address, username, password)
        return {"ok": not bool(error), "error": error,
                "drives": [drive_dict(ShareItem(s, address, address)) for s in shares]}
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
    share = ShareItem(name, address, address)
    if action == "mount":
        ok = mounter.mount_share(share, username, password)
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
