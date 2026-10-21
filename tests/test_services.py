import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from types import SimpleNamespace
from src.models.share_item import HostEntry
from src.services import config_loader, lan_scanner, mounter


class ServiceTests(unittest.TestCase):
    def test_uri_encodes_credentials_and_share(self):
        self.assertEqual(mounter.build_smb_uri('a@b', 'p#:/', 'nas.local', 'Studio Footage'),
                         'smb://a%40b:p%23%3A%2F@nas.local/Studio%20Footage')

    def test_share_parser_preserves_spaces_and_ignores_summary(self):
        output = 'Share Type Comments\n-------------------\nStudio Footage    Disk   Media\nIPC$   IPC\n2 shares listed\n'
        with patch.object(lan_scanner.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout=output, stderr='')):
            self.assertEqual(lan_scanner.list_shares_for_host('nas.local'), (['Studio Footage'], ''))

    def test_preferences_round_trip(self):
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / 'nested' / 'shares.json')
            hosts = [HostEntry.from_dict(dict(id='one', name='Studio', ip_or_hostname='nas.local', shares=['Media']))]
            config_loader.save_hosts(hosts, path)
            self.assertEqual(config_loader.load_hosts(path)[0].shares[0].name, 'Media')
            self.assertNotIn('password', Path(path).read_text())
            self.assertEqual(list(Path(path).parent.glob('.shares-*')), [])

    def test_clean_install_has_no_demo_servers(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(config_loader, 'default_config_path', return_value=Path(directory) / 'missing.json'):
                self.assertEqual(config_loader.load_hosts(), [])

    def test_explicit_missing_config_reports_error(self):
        with self.assertRaises(FileNotFoundError):
            config_loader.load_hosts('/nonexistent/ndmg-config.json')


if __name__ == '__main__':
    unittest.main()
