import unittest
from types import SimpleNamespace
from unittest.mock import patch
from src.services import network_mounts, mounter
from src.models.share_item import ShareItem
from src.native_bridge import dispatch


SAMPLE = '''/dev/disk3s1 on / (apfs, local, read-only)
//editor:secret@nas-a.local/Studio%20Footage on /Volumes/Studio Footage (smbfs, nodev, nosuid)
//editor@nas-b.local/Studio%20Footage on /Volumes/Studio Footage-1 (smbfs, nodev, nosuid)
//user@Studio%20Mac._smb._tcp.local/Media on /Volumes/Media (smbfs, nodev)
nas.local:/exports/Archive on /Volumes/Archive (nfs, nodev)
'''


class NetworkMountTests(unittest.TestCase):
    def setUp(self):
        dns = patch('src.services.host_identity.current_addresses', return_value=())
        dns.start()
        self.addCleanup(dns.stop)
        self.volumes = network_mounts.parse_mounts(SAMPLE)
        self.a = next(v for v in self.volumes if v.address == 'nas-a.local')
        self.b = next(v for v in self.volumes if v.address == 'nas-b.local')

    def test_inventory_excludes_local_disks_and_decodes_names(self):
        self.assertEqual(len(self.volumes), 4)
        self.assertEqual(self.a.share, 'Studio Footage')
        self.assertEqual(self.b.mount_point, '/Volumes/Studio Footage-1')

    def test_inventory_never_exposes_credentials(self):
        import json
        payload = json.dumps([v.to_dict() for v in self.volumes])
        self.assertNotIn('secret', payload)
        self.assertNotIn('editor', payload)

    def test_same_share_on_different_servers_has_separate_identity(self):
        self.assertNotEqual(self.a.id, self.b.id)
        with patch.object(network_mounts, 'list_network_mounts', return_value=self.volumes):
            share = ShareItem('Studio Footage', 'nas-b.local', 'NAS B')
            self.assertTrue(share.is_mounted)
            self.assertEqual(share.mount_point, '/Volumes/Studio Footage-1')
            self.assertFalse(ShareItem('Studio Footage', 'other.local', 'Other').is_mounted)

    def test_bonjour_service_name_matches_display_name(self):
        with patch.object(network_mounts, 'list_network_mounts', return_value=self.volumes):
            result = network_mounts.find_mount('192.168.1.12', 'Media', 'Studio Mac')
            self.assertEqual(result.mount_point, '/Volumes/Media')

    def test_duplicate_mount_of_same_share_is_listed_separately(self):
        copies = network_mounts.parse_mounts('//user@nas.local/Media on /Volumes/Media (smbfs, nodev)\n//user@nas.local/Media on /Volumes/Media-1 (smbfs, nodev)')
        self.assertEqual(len(copies), 2)
        self.assertNotEqual(copies[0].id, copies[1].id)

    def test_eject_uses_verified_actual_path_without_force(self):
        with patch.object(network_mounts, 'list_network_mounts', side_effect=[self.volumes, [self.a]]):
            with patch.object(network_mounts.subprocess, 'run', return_value=SimpleNamespace(returncode=0)) as run:
                self.assertEqual(network_mounts.eject_volume(self.b.id), (True, ''))
                self.assertEqual(run.call_args.args[0], ['/usr/sbin/diskutil', 'unmount', '/Volumes/Studio Footage-1'])

    def test_busy_volume_preserves_error_and_does_not_force(self):
        with patch.object(network_mounts, 'list_network_mounts', return_value=self.volumes):
            with patch.object(network_mounts.subprocess, 'run', return_value=SimpleNamespace(returncode=1, stderr='Volume is busy', stdout='')) as run:
                self.assertEqual(network_mounts.eject_volume(self.a.id), (False, 'Volume is busy'))
                self.assertNotIn('force', run.call_args.args[0])

    def test_stale_identity_cannot_eject_replacement_at_same_path(self):
        replacement = network_mounts.parse_mounts('//user@other.local/Studio%20Footage on /Volumes/Studio Footage (smbfs, nodev)')
        with patch.object(network_mounts, 'list_network_mounts', return_value=replacement):
            with patch.object(network_mounts.subprocess, 'run') as run:
                self.assertEqual(network_mounts.eject_volume(self.a.id), (True, ''))
                run.assert_not_called()

    def test_success_is_verified_against_mount_table(self):
        with patch.object(network_mounts, 'list_network_mounts', return_value=self.volumes):
            with patch.object(network_mounts.subprocess, 'run', return_value=SimpleNamespace(returncode=0)):
                self.assertFalse(network_mounts.eject_volume(self.a.id)[0])

    def test_bridge_requires_opaque_volume_identity(self):
        with self.assertRaises(ValueError):
            dispatch({'action': 'eject_volume', 'volume_id': '/Volumes/Studio Footage'})

    def test_mount_table_failure_is_not_reported_as_empty(self):
        with patch.object(network_mounts.subprocess, 'run', return_value=SimpleNamespace(returncode=1)):
            with self.assertRaises(RuntimeError):
                network_mounts.list_network_mounts()

    def test_nfs_ipv6_and_mount_spaces(self):
        values = network_mounts.parse_mounts('[fe80::1]:/exports/Media on /Volumes/Media\\040Drive (nfs, nodev)')
        self.assertEqual(values[0].address, 'fe80::1')
        self.assertEqual(values[0].mount_point, '/Volumes/Media Drive')


if __name__ == '__main__':
    unittest.main()
