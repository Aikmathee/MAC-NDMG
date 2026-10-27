#!/usr/bin/env python3
"""Publish a complete pair of architecture builds using the workflow token."""
import hashlib
import json
import os
from pathlib import Path
import re
from urllib.parse import quote
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent.parent


def main():
    repo = os.environ['GITHUB_REPOSITORY']
    tag = os.environ['GITHUB_REF_NAME']
    version = (ROOT / 'VERSION').read_text().strip()
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or tag != f'v{version}':
        raise SystemExit('The release tag must match VERSION exactly.')
    token = os.environ['GH_TOKEN']
    output = ROOT / 'dist' / 'release'
    files = [output / f'Network-Drive-Manager-macOS-{arch}.{extension}'
             for arch in ('Apple-Silicon', 'Intel') for extension in ('dmg', 'zip')]
    if any(not f.is_file() or f.stat().st_size == 0 for f in files):
        raise SystemExit('Both architectures must have DMG and ZIP packages.')
    expected = {}
    for arch in ('Apple-Silicon', 'Intel'):
        for line in (output / f'SHA256SUMS-{arch}.txt').read_text().splitlines():
            digest, name = line.split('  ', 1)
            expected[name] = digest
    for file in files:
        if hashlib.sha256(file.read_bytes()).hexdigest() != expected.get(file.name):
            raise SystemExit(f'Checksum mismatch: {file.name}')
    checksum = output / 'SHA256SUMS.txt'
    checksum.write_text(''.join(f'{expected[f.name]}  {f.name}\n' for f in files))
    files.append(checksum)
    display_version = (ROOT / 'DISPLAY_VERSION').read_text().strip()
    notes = (ROOT / 'docs' / 'releases' / f'{tag}.md').read_text()
    base = f'https://api.github.com/repos/{repo}'

    def api(method, url, body=None, media='application/json'):
        data = json.dumps(body).encode() if isinstance(body, dict) else body
        request = Request(url, data=data, method=method, headers={
            'Authorization': f'Bearer {token}', 'Accept': 'application/vnd.github+json',
            'Content-Type': media, 'X-GitHub-Api-Version': '2022-11-28'})
        with urlopen(request, timeout=180) as response:
            raw = response.read()
            return json.loads(raw) if raw else None

    # Include drafts on rerun; GET by tag may omit a draft release.
    releases = api('GET', base + '/releases?per_page=100')
    release = next((r for r in releases if r['tag_name'] == tag), None)
    if release and not release['draft']:
        raise SystemExit('This version is already published. Use a new version; do not overwrite downloads.')
    if release is None:
        release = api('POST', base + '/releases', {'tag_name': tag, 'name': f'MacNDMG {display_version}',
                       'body': notes, 'draft': True, 'prerelease': False})
    release_url = base + f"/releases/{release['id']}"
    existing = api('GET', release_url + '/assets?per_page=100')
    # Failed unpublished uploads may be replaced, never a published release.
    for asset in existing:
        if asset['name'] in {f.name for f in files}:
            api('DELETE', base + f"/releases/assets/{asset['id']}")
    upload = release['upload_url'].split('{')[0]
    for file in files:
        media = 'application/zip' if file.suffix == '.zip' else 'application/octet-stream'
        asset = api('POST', upload + '?name=' + quote(file.name), file.read_bytes(), media)
        if asset['state'] != 'uploaded' or asset['size'] != file.stat().st_size:
            raise SystemExit(f'Upload incomplete: {file.name}')
        print('Uploaded:', file.name)
    published = api('PATCH', release_url, {'draft': False, 'body': notes, 'make_latest': 'true'})
    print('Published:', published['html_url'])


if __name__ == '__main__':
    main()
