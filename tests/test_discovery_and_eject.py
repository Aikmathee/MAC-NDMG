import subprocess
import unittest
from types import SimpleNamespace
from unittest.mock import patch
from src.services import lan_scanner, network_mounts, host_identity, mounter
from src.native_bridge import connected_hosts, dispatch


class DiscoveryAndSessionTests(unittest.TestCase):
    def setUp(self):
        dns = patch.object(host_identity, 'current_addresses', return_value=())
        dns.start()
        self.addCleanup(dns.stop)
        self.volumes = network_mounts.parse_mounts('//user@editing-node/Media on /Volumes/Media (smbfs, nodev)\n//user@editing-node/Backup on /Volumes/Backup (smbfs, nodev)')

    def test_mounted_finder_server_is_discovered_without_bonjour(self):
        with patch.object(lan_scanner, 'discover_bonjour_smb', return_value=[]), \
             patch.object(lan_scanner, 'scan_subnet_fast', return_value=[]), \
             patch.object(network_mounts, 'list_network_mounts', return_value=self.volumes):
            hosts = dispatch({'action': 'scan'})['hosts']
        self.assertEqual(len(hosts), 1)
        self.assertEqual(hosts[0]['address'], 'editing-node')
        self.assertEqual(hosts[0]['source'], 'connected')

    def test_bonjour_canonical_name_wins_over_short_mount_alias(self):
        bonjour = lan_scanner.DiscoveredHost('Editing node', 'editing-node.local', '192.0.2.55', 'bonjour')
        self.assertEqual(lan_scanner.merge_connected_hosts([bonjour], self.volumes), [bonjour])

    def test_multiple_shares_make_one_server_and_local_disks_are_excluded(self):
        self.assertEqual(len(connected_hosts(self.volumes)), 1)
        local = SimpleNamespace(filesystem='apfs', address='local')
        self.assertEqual(connected_hosts([local]), [])

    def test_bonjour_service_mount_preserves_actual_endpoint(self):
        volumes = network_mounts.parse_mounts('//user@Editing%20Mac._smb._tcp.local/Media on /Volumes/Media (smbfs, nodev)')
        host = connected_hosts(volumes)[0]
        self.assertEqual(host['address'], 'editing%20mac._smb._tcp.local')
        self.assertEqual(host['name'].casefold(), 'editing mac')
        self.assertFalse(host_identity.bonjour_service_address('evil/host._smb._tcp.local'))

    def test_mounted_hostname_replaces_duplicate_ip_probe(self):
        probed = lan_scanner.DiscoveredHost('SMB Host', '192.0.2.55', '192.0.2.55')
        with patch.object(host_identity, 'current_addresses', return_value=('192.0.2.55',)):
            merged = lan_scanner.merge_connected_hosts([probed], self.volumes)
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0].host, 'editing-node')
        self.assertEqual(merged[0].source, 'connected')

    def test_bonjour_advertisement_deduplicates_service_instance_mount(self):
        bonjour = lan_scanner.DiscoveredHost('editing Mac', 'editing-mac.local', '192.0.2.55', 'bonjour')
        mounts = network_mounts.parse_mounts('//user@Editing%20Mac._smb._tcp.local/Media on /Volumes/Media (smbfs, nodev)')
        self.assertEqual(lan_scanner.merge_connected_hosts([bonjour], mounts), [bonjour])

    def test_mount_inventory_failure_does_not_discard_discovered_servers(self):
        bonjour = lan_scanner.DiscoveredHost('Editing node', 'editing-node.local', '')
        with patch.object(lan_scanner, 'discover_bonjour_smb', return_value=[bonjour]), \
             patch.object(lan_scanner, 'scan_subnet_fast', return_value=[]), \
             patch.object(network_mounts, 'list_network_mounts', side_effect=RuntimeError):
            self.assertEqual(lan_scanner.scan_all_network_hosts(), [bonjour])

    def test_existing_session_is_requested_without_guest_or_password(self):
        with patch.object(lan_scanner.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout='Media Disk', stderr='')) as run:
            shares, error = lan_scanner.list_shares_for_host('editing-node')
        self.assertEqual(shares, ['Media'])
        self.assertEqual(error, '')
        self.assertEqual(run.call_args.args[0], ['smbutil', 'view', '-N', '//editing-node'])

    def test_no_blank_credentials_are_injected_into_system_signin_url(self):
        self.assertEqual(mounter.build_smb_uri('', '', 'editing-node.local', 'Media Files'), 'smb://editing-node.local/Media%20Files')
        self.assertEqual(mounter.build_smb_uri('editor', '', 'editing-node.local', 'Media'), 'smb://editor@editing-node.local/Media')

    def test_username_only_does_not_prompt_on_hidden_stdin(self):
        with patch.object(lan_scanner.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout='Media Disk', stderr='')) as run:
            lan_scanner.list_shares_for_host('editing-node', 'editor', '')
        self.assertEqual(run.call_args.args[0], ['smbutil', 'view', '-N', '//editor@editing-node'])

    def test_ipv6_mount_destination_is_bracketed(self):
        self.assertEqual(mounter.build_smb_uri('', '', '2001:db8::1', 'Media'), 'smb://[2001:db8::1]/Media')

    def test_password_without_username_does_not_launch_an_interactive_process(self):
        with patch.object(lan_scanner.subprocess, 'run') as run:
            self.assertTrue(lan_scanner.list_shares_for_host('editing-node', '', 'secret')[1])
            run.assert_not_called()


