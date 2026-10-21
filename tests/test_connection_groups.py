import json
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from src.services import connection_groups as groups, network_mounts
from src.native_bridge import dispatch

SAMPLE = '''//editor:secret@nas-a.local/Studio%20Footage on /Volumes/Studio Footage (smbfs, nodev)
//other@nas-a.local/Studio%20Footage on /Volumes/Studio Footage-1 (smbfs, nodev)
//user@Studio%20Mac._smb._tcp.local/Projects on /Volumes/Projects (smbfs, nodev)
server:/exports/Archive on /Volumes/Archive (nfs, nodev)
'''


class ConnectionGroupsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / 'connections.json'
        self.patch = patch.object(groups, 'state_path', return_value=self.path)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.volumes = network_mounts.parse_mounts(SAMPLE)
        self.state = groups.remember_mounts(self.volumes)
        self.ids = [drive['id'] for drive in self.state['drives']]

    def test_history_deduplicates_multiple_mounts_and_excludes_unsupported_protocol(self):
        self.assertEqual(len(self.ids), 2)
        self.assertEqual(len(set(self.ids)), 2)

    def test_no_passwords_usernames_or_mount_paths_are_saved(self):
        contents = self.path.read_text()
        for secret in ['secret', 'editor', '/Volumes', 'password']:
            self.assertNotIn(secret, contents)

    def test_save_and_reload_group_with_multiple_servers(self):
        state = groups.save_group('Editing room', self.ids)
        self.assertEqual(state['groups'][0]['drive_ids'], self.ids)
        self.assertEqual(groups.load_state()['groups'][0]['name'], 'Editing room')

    def test_group_edit_updates_in_place(self):
        group = groups.save_group('Old', self.ids)['groups'][0]
        state = groups.save_group('New', self.ids[:1], group['id'])
        self.assertEqual(len(state['groups']), 1)
        self.assertEqual(state['groups'][0]['name'], 'New')
        self.assertEqual(state['groups'][0]['drive_ids'], self.ids[:1])

    def test_delete_preserves_history_and_does_not_disconnect(self):
        group = groups.save_group('Editing', self.ids)['groups'][0]
        with patch.object(groups.subprocess, 'run') as run:
            state = groups.delete_group(group['id'])
            run.assert_not_called()
        self.assertEqual(state['groups'], [])
        self.assertEqual(len(state['drives']), 2)

    def test_invalid_group_does_not_overwrite_existing_state(self):
        before = self.path.read_text()
        for name, ids in [(' ', self.ids), ('Editing', []), ('Editing', ['unknown'])]:
            with self.assertRaises(ValueError):
                groups.save_group(name, ids)
            self.assertEqual(self.path.read_text(), before)

    def test_polling_existing_mounts_does_not_rewrite_preferences(self):
        with patch.object(groups, '_write') as write:
            groups.remember_mounts(self.volumes)
            write.assert_not_called()

    def test_already_connected_skips_open(self):
        with patch.object(network_mounts, 'list_network_mounts', return_value=self.volumes):
            with patch.object(groups.subprocess, 'run') as run:
                state, _ = groups.reconnect(self.ids[0])
                self.assertEqual(state, 'connected')
                run.assert_not_called()

    def test_waiting_for_finder_is_not_reported_as_connected(self):
        with patch.object(network_mounts, 'list_network_mounts', return_value=[]):
            with patch.object(groups.subprocess, 'run', return_value=SimpleNamespace(returncode=0)) as run:
                with patch.object(groups.time, 'sleep'):
                    result, _ = groups.reconnect(self.ids[0])
        self.assertEqual(result, 'waiting')
        command = run.call_args.args[0]
        self.assertEqual(command[0], '/usr/bin/open')
        self.assertNotIn('@', command[1])
        self.assertIn('Studio%20Footage', command[1])

    def test_reconnect_checks_actual_mount_after_finder_opens(self):
        with patch.object(network_mounts, 'list_network_mounts', side_effect=[[], self.volumes]):
            with patch.object(groups.subprocess, 'run', return_value=SimpleNamespace(returncode=0)):
                with patch.object(groups.time, 'sleep'):
                    self.assertEqual(groups.reconnect(self.ids[0])[0], 'connected')

    def test_unknown_destination_cannot_launch_arbitrary_url(self):
        with patch.object(groups.subprocess, 'run') as run:
            with self.assertRaises(ValueError):
                groups.reconnect('smb://untrusted/drive')
            run.assert_not_called()

    def test_concurrent_poll_and_group_writes_preserve_all_groups(self):
        def save(index):
            return groups.save_group(f'Group {index}', self.ids)
        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(save, range(8)))
        self.assertEqual(len(groups.load_state()['groups']), 8)
        self.assertEqual(list(self.path.parent.glob('.connections-*')), [])

    def test_corrupt_history_does_not_hide_live_connected_drives(self):
        self.path.write_text('{broken')
        with patch.object(network_mounts, 'list_network_mounts', return_value=self.volumes):
            result = dispatch({'action': 'mounted'})
        self.assertTrue(result['ok'])
        self.assertEqual(len(result['volumes']), len(self.volumes))
        self.assertIn('storage_error', result)
        self.assertEqual(self.path.read_text(), '{broken')

    def test_bridge_returns_groups_without_reconnecting_on_load(self):
        groups.save_group('Editing', self.ids)
        with patch.object(network_mounts, 'list_network_mounts', return_value=self.volumes):
            with patch.object(groups.subprocess, 'run') as run:
                result = dispatch({'action': 'connections'})
                run.assert_not_called()
        self.assertTrue(result['ok'])
        self.assertEqual(result['groups'][0]['name'], 'Editing')


if __name__ == '__main__':
    unittest.main()
