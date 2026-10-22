"""Find possible SMB destinations; a matching share name is not disk identity."""
from concurrent.futures import ThreadPoolExecutor
from src.services import connection_groups, host_identity, lan_scanner, network_mounts


def find_candidates(drive_id):
    drive = next((d for d in connection_groups.load_state()['drives'] if d['id'] == drive_id), None)
    if not drive or drive.get('protocol') == 'webdav':
        raise ValueError('Choose a saved SMB drive.')
    hosts = lan_scanner.merge_connected_hosts(lan_scanner.scan_all_network_hosts(), network_mounts.list_network_mounts())
    destinations = {}
    for host in hosts:
        address = host_identity.connection_address(host)
        if address:
            destinations.setdefault(network_mounts._host_key(address), (address, host.name))
    def check(item):
        address, name = item
        shares, error = lan_scanner.list_shares_for_host(address)
        if not error and drive['share'] in shares:
            return {'id': address, 'name': name, 'address': address, 'saved': False, 'drives': []}
    with ThreadPoolExecutor(max_workers=8) as pool:
        matches = [m for m in pool.map(check, destinations.values()) if m]
    return sorted(matches, key=lambda m: m['name'].casefold())


def relocate(drive_id, address):
    # Recheck the selected candidate using only the destination's own OS session.
    shares, error = lan_scanner.list_shares_for_host(address)
    with connection_groups._locked() as state:
        drive = next((d for d in state['drives'] if d['id'] == drive_id), None)
        if not drive or drive.get('protocol') == 'webdav':
            raise ValueError('This saved SMB drive no longer exists.')
        if error or drive['share'] not in shares:
            raise ValueError('This share is no longer available. Sign in to this server in Finder and search again.')
        previous = drive['address']
        history = drive.setdefault('previous_addresses', [])
        if previous != address and previous not in history:
            history.append(previous)
        drive['address'] = address
        drive['server_name'] = address
        drive.pop('url', None)
        duplicates = {d['id'] for d in state['drives'] if d['id'] != drive_id
                      and d.get('share') == drive['share']
                      and network_mounts._host_key(d['address']) == network_mounts._host_key(address)
                      and d.get('protocol') != 'webdav'}
        state['drives'] = [d for d in state['drives'] if d['id'] not in duplicates]
        for group in state['groups']:
            group['drive_ids'] = list(dict.fromkeys(drive_id if i in duplicates else i for i in group['drive_ids']))
        # Keep the saved identifier so all group memberships survive the move.
        connection_groups._write(state)
        return state
