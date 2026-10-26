"""Read-only scenario regressions: never require a real server or user account."""
import socket
import subprocess
import unittest
from unittest.mock import patch
from types import SimpleNamespace
from src.services import connection_groups, host_identity, lan_scanner


class NetworkResilienceTests(unittest.TestCase):
    def tearDown(self):
        host_identity.current_addresses.cache_clear()

    def test_new_request_re_resolves_netbios_after_dhcp_change(self):
        for ip in ['192.0.2.10', '192.0.2.99']:
            host_identity.current_addresses.cache_clear()  # Each real bridge request is a new process.
            result=subprocess.CompletedProcess([],0,f'IP address of studio-nas: {ip}\n','')
            with patch.object(host_identity.socket,'getaddrinfo',side_effect=socket.gaierror()), \
                 patch.object(host_identity.subprocess,'run',return_value=result):
                self.assertEqual(host_identity.current_addresses('studio-nas'),(ip,))

    def test_wrong_account_is_returned_as_failure_without_retrying_other_accounts(self):
        result=subprocess.CompletedProcess([],1,'','Authentication error')
        with patch.object(lan_scanner.subprocess,'run',return_value=result) as run:
            shares,error=lan_scanner.list_shares_for_host('nas.local','account','incorrect')
        self.assertEqual(shares,[])
        self.assertIn('Authentication',error)
        self.assertEqual(run.call_count,1)

    def test_disconnected_network_does_not_claim_finder_open_was_mounted(self):
        drive={'id':'saved','name':'Media','share':'Media','address':'nas.local','server_name':'NAS'}
        with patch.object(connection_groups,'load_state',return_value={'drives':[drive]}), \
             patch.object(connection_groups.network_mounts,'list_network_mounts',return_value=[]), \
             patch.object(connection_groups.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'','')), \
             patch.object(connection_groups.time,'sleep'):
            status,volumes=connection_groups.reconnect('saved')
        self.assertEqual(status,'waiting')
        self.assertEqual(volumes,[])

    def test_reconnect_already_mounted_does_not_open_a_duplicate(self):
        drive={'id':'saved','name':'Media','share':'Media','address':'nas.local','server_name':'NAS'}
        volume=SimpleNamespace(filesystem='smbfs',share='Media',address='nas.local')
        with patch.object(connection_groups,'load_state',return_value={'drives':[drive]}), \
             patch.object(connection_groups.network_mounts,'list_network_mounts',return_value=[volume]), \
             patch.object(connection_groups.subprocess,'run') as run:
            status,_=connection_groups.reconnect('saved')
        self.assertEqual(status,'connected')
        run.assert_not_called()
