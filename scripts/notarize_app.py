#!/usr/bin/env python3
"""Read-only distribution preflight, or explicitly sign/notarize a staged copy.

Uses an existing Developer ID identity and a notarytool Keychain profile.
Never imports keys, stores passwords, modifies the installed app, or publishes.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
MACHO = {bytes.fromhex(x) for x in ('feedface','cefaedfe','feedfacf','cffaedfe','cafebabe','bebafeca','cafebabf','bfbafeca')}


def command(args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs)


def preflight(app):
    if not (app / 'Contents/Info.plist').is_file():
        raise ValueError('Build MacNDMG.app first.')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'com.studio.network-drive-manager':
        raise ValueError('This is not a MacNDMG app bundle.')
    command(['codesign', '--verify', '--deep', '--strict', str(app)])
    identities = command(['security', 'find-identity', '-v', '-p', 'codesigning']).stdout
    names = [line.split('"')[1] for line in identities.splitlines()
             if '"Developer ID Application:' in line and line.count('"') >= 2]
    tools = {}
    for name in ('notarytool', 'stapler'):
        try:
            command(['xcrun', '--find', name])
            tools[name] = True
        except subprocess.CalledProcessError:
            tools[name] = False
    return {'version': info.get('CFBundleShortVersionString'),
            'developer_id_identities': names, 'tools': tools,
            'ready_to_sign': bool(names) and all(tools.values()),
            'notarized': False}  # Preflight alone never establishes notarization.


def signing_targets(app):
    targets = set()
    for path in app.rglob('*'):
        if path.is_symlink():
            continue
        if path.is_file():
            with path.open('rb') as handle:
                if handle.read(4) in MACHO:
                    targets.add(path)
        elif path.suffix in ('.framework', '.app', '.xpc', '.bundle'):
            if (path / 'Contents/Info.plist').exists() or path.suffix == '.framework':
                targets.add(path)
    return sorted(targets, key=lambda p: (-len(p.parts), str(p))) + [app]


def stage_and_sign(app, output, identity):
    if output.exists():
        raise ValueError('Choose a new output folder; existing outputs are never overwritten.')
    if app == output or app in output.parents:
        raise ValueError('Output must be outside the source app bundle.')
    output.mkdir(parents=True)
    staged = output / app.name
    shutil.copytree(app, staged, symlinks=True)
    for target in signing_targets(staged):
        command(['codesign', '--force', '--options', 'runtime', '--timestamp',
                 '--sign', identity, str(target)])
    command(['codesign', '--verify', '--deep', '--strict', str(staged)])
    # Signing must not break the embedded Python service before uploading to Apple.
    command(['python3', str(ROOT / 'scripts/verify_bundle.py'), '--app', str(staged), '--require-modern-sdk'])
    return staged


def notarize(staged, output, profile):
    archive = output / 'MacNDMG-notarization.zip'
    command(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(staged), str(archive)])
    response = command(['xcrun', 'notarytool', 'submit', str(archive), '--keychain-profile', profile,
                        '--wait', '--timeout', '20m', '--output-format', 'json'])
    result = json.loads(response.stdout)
    report = {key: result.get(key) for key in ('id', 'status')}
    (output / 'notarization.json').write_text(json.dumps(report, indent=2) + '\n')
    if result.get('status') != 'Accepted':
        raise ValueError('Apple has not accepted this submission. Review the local submission ID; do not distribute it as notarized.')
    command(['xcrun', 'stapler', 'staple', str(staged)])
    command(['xcrun', 'stapler', 'validate', str(staged)])
    command(['spctl', '--assess', '--type', 'execute', '--verbose=2', str(staged)])
    report['stapled_and_assessed'] = True
    (output / 'notarization.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT / 'dist/MacNDMG.app')
    parser.add_argument('--output', type=Path, help='New folder for the signed copy and local reports')
    parser.add_argument('--identity', help='Exact existing Developer ID Application identity')
    parser.add_argument('--sign', action='store_true', help='Sign a copy; never alter the source app')
    parser.add_argument('--submit', action='store_true', help='Upload signed copy to Apple and wait for notarization')
    parser.add_argument('--profile', help='Existing notarytool Keychain profile; never a password')
    args = parser.parse_args()
    app = args.app.resolve()
    if args.submit and (not args.sign or not args.profile):
        parser.error('--submit requires --sign and an existing --profile')
    if args.sign and (not args.identity or not args.output):
        parser.error('--sign requires --identity and a new --output folder')
    try:
        report = preflight(app)
        if not args.sign:
            print(json.dumps(report, indent=2))
            return
        if args.identity not in report['developer_id_identities']:
            raise ValueError('The selected Developer ID Application identity is not available in Keychain.')
        if not report['ready_to_sign']:
            raise ValueError('Developer ID and Xcode notarization tools are required.')
        output = args.output.resolve()
        staged = stage_and_sign(app, output, args.identity)
        if args.submit:
            print(json.dumps(notarize(staged, output, args.profile), indent=2))
        else:
            print('Signed staged copy. It is not notarized and was not uploaded.')
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        # Avoid dumping subprocess output that may contain account metadata.
        parser.exit(1, f'Distribution preparation failed: {error}\n')


if __name__ == '__main__':
    main()
