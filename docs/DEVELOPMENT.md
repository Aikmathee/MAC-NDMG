# Development

The shipping app is a native SwiftUI/AppKit interface with a private bundled Python service. There is no localhost server or port 8888. One JSON request travels over standard input per service process.

## Requirements and build

Use macOS, Xcode Command Line Tools with Swift 6.1+, and Python 3.12+. Build on the target CPU architecture; Python and Swift must have the same architecture.

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m unittest discover -s tests -v
.venv/bin/python scripts/build_app.py
.venv/bin/python scripts/package_release.py
```

Output is in `dist/`; distributable DMGs, ZIPs and checksums are in `dist/release/`. `VERSION` is the source for app and release versions.

- `native/NetworkDrives.swift`: interface and observable store.
- `native/CredentialVault.swift`: Keychain access; isolated Swift tests are in `native/tests/`.
- `src/native_bridge.py`: bundled JSON service entry point.
- `src/services/`: LAN discovery, live network mount identity, safe eject, remote destinations and saved groups.
- `src/models/`: shared models.

Settings are stored in the user's Application Support/MAC-NDMG folder. Accounts are session-only or stored in Keychain when requested. No user's network inventory, preferences or credentials belong in the repository or release package.

## Validation

Python tests cover persistence, service validation, SMB encoding, multi-server groups, remote URL parsing, mount identities and safe eject. CI also compiles the native app, verifies its signature and architecture, and runs the packaged service against an isolated clean configuration. Authenticated mounts require a real server and are not covered by automated CI.

Current bundles are ad-hoc signed. Developer ID signing and Apple notarization are still required for a first launch without the unidentified-developer exception. Do not describe these builds as notarized.
