import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from src.native_bridge import dispatch, library_dict
from src.services import host_identity as identity, network_mounts, connection_groups as groups
from src.services.lan_scanner import DiscoveredHost


class HostIdentityTests(unittest.TestCase):
    def tearDown(self):
        identity.current_addresses.cache_clear()

    def test_dhcp_change_does_not_change_destination_or_identity(self):
        for ip in ['192.0.2.10', '192.0.2.99']:
            with patch('src.native_bridge.lan_scanner.scan_all_network_hosts',
                       return_value=[DiscoveredHost('Editing Mac', 'editing-mac.local', ip)]):
                host = dispatch({'action': 'scan'})['hosts'][0]
            self.assertEqual(host['address'], 'editing-mac.local')
            self.assertEqual(host['id'], 'editing-mac.local')
            self.assertEqual(host['ip'], ip)

    def test_display_name_is_not_invented_into_a_hostname(self):
        host = DiscoveredHost('Editing Mac (2)', 'Editing Mac (2)', '192.0.2.10')
        self.assertEqual(identity.connection_address(host), '192.0.2.10')
        self.assertEqual(identity.connection_address(DiscoveredHost('Unresolved', 'Invalid Name', '')), '')

    def test_dns_and_vpn_hostname_are_preserved(self):
        for hostname in ['nas.example.test', 'editing-mac.example.ts.net', 'editing-mac.local.']:
            self.assertEqual(identity.connection_address(DiscoveredHost('Server', hostname, '192.0.2.10')),
                             hostname.rstrip('.'))

    def test_unavailable_hostname_does_not_fall_back_to_an_old_ip(self):
        with patch.object(identity.socket, 'getaddrinfo', side_effect=OSError):
            self.assertEqual(identity.current_addresses('offline.local'), ())
            self.assertFalse(identity.matches_ip('offline.local', '192.0.2.10'))

    def test_mount_check_matches_current_ip_and_rejects_old_ip(self):
        volumes = network_mounts.parse_mounts('//user@192.0.2.99/Media on /Volumes/Media (smbfs, nodev)')
        with patch.object(identity, 'current_addresses', return_value=('192.0.2.99',)):
            with patch.object(network_mounts, 'list_network_mounts', return_value=volumes):
                self.assertIsNotNone(network_mounts.find_mount('editing-mac.local', 'Media'))
                self.assertIsNone(network_mounts.find_mount('editing-mac.local', 'Other'))
            self.assertTrue(identity.matches_ip('editing-mac.local', '192.0.2.99'))
            self.assertFalse(identity.matches_ip('editing-mac.local', '192.0.2.10'))

    def test_group_reconnect_uses_hostname_and_preserves_group_after_ip_change(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(groups, 'state_path', return_value=Path(folder)/'connections.json'):
            state = groups.save_endpoint('smb://editing-mac.local/Media')
            drive = state['drives'][0]
            groups.save_group('Editing', [drive['id']])
            before = groups.load_state()
            with patch.object(network_mounts, 'list_network_mounts', return_value=[]), \
                 patch.object(groups.subprocess, 'run', return_value=SimpleNamespace(returncode=0)) as run, \
                 patch.object(groups.time, 'sleep'):
                self.assertEqual(groups.reconnect(drive['id'])[0], 'waiting')
                self.assertEqual(run.call_args.args[0][1], 'smb://editing-mac.local/Media')
            self.assertEqual(groups.load_state(), before)
            volumes = network_mounts.parse_mounts('//user@192.0.2.99/Media on /Volumes/Media (smbfs, nodev)')
            with patch.object(identity, 'current_addresses', return_value=('192.0.2.99',)):
                self.assertTrue(groups.is_connected(drive, volumes))
                self.assertEqual(library_dict(before, volumes)['remembered'][0]['mounted_ids'], [volumes[0].id])
            self.assertNotIn('192.0.2.99', (Path(folder)/'connections.json').read_text())

    def test_numeric_mount_does_not_replace_a_known_hostname_destination(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(groups, 'state_path', return_value=Path(folder)/'connections.json'):
            known = groups.save_endpoint('smb://editing-mac.local/Media')['drives'][0]
            volumes = network_mounts.parse_mounts('//user@192.0.2.99/Media on /Volumes/Media (smbfs, nodev)')
            with patch.object(identity, 'current_addresses', return_value=('192.0.2.99',)):
                state = groups.remember_mounts(volumes)
            self.assertEqual(state['drives'], [known])

    def test_verified_hostname_mount_is_remembered_by_name(self):
        with patch('src.native_bridge.mounter.mount_share', return_value=True), \
             patch('src.native_bridge.drive_dict', return_value={}), \
             patch.object(groups, 'save_endpoint') as save:
            dispatch({'action': 'mount', 'address': 'editing-mac.local', 'share': 'Media Files'})
            save.assert_called_once_with('smb://editing-mac.local/Media%20Files')

    def test_old_ip_history_is_not_silently_reassigned_to_another_machine(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(groups, 'state_path', return_value=Path(folder)/'connections.json'):
            old = network_mounts.parse_mounts('//user@192.0.2.10/Media on /Volumes/Media (smbfs, nodev)')
            state = groups.remember_mounts(old)
            group = groups.save_group('Keep', [state['drives'][0]['id']])['groups'][0]
            new = network_mounts.parse_mounts('//user@editing-mac.local/Media on /Volumes/Media (smbfs, nodev)')
            updated = groups.remember_mounts(new)
            self.assertEqual(updated['groups'][0], group)
            self.assertEqual(updated['drives'][0]['address'], '192.0.2.10')
