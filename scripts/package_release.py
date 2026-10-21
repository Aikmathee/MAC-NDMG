#!/usr/bin/env python3
"""Create portable DMG/ZIP downloads from the verified native app bundle."""
from pathlib import Path
import hashlib
import platform
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'dist' / 'Network Drive Manager.app'


def main():
    if not APP.is_dir():
        raise SystemExit('Build the native app before packaging.')
    architecture = {'arm64': 'Apple-Silicon', 'x86_64': 'Intel'}.get(platform.machine())
    if not architecture:
        raise SystemExit('Packaging requires an Apple Silicon or Intel Mac.')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(APP)], check=True)
    actual = subprocess.check_output(['lipo', '-archs', str(APP / 'Contents/MacOS/Network Drive Manager')], text=True).strip()
    if actual != platform.machine():
        raise SystemExit(f'Wrong app architecture: {actual}')
    output = ROOT / 'dist' / 'release'
    output.mkdir(parents=True, exist_ok=True)
    name = f'Network-Drive-Manager-macOS-{architecture}'
    with tempfile.TemporaryDirectory(prefix='ndmg-package-') as temporary:
        staging = Path(temporary) / 'Network Drives'
        staging.mkdir()
        subprocess.run(['ditto', str(APP), str(staging / APP.name)], check=True)
        (staging / 'Applications').symlink_to('/Applications')
        (staging / 'INSTALL.txt').write_text(
            'Network Drives for Mac\n\n'
            'Drag Network Drive Manager.app to Applications, then open it there.\n'
            'Requires macOS 13+. Python is already included.\n\n'
            'ลากแอพไปยัง Applications แล้วเปิดจาก Applications ไม่ต้องติดตั้ง Python\n\n'
            'This build is ad-hoc signed and not Apple-notarized.\n'
            'If macOS blocks it, verify the source and read:\n'
            'https://support.apple.com/en-au/102445\n'
            'System Settings > Privacy & Security > Open Anyway (for this app only).\n'
            'Do not disable Gatekeeper.\n\n'
            'Downloads and help: https://github.com/Aikmathee/MAC-NDMG\n', encoding='utf-8')
        dmg = output / (name + '.dmg')
        subprocess.run(['hdiutil', 'create', '-volname', 'Network Drives', '-srcfolder', str(staging),
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
