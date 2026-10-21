#!/usr/bin/env python3
"""Build the native macOS app with its bundled Python service."""

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


def main():
    os.chdir(Path(__file__).resolve().parent.parent)
    if sys.platform != "darwin":
        raise SystemExit("Build this application on macOS.")
    parser = argparse.ArgumentParser(description="Build macOS .app bundle")
    parser.add_argument(
        "--clean", action="store_true",
        help="Remove previous build artefacts before building",
    )
    args = parser.parse_args()

    if args.clean:
        print("Cleaning previous build artefacts…")
        clean()

    build_native()


if __name__ == "__main__":
    main()