class EjectDiagnosticsTests(unittest.TestCase):
    def setUp(self):
        self.volume = network_mounts.parse_mounts('//user@editing-node/Media on /Volumes/Media (smbfs, nodev)')[0]

    def test_busy_error_retains_normal_unmount_and_reports_processes(self):
        with patch.object(network_mounts, 'list_network_mounts', return_value=[self.volume]), \
             patch.object(network_mounts.subprocess, 'run', side_effect=[
                 SimpleNamespace(returncode=1, stdout='', stderr='Volume is busy'),
                 SimpleNamespace(returncode=0, stdout='p123\ncEditor\np456\ncFinder\n', stderr='')]) as run:
            ok, error = network_mounts.eject_volume(self.volume.id)
            report = network_mounts.eject_diagnostics(self.volume.id, error)
        self.assertFalse(ok)
        self.assertEqual(run.call_args_list[0].args[0], ['/usr/sbin/diskutil', 'unmount', '/Volumes/Media'])
        command = run.call_args_list[1].args[0]
        self.assertIn('+f', command)
        self.assertNotIn('+D', command)
        self.assertEqual(report['processes'], [{'pid': 123, 'name': 'Editor'}, {'pid': 456, 'name': 'Finder'}])
        self.assertTrue(report['limited'])
        self.assertEqual(run.call_args_list[1].kwargs['timeout'], 4)
        self.assertNotIn('force', str(run.call_args_list))

    def test_timeout_and_permission_limits_keep_failure_and_do_not_claim_no_blockers(self):
        with patch.object(network_mounts, 'list_network_mounts', return_value=[self.volume]), \
             patch.object(network_mounts.subprocess, 'run', side_effect=subprocess.TimeoutExpired('lsof', 4)):
            report = network_mounts.eject_diagnostics(self.volume.id, 'Unmount dissented by PID 321')
        self.assertTrue(report['limited'])
        self.assertEqual(report['processes'], [{'pid': 321, 'name': 'Process 321'}])

    def test_stale_identity_never_probes_a_replacement_volume(self):
        with patch.object(network_mounts, 'list_network_mounts', return_value=[]), \
             patch.object(network_mounts.subprocess, 'run') as run:
            report = network_mounts.eject_diagnostics(self.volume.id, 'busy')
            run.assert_not_called()
        self.assertTrue(report['limited'])

    def test_unmount_timeout_is_a_recoverable_error(self):
        with patch.object(network_mounts, 'list_network_mounts', return_value=[self.volume]), \
             patch.object(network_mounts.subprocess, 'run', side_effect=subprocess.TimeoutExpired('diskutil', 20)):
            ok, error = network_mounts.eject_volume(self.volume.id)
        self.assertFalse(ok)
        self.assertIn('did not finish', error)

    def test_bridge_returns_structured_failure_without_hiding_mounts(self):
        report = {'id': self.volume.id, 'name': 'Media', 'message': 'busy', 'processes': [{'pid': 123, 'name': 'Editor'}], 'limited': True}
        with patch.object(network_mounts, 'list_network_mounts', return_value=[self.volume]), \
             patch.object(network_mounts, 'eject_volume', return_value=(False, 'busy')), \
             patch.object(network_mounts, 'eject_diagnostics', return_value=report), \
             patch('src.native_bridge.connection_groups.remember_mounts', return_value={'drives': [], 'groups': []}):
            response = dispatch({'action': 'eject_volume', 'volume_id': self.volume.id})
        self.assertFalse(response['ok'])
        self.assertEqual(response['eject_failure'], report)
        self.assertEqual(response['volumes'][0]['id'], self.volume.id)

    def test_successful_late_unmount_does_not_show_a_false_failure(self):
        with patch.object(network_mounts, 'list_network_mounts', return_value=[]), \
             patch.object(network_mounts, 'eject_volume', return_value=(False, 'timed out')), \
             patch('src.native_bridge.connection_groups.remember_mounts', return_value={'drives': [], 'groups': []}):
            response = dispatch({'action': 'eject_volume', 'volume_id': self.volume.id})
        self.assertTrue(response['ok'])
        self.assertNotIn('eject_failure', response)
