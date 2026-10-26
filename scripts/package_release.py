#!/usr/bin/env python3
"""Create portable DMG/ZIP downloads from the verified native app bundle."""
import argparse
from pathlib import Path
import hashlib
import platform
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'dist' / 'MacNDMG.app'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=APP)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/release')
    parser.add_argument('--notarized', action='store_true', help='Require a stapled, Gatekeeper-accepted app')
    args = parser.parse_args()
    app = args.app.resolve()
    if args.notarized:
        subprocess.run(['xcrun', 'stapler', 'validate', str(app)], check=True)
        subprocess.run(['spctl', '--assess', '--type', 'execute', str(app)], check=True)
    if not app.is_dir():
        raise SystemExit('Build the native app before packaging.')
    architecture = {'arm64': 'Apple-Silicon', 'x86_64': 'Intel'}.get(platform.machine())
    if not architecture:
        raise SystemExit('Packaging requires an Apple Silicon or Intel Mac.')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    actual = subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS/MacNDMG')], text=True).strip()
    if actual != platform.machine():
        raise SystemExit(f'Wrong app architecture: {actual}')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    name = f'Network-Drive-Manager-macOS-{architecture}'
    with tempfile.TemporaryDirectory(prefix='ndmg-package-') as temporary:
        staging = Path(temporary) / 'MacNDMG'
        staging.mkdir()
        subprocess.run(['ditto', str(app), str(staging / app.name)], check=True)
        (staging / 'Applications').symlink_to('/Applications')
        signing_note = ('This app is Developer ID signed and Apple-notarized.\n\n' if args.notarized else
            'This build is ad-hoc signed and not Apple-notarized.\n'
            'If macOS blocks it, verify the source and read:\n'
            'https://support.apple.com/en-au/102445\n'
            'System Settings > Privacy & Security > Open Anyway (for this app only).\n'
            'Do not disable Gatekeeper.\n\n')
        (staging / 'INSTALL.txt').write_text(
            'MacNDMG for Mac\n\n'
            'Drag MacNDMG.app to Applications, then open it there.\n'
            'Requires macOS 13+. Python is already included.\n\n'
            'ลากแอพไปยัง Applications แล้วเปิดจาก Applications ไม่ต้องติดตั้ง Python\n\n'
            + signing_note + 'Downloads and help: https://github.com/Aikmathee/MAC-NDMG\n', encoding='utf-8')
        dmg = output / (name + '.dmg')
        subprocess.run(['hdiutil', 'create', '-volname', 'MacNDMG', '-srcfolder', str(staging),
                        '-ov', '-format', 'UDZO', str(dmg)], check=True)
        archive = output / (name + '.zip')
        subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(staging), str(archive)], check=True)
    sums = []
    for file in sorted(output.glob(name + '.*')):
        sums.append(f'{hashlib.sha256(file.read_bytes()).hexdigest()}  {file.name}\n')
    (output / f'SHA256SUMS-{architecture}.txt').write_text(''.join(sums))
    print(f'Release packages ready: {output}')


if __name__ == '__main__':
    main()
