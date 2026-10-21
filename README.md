# Network Drives for Mac

A native macOS app for finding servers and connecting to multiple SMB shared
drives. SwiftUI and AppKit provide the interface; the bundled Python service
handles discovery, authentication, mounting, and saved servers.

## Use the app

Requires **macOS 13 or newer**. The distributed app includes Python.

1. Unzip `Network-Drive-Manager-macOS.zip` and move the app into Applications.
2. The app opens to **Overview**, shows connected drives, and searches the local network automatically.
3. Choose a server card, enter its username and password, and choose **Load drives**.
4. Select the drives you want and choose **Connect**.
5. Connected drives offer **Open**; select them and choose **Eject** to disconnect.

**Connected** in the sidebar lists network drives already mounted on this Mac,
including connections made in Finder before opening the app. Each row shows the
server and actual mount location, with **Open** and **Eject** actions. Overview
shows a short preview with **View all**. The list refreshes every three seconds,
when the app becomes active, and after an operation. Eject uses normal macOS
unmounting; if a drive is busy, its error is shown and the app does not force it.
Local disks are not included. Duplicate drive names and multiple mounts of the
same share are tracked separately by their real mounted source and path.

**Add server** accepts an IP address or hostname. **Save** keeps the current
server and drive names for next time. **Use Finder** opens the macOS connection
flow and lets Finder manage authentication. **Activity** shows recent results.

- `⌘R`: refresh discovery from Overview.
- `⌘K`: add a server.
- Choose **Appearance → Dark**, **Light**, or **System** at the bottom of the sidebar.
  The app remembers your choice across launches and applies it to sheets and glass surfaces.
- macOS 26 uses the system's `NSGlassEffectView` for Liquid Glass surfaces.
  Earlier macOS versions use `NSVisualEffectView` materials.
- Preferences live in `~/Library/Application Support/MAC-NDMG/shares.json`.
- Passwords stay in memory and are cleared after a batch or server change.
  Existing SMB system commands receive credentials as arguments, which may be
  visible to local process inspection. Use Finder for OS-managed authentication.
- No localhost web server or port 8888 is needed. SMB uses the server's port 445.
- Recipients must be on the server's network or a suitable VPN.

The locally built app is ad-hoc signed, not Apple-notarized. Public distribution
requires an Apple Developer signing identity and notarization. Build on the CPU
architecture you want to support; the current ZIP is for Apple Silicon.

## Build

Requires macOS, Apple's Command Line Tools (Swift 6.1 or newer), and Python 3.10+.

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python build_app.py
ditto -c -k --sequesterRsrc --keepParent 'dist/Network Drive Manager.app' 'dist/Network-Drive-Manager-macOS.zip'
```

The default build creates the SwiftUI app and bundles its Python service under
`Contents/Resources/service`. The UI sends one JSON request per service process
through standard input, including credentials; it never puts credentials in its
own command line or opens a listening port.

The GitHub Actions workflow runs tests and builds an Apple Silicon app on pushes
to `main`/`master`, pull requests, and manual runs. Download the ZIP from the
successful run's **Artifacts** section.

## Development and legacy UI

```bash
python3 -m unittest discover -s tests -v
python3 -m src.main                          # legacy Tkinter UI
python3 -m src.main --config config/shares.json
.venv/bin/python build_app.py --backend pyinstaller  # legacy standalone UI
```

`native/NetworkDrives.swift` contains the native interface and state controller.
`src/native_bridge.py` is the JSON service entry point. Existing Python models
and services remain in `src/models` and `src/services`.

Tests cover persistence, clean-install behavior, SMB URL encoding, share names
with spaces, service request validation, the native service response format, network mount identity, duplicate names,
actual mount paths, and safe eject success/failure behavior.
A real server account is required to validate authenticated mounts end to end.

`index.html` is a separate informational website, not the app's control surface.

## License

Internal use only. Not for redistribution.
