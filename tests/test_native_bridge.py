import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from src.native_bridge import dispatch
from src.services.lan_scanner import DiscoveredHost


class NativeBridgeTests(unittest.TestCase):
    def test_invalid_server_address_rejected_before_mounting(self):
        with self.assertRaises(ValueError):
            dispatch({'action': 'mount', 'address': 'nas.local/other', 'share': 'Media'})

    def test_bridge_preserves_saved_servers_without_credentials(self):
        with tempfile.TemporaryDirectory() as folder:
            config = str(Path(folder) / 'shares.json')
            Path(config).write_text('{"hosts": []}')
            result = dispatch({'action': 'save', 'config': config, 'address': 'nas.local',
                               'name': 'Studio', 'shares': ['Media'], 'password': 'do-not-store'})
            self.assertTrue(result['ok'])
            self.assertNotIn('do-not-store', Path(config).read_text())
            loaded = dispatch({'action': 'saved', 'config': config})
            self.assertEqual(loaded['hosts'][0]['drives'][0]['name'], 'Media')

    def test_scan_response_uses_resolved_address(self):
        with patch('src.native_bridge.lan_scanner.scan_all_network_hosts', return_value=[DiscoveredHost('Studio', 'studio.local', '192.168.1.10')]):
            result = dispatch({'action': 'scan'})
            self.assertEqual(result['hosts'][0]['address'], '192.168.1.10')
            self.assertFalse(result['hosts'][0]['saved'])

    def test_share_name_cannot_escape_volumes(self):
        with self.assertRaises(ValueError):
            dispatch({'action': 'reveal', 'address': 'nas.local', 'share': '../private'})

    def test_share_loading_reports_auth_failure(self):
        with patch('src.native_bridge.lan_scanner.list_shares_for_host', return_value=([], 'Authentication failed')):
            result = dispatch({'action': 'shares', 'address': 'nas.local'})
            self.assertFalse(result['ok'])
            self.assertEqual(result['error'], 'Authentication failed')


if __name__ == '__main__':
    unittest.main()
