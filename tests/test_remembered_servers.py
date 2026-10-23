import unittest
from unittest.mock import patch
from src import native_bridge
from src.services import connection_groups


class RememberedServerTests(unittest.TestCase):
    def state(self):
        return {'drives': [connection_groups.endpoint_target('smb://archive.local/Media'),
                           connection_groups.endpoint_target('smb://archive.local/Projects')], 'groups': []}

    def test_missing_server_remains_saved_without_online_claim(self):
        hosts = native_bridge.remembered_hosts(self.state())
        self.assertEqual(len(hosts), 1)
        self.assertEqual(hosts[0]['address'], 'archive.local')
        self.assertTrue(hosts[0]['saved'])
        self.assertNotIn('discovered', hosts[0])
        self.assertNotIn('ip', hosts[0])

    def test_connections_exposes_known_servers_without_mount_or_scan(self):
        with patch.object(connection_groups, 'remember_mounts', return_value=self.state()), \
             patch.object(native_bridge.network_mounts, 'list_network_mounts', return_value=[]):
            response = native_bridge.dispatch({'action':'connections'})
        self.assertEqual(len(response['hosts']), 1)

    def test_mount_poll_keeps_both_live_and_remembered_servers(self):
        with patch.object(connection_groups, 'remember_mounts', return_value=self.state()), \
             patch.object(native_bridge.network_mounts, 'list_network_mounts', return_value=[]), \
             patch.object(native_bridge, 'connected_hosts', return_value=[{'id':'live','address':'live.local'}]):
            response = native_bridge.dispatch({'action':'mounted'})
        self.assertEqual(len(response['hosts']), 2)

    def test_webdav_and_custom_port_not_exposed_as_portless_smb(self):
        state={'drives':[connection_groups.endpoint_target('https://cloud.example.com/dav'),
                         {'id':'custom', 'address':'nas.local', 'share':'Media', 'url':'smb://nas.local:1445/Media'}], 'groups':[]}
        self.assertEqual(native_bridge.remembered_hosts(state), [])
