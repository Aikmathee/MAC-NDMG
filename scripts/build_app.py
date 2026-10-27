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

APP_NAME = "MacNDMG"
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


def build_native(require_modern_sdk=False):
    """Build a SwiftUI macOS app with its Python service bundled privately."""
    sdk_version = subprocess.check_output(["xcrun", "--show-sdk-version"], text=True).strip()
    modern = int(sdk_version.split(".")[0]) >= 26
    if require_modern_sdk and not modern:
        raise SystemExit("Distribution builds require macOS SDK 26 or newer.")
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
    sources = sorted(str(p) for p in Path("native").rglob("*.swift") if "tests" not in p.parts and p.name != "AppIcon.swift")
    subprocess.check_call([
        "xcrun", "swiftc", "-parse-as-library", "-O",
        "-target", f"{architecture}-apple-macos13.0",
        "-module-cache-path", str(Path("build/swift-cache").resolve()),
        *(["-D", "MODERN_GLASS"] if modern else []), *sources, "-o", str(macos / APP_NAME),
    ])
    icon_tool = Path("build/make-app-icon")
    subprocess.check_call(["xcrun", "swiftc", "-module-cache-path", str(Path("build/swift-cache").resolve()),
                           "native/AppIcon.swift", "-o", str(icon_tool)])
    subprocess.check_call([str(icon_tool.resolve()), "build/AppIcon.iconset"])
    subprocess.check_call(["iconutil", "-c", "icns", "build/AppIcon.iconset", "-o", str(resources / "AppIcon.icns")])
    info = {
        "CFBundleName": "MacNDMG", "CFBundleDisplayName": "MacNDMG",
        "CFBundleExecutable": APP_NAME, "CFBundleIdentifier": BUNDLE_ID,
        "CFBundlePackageType": "APPL", "CFBundleShortVersionString": Path("VERSION").read_text().strip(),
        "CFBundleVersion": Path("VERSION").read_text().strip(), "LSMinimumSystemVersion": "13.0",
        "CFBundleIconFile": "AppIcon",
        "NDMGDisplayVersion": Path("DISPLAY_VERSION").read_text().strip(),
        "NSHighResolutionCapable": True, "NDMGModernGlassBuild": modern, "NDMGSDKVersion": sdk_version,
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
    parser.add_argument("--require-modern-sdk", action="store_true", help="Require SDK 26+ for release builds")
    args = parser.parse_args()

    if args.clean:
        print("Cleaning previous build artefacts…")
        clean()

    build_native(args.require_modern_sdk)


if __name__ == "__main__":
    main()
