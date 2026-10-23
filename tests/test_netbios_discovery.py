import socket
import subprocess
import unittest
from unittest.mock import patch
from src.services import host_identity, lan_scanner


class NetBIOSDiscoveryTests(unittest.TestCase):
    def test_short_hostname_resolves_when_dns_is_missing(self):
        host_identity.current_addresses.cache_clear()
        self.addCleanup(host_identity.current_addresses.cache_clear)
        result = subprocess.CompletedProcess([], 0, 'Got response from 192.0.2.7\nIP address of studio-nas: 192.0.2.7\n', '')
        with patch.object(host_identity.socket, 'getaddrinfo', side_effect=socket.gaierror()), \
             patch.object(host_identity.subprocess, 'run', return_value=result) as run:
            self.assertEqual(host_identity.current_addresses('studio-nas'), ('192.0.2.7',))
        self.assertEqual(run.call_args.args[0], ['/usr/bin/smbutil','lookup','studio-nas'])

    def test_no_netbios_lookup_for_fqdn(self):
        with patch.object(host_identity.subprocess, 'run') as run:
            self.assertEqual(host_identity.netbios_addresses('nas.example.com'), ())
        run.assert_not_called()

    def test_subnet_server_gets_verified_name(self):
        result = subprocess.CompletedProcess([], 0, 'Workgroup: WORKGROUP\nServer: STUDIO-NAS\n', '')
        with patch.object(lan_scanner.socket, 'gethostbyaddr', side_effect=socket.herror()), \
             patch.object(lan_scanner.subprocess, 'run', return_value=result), \
             patch.object(host_identity, 'current_addresses', return_value=('192.0.2.7',)):
            host=lan_scanner.resolve_subnet_host('192.0.2.7')
        self.assertEqual((host.name,host.host,host.source),('STUDIO-NAS','studio-nas','netbios'))

    def test_unverified_name_never_redirects_connection(self):
        result = subprocess.CompletedProcess([], 0, 'Server: STUDIO-NAS\n', '')
        with patch.object(lan_scanner.socket, 'gethostbyaddr', side_effect=socket.herror()), \
             patch.object(lan_scanner.subprocess, 'run', return_value=result), \
             patch.object(host_identity, 'current_addresses', return_value=('192.0.2.8',)):
            host=lan_scanner.resolve_subnet_host('192.0.2.7')
        self.assertEqual(host.host,'192.0.2.7')

    def test_timeout_keeps_numeric_discovered_server(self):
        with patch.object(lan_scanner.socket, 'gethostbyaddr', side_effect=socket.herror()), \
             patch.object(lan_scanner.subprocess, 'run', side_effect=subprocess.TimeoutExpired('smbutil',2)):
            self.assertEqual(lan_scanner.resolve_subnet_host('192.0.2.7').host,'192.0.2.7')
