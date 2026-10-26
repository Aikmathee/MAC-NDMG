import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('notarize_app',Path(__file__).resolve().parents[1]/'scripts/notarize_app.py')
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class NotarizationPreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.app=self.root/'MacNDMG.app'
        (self.app/'Contents').mkdir(parents=True)
        (self.app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.studio.network-drive-manager','CFBundleShortVersionString':'2.3.7'}))

    def test_preflight_without_identity_never_signs_or_uploads(self):
        def fake(args,**kwargs):
            return subprocess.CompletedProcess(args,0,'0 valid identities found\n','')
        with patch.object(module,'command',side_effect=fake) as run:
            result=module.preflight(self.app)
        self.assertFalse(result['ready_to_sign'])
        self.assertFalse(result['notarized'])
        self.assertFalse(any('--sign' in c.args[0] or 'submit' in c.args[0] for c in run.call_args_list))

    def test_nested_code_signed_before_outer_bundle_and_symlinks_ignored(self):
        code=self.app/'Contents/helper'
        code.write_bytes(bytes.fromhex('cffaedfe')+b'fixture')
        (self.app/'Contents/alias').symlink_to(code)
        self.assertEqual(module.signing_targets(self.app),[code,self.app])

    def test_signing_only_changes_staged_copy_and_enables_runtime_timestamp(self):
        code=self.app/'Contents/helper'
        original=bytes.fromhex('cffaedfe')+b'fixture'
        code.write_bytes(original)
        with patch.object(module,'command',return_value=subprocess.CompletedProcess([],0,'','')) as run:
            staged=module.stage_and_sign(self.app,self.root/'staging','Developer ID Application: Example')
        self.assertEqual(code.read_bytes(),original)
        signs=[c.args[0] for c in run.call_args_list if '--sign' in c.args[0]]
        self.assertTrue(all('--timestamp' in c and 'runtime' in c and '--deep' not in c for c in signs))
        self.assertEqual(signs[-1][-1],str(staged))

    def test_existing_outputs_are_preserved(self):
        with self.assertRaises(ValueError): module.stage_and_sign(self.app,self.root,'unused')

    def test_rejected_notarization_is_never_stapled(self):
        output=self.root/'staging';output.mkdir()
        def fake(args,**kwargs):
            return subprocess.CompletedProcess(args,0,'{"id":"fixture","status":"Invalid"}','')
        with patch.object(module,'command',side_effect=fake) as run:
            with self.assertRaises(ValueError): module.notarize(self.app,output,'profile')
        self.assertFalse(any('staple' in c.args[0] for c in run.call_args_list))

    def test_accepted_notarization_requires_stapling_validation_and_assessment(self):
        output=self.root/'staging';output.mkdir()
        def fake(args,**kwargs):
            return subprocess.CompletedProcess(args,0,'{"id":"fixture","status":"Accepted"}','')
        with patch.object(module,'command',side_effect=fake) as run:
            result=module.notarize(self.app,output,'profile')
        self.assertTrue(result['stapled_and_assessed'])
        self.assertTrue(any('validate' in c.args[0] for c in run.call_args_list))
        self.assertTrue(any('spctl' == c.args[0][0] for c in run.call_args_list))

    def test_packaging_rejects_notarized_claim_before_creating_installer(self):
        import sys
        spec=importlib.util.spec_from_file_location('package_release',Path(__file__).resolve().parents[1]/'scripts/package_release.py')
        package=importlib.util.module_from_spec(spec);spec.loader.exec_module(package)
        with patch.object(sys,'argv',['package_release.py','--app',str(self.app),'--notarized']), \
             patch.object(package.subprocess,'run',side_effect=subprocess.CalledProcessError(1,['stapler'])) as run:
            with self.assertRaises(subprocess.CalledProcessError): package.main()
        self.assertEqual(run.call_count,1)
        self.assertEqual(run.call_args.args[0][:3],['xcrun','stapler','validate'])
