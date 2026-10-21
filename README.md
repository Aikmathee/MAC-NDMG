<div align="center">

# Network Drives for Mac

Connect your network drives. Keep your workspace simple.

**Native macOS app · Dark & Light mode · SMB & WebDAV · Drive groups**

[![Download for Apple Silicon](https://img.shields.io/badge/Download_for_Mac-Apple_Silicon-007AFF?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/Aikmathee/MAC-NDMG/releases/latest/download/Network-Drive-Manager-macOS-Apple-Silicon.dmg)
[![Download for Intel](https://img.shields.io/badge/Download_for_Mac-Intel-555555?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/Aikmathee/MAC-NDMG/releases/latest/download/Network-Drive-Manager-macOS-Intel.dmg)

**[All downloads & release notes](https://github.com/Aikmathee/MAC-NDMG/releases/latest)** · [คู่มือภาษาไทย](docs/INSTALL.th.md) · [User guide](docs/USER_GUIDE.md)

macOS 13 or later. Python is included — no Terminal or developer tools needed.

</div>

## ดาวน์โหลดและเริ่มใช้งาน

1. กดปุ่มดาวน์โหลดด้านบน: **Apple Silicon** สำหรับชิป M1 ขึ้นไป หรือ **Intel** สำหรับ Mac รุ่น Intel (ดูได้ที่  → About This Mac)
2. เปิดไฟล์ `.dmg` แล้วลาก **Network Drive Manager** ไปยัง **Applications**
3. เปิดแอพ เลือกเครื่องหรือกด **Add server** แล้วเข้าสู่ระบบเพื่อเลือกไดรฟ์

**การเปิดครั้งแรก:** เวอร์ชันนี้ยังไม่ได้รับการ notarize จาก Apple หาก macOS บล็อกแอพ ให้ตรวจว่าดาวน์โหลดจาก Release ของโปรเจกต์นี้ แล้วใช้ **System Settings → Privacy & Security → Open Anyway** ตาม [คำแนะนำของ Apple](https://support.apple.com/en-au/102445) ไม่ต้องปิด Gatekeeper หรือรันคำสั่งใน Terminal

## What you can do

- See drives already connected in Finder, with Open and Eject actions.
- Command-click or Shift-click to select multiple drives and servers.
- Connect or eject a whole group; save selections for next time.
- Remember SMB accounts in macOS Keychain.
- Connect through a LAN, Tailscale, another VPN or a WebDAV server.
- Choose System, Light or Dark appearance, with Liquid Glass on macOS 26.

Groups connect when you click **Connect**. Busy drives are never force-ejected. FTP/SFTP mounting is not included.

## Install in English

Download the DMG for your Mac, open it and drag the app to **Applications**. Open the app and choose a server. For remote SMB, connect your VPN first; add a hostname such as `nas.example.ts.net` or a share URL such as `smb://nas/Projects`. For WebDAV, use the server's actual endpoint, such as `https://cloud.example.com/dav/`.

This release is ad-hoc signed and **not Apple-notarized**. macOS may block the first launch. Review [Apple's instructions](https://support.apple.com/en-au/102445) and allow this app only if you trust its source. A ZIP alternative and SHA-256 checksums are available under [Release assets](https://github.com/Aikmathee/MAC-NDMG/releases/latest).

## Project structure

| Folder | Purpose |
| --- | --- |
| `native/` | SwiftUI interface, macOS integration and Keychain |
| `src/` | Python service, discovery, mounts and persistence |
| `tests/` | Python service tests |
| `scripts/` | Build, package and release tooling |
| `docs/` | Installation, usage and development guides |
| `.github/workflows/` | Tests, builds and release publishing |

[Development & build guide](docs/DEVELOPMENT.md) · [Release process](docs/RELEASING.md) · [Changelog](CHANGELOG.md)
