#!/usr/bin/env python3
"""
build_app.py - Bundle the macOS Network Drive Manager into a standalone .app.

Supports two build backends:
  1. Native SwiftUI app with a bundled Python service (default)
  2. PyInstaller or py2app for the legacy Tkinter interface

Usage:
    python build_app.py                # native SwiftUI (default)
    python build_app.py --backend py2app
    python build_app.py --clean        # Remove previous build artefacts first
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import platform
import plistlib
from pathlib import Path

APP_NAME = "Network Drive Manager"
ENTRY_POINT = "src/main.py"
ICON_PATH = "assets/app_icon.icns"
CONFIG_DATA = "config/shares.json"
BUNDLE_ID = "com.studio.network-drive-manager"


def clean():
    """Remove previous build artefacts."""
    for d in ("build", "dist", "__pycache__"):
        if os.path.isdir(d):
            shutil.rmtree(d)
            print(f"  Removed {d}/")
    for f in (".eggs", f"{APP_NAME}.spec"):
        if os.path.exists(f):
            os.remove(f)
            print(f"  Removed {f}")


def build_native():
    """Build a SwiftUI macOS app with its Python service bundled privately."""
    subprocess.check_call([
        sys.executable, "-m", "PyInstaller", "--name", "ndmg-service",
        "--onedir", "--noconfirm", "--paths", str(Path.cwd()),
        "--exclude-module", "tkinter", "--distpath", "dist/native-service",
        "--workpath", "build/native-service", "--specpath", "build",
        "src/native_bridge.py",
    ])
    bundle = Path("dist") / f"{APP_NAME}.app"
    if bundle.exists():
        shutil.rmtree(bundle)
    macos = bundle / "Contents" / "MacOS"
    resources = bundle / "Contents" / "Resources"
    macos.mkdir(parents=True)
    resources.mkdir(parents=True)
    shutil.copytree("dist/native-service/ndmg-service", resources / "service")
    architecture = "arm64" if platform.machine() == "arm64" else "x86_64"
    subprocess.check_call([
        "xcrun", "swiftc", "-parse-as-library", "-O",
        "-target", f"{architecture}-apple-macos13.0",
        "-module-cache-path", str(Path("build/swift-cache").resolve()),
        "native/NetworkDrives.swift", "native/CredentialVault.swift", "-o", str(macos / APP_NAME),
    ])
    icon_tool = Path("build/make-app-icon")
    subprocess.check_call(["xcrun", "swiftc", "-module-cache-path", str(Path("build/swift-cache").resolve()),
                           "native/AppIcon.swift", "-o", str(icon_tool)])
    subprocess.check_call([str(icon_tool.resolve()), "build/AppIcon.iconset"])
    subprocess.check_call(["iconutil", "-c", "icns", "build/AppIcon.iconset", "-o", str(resources / "AppIcon.icns")])
    info = {
        "CFBundleName": "Network Drives", "CFBundleDisplayName": "Network Drives",
        "CFBundleExecutable": APP_NAME, "CFBundleIdentifier": BUNDLE_ID,
        "CFBundlePackageType": "APPL", "CFBundleShortVersionString": Path("VERSION").read_text().strip(),
        "CFBundleVersion": Path("VERSION").read_text().strip(), "LSMinimumSystemVersion": "13.0",
        "CFBundleIconFile": "AppIcon",
        "NSHighResolutionCapable": True,
        "NSLocalNetworkUsageDescription": "Find shared drives on your local network and connect to the servers you choose.",
        "NSBonjourServices": ["_smb._tcp"],
    }
    with (bundle / "Contents" / "Info.plist").open("wb") as handle:
        plistlib.dump(info, handle)
    subprocess.check_call(["codesign", "--force", "--deep", "--sign", "-", str(bundle)])
    print(f"Native app created: {bundle}")


def build_pyinstaller():
    """Build using PyInstaller."""
    cmd = [
        sys.executable, "-m", "PyInstaller",
        "--name", APP_NAME,
        "--windowed",                       # .app bundle, no terminal
        "--onedir",                         # directory bundle (faster start)
        "--paths", os.path.dirname(os.path.abspath(__file__)),
        "--osx-bundle-identifier", BUNDLE_ID,
        "--noconfirm",                      # overwrite previous build
        "--add-data", f"{CONFIG_DATA}:config",
    ]

    if os.path.exists(ICON_PATH):
        cmd.extend(["--icon", ICON_PATH])

    cmd.append(ENTRY_POINT)

    print(f"Running: {' '.join(cmd)}\n")
    subprocess.check_call(cmd)
    print(f"\n✅  App bundle created at: dist/{APP_NAME}.app")


def build_py2app():
    """Build using py2app (requires a setup.py-style invocation)."""
    setup_content = f'''
from setuptools import setup

APP = ["{ENTRY_POINT}"]
DATA_FILES = [("config", ["{CONFIG_DATA}"])]
OPTIONS = {{
    "argv_emulation": False,
    "plist": {{
        "CFBundleName": "{APP_NAME}",
        "CFBundleIdentifier": "{BUNDLE_ID}",
        "CFBundleShortVersionString": "1.0.0",
        "LSMinimumSystemVersion": "12.0",
    }},
    "packages": ["src"],
}}

{"ICONFILE = " + repr(ICON_PATH) if os.path.exists(ICON_PATH) else ""}

setup(
    app=APP,
    data_files=DATA_FILES,
    options={{"py2app": OPTIONS}},
    setup_requires=["py2app"],
)
'''
    setup_path = "_setup_py2app.py"
    with open(setup_path, "w") as f:
        f.write(setup_content)

    try:
        subprocess.check_call([sys.executable, setup_path, "py2app"])
        print(f"\n✅  App bundle created at: dist/{APP_NAME}.app")
    finally:
        os.remove(setup_path)


def main():
    os.chdir(Path(__file__).resolve().parent.parent)
    if sys.platform != "darwin":
        raise SystemExit("Build this application on macOS.")
    parser = argparse.ArgumentParser(description="Build macOS .app bundle")
    parser.add_argument(
        "--backend", choices=["native", "pyinstaller", "py2app"],
        default="native",
        help="Build backend (default: native SwiftUI; pyinstaller keeps the legacy Tk UI)",
    )
    parser.add_argument(
        "--clean", action="store_true",
        help="Remove previous build artefacts before building",
    )
    args = parser.parse_args()

    if args.clean:
        print("Cleaning previous build artefacts…")
        clean()

    if args.backend == "native":
        build_native()
    elif args.backend == "pyinstaller":
        build_pyinstaller()
    else:
        build_py2app()


if __name__ == "__main__":
    main()
