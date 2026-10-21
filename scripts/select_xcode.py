"""Choose an installed stable Xcode 26 SDK for GitHub release builds."""
import os
from pathlib import Path
import re

candidates = []
for app in Path('/Applications').glob('Xcode_26*.app'):
    match = re.fullmatch(r'Xcode_(26(?:\.\d+)*).app', app.name)
    if match:
        candidates.append((tuple(map(int, match.group(1).split('.'))), app))
if not candidates:
    raise SystemExit('Xcode 26 is required; no compatible installation was found.')
selected = max(candidates)[1] / 'Contents/Developer'
with open(os.environ['GITHUB_ENV'], 'a') as handle:
    handle.write(f'DEVELOPER_DIR={selected}\n')
print('Selected:', selected)
