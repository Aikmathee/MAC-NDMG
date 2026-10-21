import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from src.services import remote_endpoints as endpoints, connection_groups as groups, network_mounts
from src.native_bridge import dispatch


class RemoteEndpointTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        mock = patch.object(groups, 'state_path', return_value=Path(folder.name) / 'connections.json')
        mock.start()
        self.addCleanup(mock.stop)

    def test_magicdns_and_tailscale_share(self):
        for address in ['nas.tail123.ts.net', '100.101.102.103', '[fd7a:115c:a1e0::1]']:
            state = dispatch({'action': 'save_endpoint', 'url': f'smb://{address}/Studio%20Media'})
            self.assertTrue(state['ok'])
            self.assertEqual(state['remembered'][-1]['share'], 'Studio Media')

    def test_validation_never_persists_credentials_or_tokens(self):
        for url in ['ftp://nas/files', 'sftp://nas/files', 'https://user:secret@nas/dav',
                    'https://nas/dav?token=secret', 'https://nas/dav#secret', 'smb://nas/',
                    'https://nas:99999/dav', 'https://bad host/dav', 'https://nas/\nsecret']:
            with self.subTest(url=url), self.assertRaises(ValueError):
                groups.save_endpoint(url)
        self.assertEqual(groups.load_state()['drives'], [])

    def test_webdav_root_port_and_case_sensitive_paths(self):
        url = endpoints.normalize_url('https://NAS.example:8443/DAV/My Files/')
        self.assertEqual(url, 'https://nas.example:8443/DAV/My%20Files')
        sample = 'https://user:secret@nas.example:8443/DAV/My%20Files on /Volumes/Cloud (webdav, nodev)\nhttps://nas.example/ on /Volumes/Root (webdav, nodev)'
        volumes = network_mounts.parse_mounts(sample)
        self.assertEqual(len(volumes), 2)
        drive = groups.save_endpoint(url)['drives'][0]
        self.assertTrue(groups.is_connected(drive, volumes))
        self.assertNotIn('secret', str([v.to_dict() for v in volumes]))
        self.assertFalse(groups.is_connected(dict(drive, url=url.lower()), volumes))

    def test_mixed_groups_and_native_webdav_mount(self):
        smb = groups.save_endpoint('smb://nas/Projects')['drives'][0]
        dav = groups.save_endpoint('https://cloud.example/dav')['drives'][-1]
        group = groups.save_group('Remote editing', [smb['id'], dav['id']])['groups'][0]
        self.assertEqual(len(group['drive_ids']), 2)
        volumes = network_mounts.parse_mounts('https://cloud.example/dav on /Volumes/Cloud (webdav, nodev)')
        with patch.object(network_mounts, 'list_network_mounts', side_effect=[[], volumes]), patch.object(endpoints, 'mount_webdav') as mount:
            status, _ = groups.reconnect(dav['id'])
            self.assertEqual(status, 'connected')
            mount.assert_called_once_with('https://cloud.example/dav')

    def test_opening_does_not_claim_connected_and_encoded_smb_path(self):
        drive = groups.save_endpoint('smb://nas.tail123.ts.net/Projects%20Archive')['drives'][0]
        with patch.object(network_mounts, 'list_network_mounts', return_value=[]), patch.object(groups.subprocess, 'run') as run, patch.object(groups.time, 'sleep'):
            run.return_value.returncode = 0
            self.assertEqual(groups.reconnect(drive['id'])[0], 'waiting')
            self.assertEqual(run.call_args.args[0], ['/usr/bin/open', drive['url']])
