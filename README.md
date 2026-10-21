# macOS Network Drive Manager (GUI)

An internal macOS desktop utility built with **Python / Tkinter** that allows users to discover, select, and batch-mount multiple SMB network shares across localized workstations and NAS devices within a LAN using a unified credential session.

![Python](https://img.shields.io/badge/Python-3.10+-blue?logo=python)
![macOS](https://img.shields.io/badge/macOS-12+-black?logo=apple)
![License](https://img.shields.io/badge/License-Internal-lightgrey)

---

## 🎯 Problem Statement

In local network environments (e.g., video editing suites, studio workflows), Mac users often need to connect to multiple shared hard drives across several workstations. Connecting via macOS Finder (`Cmd + K`) requires manual, repetitive input for each share path, causing friction and time loss.

---

## 🚀 Features

| Feature | Description |
|---------|-------------|
| **Unified Authentication** | Enter SMB credentials once to mount all selected shares |
| **Structured Host View** | Visual tree/grouping of LAN hosts and their exported shares |
| **Batch Selection** | Select All / Clear All / individual checkboxes per drive |
| **Async Mounting** | Background-threaded mount operations — GUI never freezes |
| **Config-Driven** | Reads hosts & shares from `config/shares.json` |
| **Live Status** | Green/orange/red badges show mount state per drive |
| **Disconnect** | Batch eject mounted volumes |
| **LAN Scanner** | Optional port-445 probe to discover SMB hosts |

---

## 📁 Project Structure

```text
mac-network-mounter/
├── config/
│   └── shares.json            # Target LAN machines and share definitions
├── assets/
│   └── app_icon.icns          # Application icon for macOS packaging
├── src/
│   ├── __init__.py
│   ├── main.py                # Application entry point
│   ├── models/
│   │   └── share_item.py      # Data structures (HostEntry, ShareItem)
│   ├── services/
│   │   ├── config_loader.py   # JSON config reader/writer
│   │   ├── mounter.py         # SMB mounting via subprocess + status checks
│   │   └── lan_scanner.py     # Optional LAN scanning
│   └── ui/
│       ├── components.py      # Custom Tkinter widgets (dark theme)
│       └── main_window.py     # Main GUI layout & controller
├── build_app.py               # PyInstaller / py2app bundler
├── requirements.txt           # Dependencies
└── README.md                  # This file
```

---

## ⚡ Quick Start

### Prerequisites

- **macOS 12+** (Monterey or later recommended)
- **Python 3.10+** with Tkinter (included in macOS default Python or Homebrew Python)

### Run

```bash
# Clone / navigate to the project directory
cd mac-network-mounter

# Run directly (no pip install needed — stdlib only)
python -m src.main

# Or with a custom config file
python -m src.main --config /path/to/my_shares.json

# Verbose debug logging
python -m src.main -v
```

### Configure Hosts

Edit `config/shares.json` to define your LAN machines:

```json
{
  "hosts": [
    {
      "id": "host-01",
      "name": "Editing Rig 01",
      "ip_or_hostname": "192.168.1.100",
      "shares": ["Video_Projects", "Cache_Drive", "Assets"]
    },
    {
      "id": "host-02",
      "name": "Central Storage NAS",
      "ip_or_hostname": "192.168.1.102",
      "shares": ["Archive_2024", "Sound_Effects"]
    }
  ]
}
```

---

## 🏗️ Build Standalone `.app`

```bash
# Install PyInstaller
pip install pyinstaller

# Build
python build_app.py

# Or with py2app
pip install py2app
python build_app.py --backend py2app

# Clean first
python build_app.py --clean
```

The bundled app will be at `dist/Network Drive Manager.app`.

---

## 🛠️ Technical Details

### Mounting Strategy

The app uses macOS `open smb://...` via `subprocess.run()`:

1. Credentials are **URL-encoded** (`urllib.parse.quote`) to handle special characters (`@`, `:`, `/`, `#`)
2. URI format: `smb://<encoded_user>:<encoded_pass>@<ip>/<share>`
3. After issuing the `open` command, the app polls `/Volumes/<ShareName>` to verify the mount succeeded
4. Retries up to 5 times with 1.5 s intervals if the volume doesn't appear immediately

### Threading Model

- **Main thread:** Tkinter event loop (all GUI updates)
- **Worker thread:** Sequential `mount_share()` calls via `threading.Thread(daemon=True)`
- GUI updates are safely posted from the worker via `root.after(0, callback)`

### Credential Security

- Passwords are **never logged** — only a masked URI appears in logs
- Credentials exist only in memory during the session; they are not persisted to disk

---

## 📝 License

Internal use only. Not for redistribution.

## Updated desktop workflow

The Python application runs directly on macOS; it does **not** need localhost or
port 8888. `index.html` is a separate informational website, not a drive-control
interface. SMB connections use port 445 on your NAS/server.

1. Run `python3 -m src.main` on your Mac.
2. Choose **Refresh** or **Add server**, then select a server.
3. Enter that server's username/password and click **Load drives**.
4. Select drives and click **Connect**. Finder may request permission.
5. Use **Open** to view a mounted drive, **Eject** to disconnect, and **Save
   server** to retain the server and its drive list.

Saved servers are stored per user in
`~/Library/Application Support/MAC-NDMG/shares.json`, outside the app bundle.
A fresh installation starts with no sample servers. To import an existing
configuration, launch with `python3 -m src.main --config config/shares.json`.
Passwords are not saved to the configuration. macOS commands currently receive
credentials as arguments, so they can be visible to local process inspection.
Use **Open in Finder** with an empty password for macOS-managed authentication.

### Build and share

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python build_app.py
ditto -c -k --sequesterRsrc --keepParent 'dist/Network Drive Manager.app' 'dist/Network-Drive-Manager-macOS.zip'
```

Send the ZIP to another Mac user. They unzip it and move the `.app` into
Applications; Python is included in the bundle. The recipient must be on the
same network as the target SMB server, or connected through a suitable VPN.
Build on the CPU architecture you intend to support (Apple Silicon or Intel).
The GitHub Actions workflow builds an Apple Silicon app on pushes to `main` or
`master`, on pull requests, or manually. Download the ZIP from the successful
run's **Artifacts** section. This build is unsigned and not notarized; broad
public distribution requires Apple Developer signing and notarization.

### Validation

```bash
python3 -m unittest discover -s tests -v
```

These tests cover configuration persistence, clean-install behavior, SMB URL
encoding, and parsing share names with spaces. A real NAS/server is needed for
end-to-end discovery, authentication, mounting, and eject validation.

### Interface

The desktop uses a light two-column layout with one blue primary action.
Server labels show the name and address without protocol tags. Sign-in fields
have labels above them; the bottom bar shows the selection count. Connect and
Eject become available when the selection supports the action. Activity history
is collapsed by default and can be opened from the status bar.
