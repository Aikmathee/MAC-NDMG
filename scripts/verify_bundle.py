#!/usr/bin/env python3
"""Check packaged version, signature and clean-install JSON protocol."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'dist/MacNDMG.app'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-modern-sdk", action="store_true")
    parser.add_argument("--app", type=Path, default=APP)
    args = parser.parse_args()
    app = args.app.resolve()
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    with (app / 'Contents/Info.plist').open('rb') as handle:
        info = plistlib.load(handle)
    assert info['CFBundleShortVersionString'] == (ROOT / 'VERSION').read_text().strip()
    if args.require_modern_sdk:
        assert info.get('NDMGModernGlassBuild') is True, 'Release must enable typed Liquid Glass APIs'
        assert int(info['NDMGSDKVersion'].split('.')[0]) >= 26
    with tempfile.TemporaryDirectory(prefix='ndmg-verify-') as folder:
        env = dict(os.environ, HOME=folder)
        executable = app / 'Contents/Resources/service/ndmg-service'
        for action, field in [('saved', 'hosts'), ('connections', 'remembered')]:
            result = subprocess.run([str(executable)], input=json.dumps({'action': action}) + '\n',
                                    text=True, capture_output=True, env=env, timeout=20, check=True)
            payload = json.loads(result.stdout)
            assert payload['ok'] and isinstance(payload[field], list), 'Invalid service response'
            if action == 'saved':
                assert payload[field] == [], 'Clean installs must not include sample servers'
            else:
                assert payload['groups'] == [], 'Clean installs must not include saved groups'
    print('Verified bundle version, signature and clean-install service responses.')


if __name__ == '__main__':
    main()
