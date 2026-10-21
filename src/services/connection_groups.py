"""Remember SMB destinations and named groups, without storing credentials."""
from __future__ import annotations

from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
from urllib.parse import quote
import uuid

from src.services import config_loader, network_mounts


def state_path() -> Path:
    return config_loader.default_config_path().parent / 'connections.json'


def _empty():
    return {'version': 1, 'drives': [], 'groups': []}


@contextmanager
def _locked():
    path = state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path.with_suffix('.lock'), 'a', encoding='utf-8') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            state = json.loads(path.read_text()) if path.exists() else _empty()
            if not isinstance(state, dict) or not isinstance(state.get('drives'), list) or not isinstance(state.get('groups'), list):
                raise ValueError('Saved connections could not be read.')
            yield state
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def _write(state):
    path = state_path()
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.connections-', suffix='.json')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as handle:
            json.dump(state, handle, ensure_ascii=False, indent=2)
            handle.write('\n')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def target_for_volume(volume):
    if volume.filesystem != 'smbfs':
        return None
    key = f'smbfs\0{network_mounts._host_key(volume.address)}\0{volume.share}'
    return {'id': hashlib.sha256(key.encode()).hexdigest(), 'name': volume.share,
            'address': volume.address, 'server_name': volume.server_name, 'share': volume.share}


def remember_mounts(volumes):
    with _locked() as state:
        ids = {drive['id'] for drive in state['drives']}
        changed = False
        for volume in volumes:
            target = target_for_volume(volume)
            if target and target['id'] not in ids:
                state['drives'].append(target)
                ids.add(target['id'])
                changed = True
        if changed:
            _write(state)
        return state


def load_state():
    with _locked() as state:
        return state


def save_group(name, drive_ids, group_id=None):
    if not isinstance(name, str) or not name.strip() or len(name.strip()) > 80:
        raise ValueError('Enter a group name of up to 80 characters.')
    if not isinstance(drive_ids, list) or not drive_ids or len(drive_ids) > 500 or not all(isinstance(i, str) for i in drive_ids):
        raise ValueError('Select at least one saved drive.')
    with _locked() as state:
        known = {drive['id'] for drive in state['drives']}
        if not set(drive_ids).issubset(known):
            raise ValueError('Some selected drives are no longer available. Refresh and try again.')
        if group_id is not None and not any(group['id'] == group_id for group in state['groups']):
            raise ValueError('This group no longer exists.')
        group = {'id': group_id or str(uuid.uuid4()), 'name': name.strip(), 'drive_ids': list(dict.fromkeys(drive_ids))}
        state['groups'] = [g for g in state['groups'] if g['id'] != group['id']] + [group]
        _write(state)
        return state


def delete_group(group_id):
    with _locked() as state:
        state['groups'] = [group for group in state['groups'] if group['id'] != group_id]
        _write(state)
        return state


def is_connected(drive, volumes):
    return any(volume.filesystem == 'smbfs' and volume.share == drive['share']
               and network_mounts._host_key(volume.address) == network_mounts._host_key(drive['address'])
               for volume in volumes)


def reconnect(drive_id):
    # Accept only an identifier from local history, never an arbitrary URL or password.
    state = load_state()
    drive = next((item for item in state['drives'] if item['id'] == drive_id), None)
    if drive is None:
        raise ValueError('This saved drive no longer exists.')
    volumes = network_mounts.list_network_mounts()
    if is_connected(drive, volumes):
        return 'connected', volumes
    address = drive['address']
    if ':' in address and not address.startswith('['):
        address = f'[{address}]'
    uri = f"smb://{quote(address, safe='[]:.')}/{quote(drive['share'], safe='')}"
    result = subprocess.run(['/usr/bin/open', uri], capture_output=True, text=True, timeout=10)
    if result.returncode:
        raise RuntimeError('Finder could not open this drive. Check that the server is available.')
    for _ in range(5):
        time.sleep(0.4)
        volumes = network_mounts.list_network_mounts()
        if is_connected(drive, volumes):
            return 'connected', volumes
    # Opening Finder isn't proof of a successful mount. The UI shows this as
    # waiting and its normal live monitor will reflect the eventual result.
    return 'waiting', volumes
