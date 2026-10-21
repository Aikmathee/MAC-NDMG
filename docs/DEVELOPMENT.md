# Development

The shipping app is a native SwiftUI/AppKit interface with a private bundled Python service. There is no localhost server or port 8888. One JSON request travels over standard input per service process.

## Requirements and build

Release builds use Xcode 26 with macOS SDK 26+ and Python 3.12+. The deployment target remains macOS 13. Build on the target CPU architecture; Python and Swift must have the same architecture. GitHub Actions selects an installed stable Xcode 26 and requires the modern SDK for building and verification.

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m unittest discover -s tests -v
.venv/bin/python scripts/build_app.py --require-modern-sdk
.venv/bin/python scripts/verify_bundle.py --require-modern-sdk
.venv/bin/python scripts/package_release.py
```

Output is in `dist/`; distributable DMGs, ZIPs and checksums are in `dist/release/`. `VERSION` is the source for app and release versions.

- `native/NetworkDrives.swift`: app entry point, shell wiring and observable store.
- `native/Design/`: system button styles, content/control materials, selection and design tokens.
- `native/Views/`: overview, connected drives, groups, server detail, sheets and toolbar.
- `native/CredentialVault.swift`: Keychain access; isolated Swift tests are in `native/tests/`.
- `src/native_bridge.py`: bundled JSON service entry point.
- `src/services/`: LAN discovery, live network mount identity, safe eject, remote destinations and saved groups.
- `src/models/`: shared models.

Settings are stored in the user's Application Support/MAC-NDMG folder. Accounts are session-only or stored in Keychain when requested. No user's network inventory, preferences or credentials belong in the repository or release package.

## Validation

Python tests cover persistence, service validation, SMB encoding, multi-server groups, remote URL parsing, mount identities and safe eject. CI also compiles the native app, verifies its signature and architecture, and runs the packaged service against an isolated clean configuration. Authenticated mounts require a real server and are not covered by automated CI.

Current bundles are ad-hoc signed. Developer ID signing and Apple notarization are still required for a first launch without the unidentified-developer exception. Do not describe these builds as notarized.


## Compatibility builds

For local layout work with Command Line Tools / SDK 15.5, omit `--require-modern-sdk`. This compiles the shared layout with standard controls and a runtime glass compatibility renderer. It does not exercise the SDK 26 SwiftUI glass button styles. Production downloads are always built and checked with SDK 26+; final visual QA must use that build on macOS 26.

`MODERN_GLASS` is a compiler condition set only when the detected SDK major version is 26 or newer. All new API calls are also guarded by OS availability for deployment on macOS 13–15. Reduce Transparency uses an opaque control surface; custom hover/selection transitions respect Reduce Motion; content outlines adapt to increased contrast.
