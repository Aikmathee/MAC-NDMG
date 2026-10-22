import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from types import SimpleNamespace
from src.services import connection_groups, drive_recovery


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = patch.object(connection_groups, 'state_path', return_value=Path(self.temp.name)/'connections.json')
        self.path.start()
        self.addCleanup(self.path.stop)
        self.drive = connection_groups.endpoint_target('smb://old.local/Media')
        with connection_groups._locked() as state:
            state['drives'] = [self.drive]
            state['groups'] = [{'id':'group', 'name':'Work', 'drive_ids':[self.drive['id']]}]
            connection_groups._write(state)

    def test_relocation_preserves_group_and_original_address(self):
        with patch.object(drive_recovery.lan_scanner, 'list_shares_for_host', return_value=(['Media'], None)) as listing:
            state = drive_recovery.relocate(self.drive['id'], 'new.local')
        listing.assert_called_once_with('new.local')
        self.assertEqual(state['drives'][0]['id'], self.drive['id'])
        self.assertEqual(state['groups'][0]['drive_ids'], [self.drive['id']])
        self.assertEqual(state['drives'][0]['previous_addresses'], ['old.local'])
        self.assertNotIn('url', state['drives'][0])

    def test_missing_share_does_not_change_history(self):
        with patch.object(drive_recovery.lan_scanner, 'list_shares_for_host', return_value=([], 'offline')):
            with self.assertRaises(ValueError): drive_recovery.relocate(self.drive['id'], 'new.local')
        self.assertEqual(connection_groups.load_state()['drives'][0]['address'], 'old.local')

    def test_search_keeps_ambiguous_matches_and_uses_no_credentials(self):
        hosts = [SimpleNamespace(name=n, address=n) for n in ['one.local', 'two.local']]
        with patch.object(drive_recovery.lan_scanner, 'scan_all_network_hosts', return_value=hosts), \
             patch.object(drive_recovery.network_mounts, 'list_network_mounts', return_value=[]), \
             patch.object(drive_recovery.lan_scanner, 'merge_connected_hosts', return_value=hosts), \
             patch.object(drive_recovery.host_identity, 'connection_address', side_effect=lambda h:h.address), \
             patch.object(drive_recovery.lan_scanner, 'list_shares_for_host', return_value=(['Media'], None)) as listing:
            matches = drive_recovery.find_candidates(self.drive['id'])
        self.assertEqual(len(matches), 2)
        self.assertTrue(all(len(c.args)==1 and not c.kwargs for c in listing.call_args_list))

    def test_webdav_is_not_searched(self):
        with self.assertRaises(ValueError): drive_recovery.find_candidates('unknown')

    def test_destination_already_saved_merges_memberships(self):
        other = connection_groups.endpoint_target('smb://new.local/Media')
        with connection_groups._locked() as state:
            state['drives'].append(other)
            state['groups'].append({'id':'second', 'name':'Other', 'drive_ids':[other['id'], self.drive['id']]})
            connection_groups._write(state)
        with patch.object(drive_recovery.lan_scanner, 'list_shares_for_host', return_value=(['Media'], None)):
            state = drive_recovery.relocate(self.drive['id'], 'new.local')
        self.assertEqual(len(state['drives']), 1)
        self.assertTrue(all(g['drive_ids'] == [self.drive['id']] for g in state['groups']))

    def test_monitor_does_not_duplicate_relocated_drive(self):
        with patch.object(drive_recovery.lan_scanner, 'list_shares_for_host', return_value=(['Media'], None)):
            drive_recovery.relocate(self.drive['id'], 'new.local')
        volume = SimpleNamespace(filesystem='smbfs', address='new.local', share='Media', server_name='New')
        state = connection_groups.remember_mounts([volume])
        self.assertEqual(len(state['drives']), 1)
