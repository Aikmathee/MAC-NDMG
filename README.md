<div align="center">

# MacNDMG

**เชื่อมไดรฟ์เครือข่ายบน Mac ได้เป็นกลุ่ม**

SMB · WebDAV · LAN / VPN · Light & Dark · Liquid Glass

### Preview 1 — เปิดให้ทดลองใช้งาน

[![ดาวน์โหลดสำหรับ Apple Silicon](https://img.shields.io/badge/Download_for_Mac-Apple_Silicon-007AFF?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/Aikmathee/MAC-NDMG/releases/latest/download/Network-Drive-Manager-macOS-Apple-Silicon.dmg)
[![ดาวน์โหลดสำหรับ Intel](https://img.shields.io/badge/Download_for_Mac-Intel-555555?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/Aikmathee/MAC-NDMG/releases/latest/download/Network-Drive-Manager-macOS-Intel.dmg)

[ไฟล์ดาวน์โหลดและรายละเอียดรุ่น](https://github.com/Aikmathee/MAC-NDMG/releases/latest) · [วิธีติดตั้ง](docs/INSTALL.th.md) · [คู่มือใช้งาน](docs/USER_GUIDE.md) · [แจ้งบั๊ก](https://github.com/Aikmathee/MAC-NDMG/issues/new?template=bug_report.md)

macOS 13 ขึ้นไป · รองรับ Apple Silicon และ Intel · ไม่ต้องติดตั้ง Python หรือใช้ Terminal

</div>

## เริ่มต้นใช้งาน

1. **เลือกไฟล์สำหรับ Mac ของคุณ** — Apple Silicon สำหรับชิป Apple M1 ขึ้นไป หรือ Intel สำหรับ Mac รุ่น Intel ตรวจได้ที่  → About This Mac
2. **ติดตั้งแอป** — เปิดไฟล์ `.dmg` แล้วลาก **MacNDMG** ไปยัง **Applications**
3. **เลือกไดรฟ์ที่ต้องการเชื่อม** — เปิดแอป เลือกเซิร์ฟเวอร์แล้วกด **Load drives…** หรือเพิ่มที่อยู่ด้วย **Add server** จากนั้นเลือกไดรฟ์แล้วกด **Connect**

**การเปิดครั้งแรก:** รุ่นทดลองนี้ยังไม่ได้รับการ notarize จาก Apple จึงอาจมีคำเตือนจาก macOS หลังลองเปิดแอป หากคุณตรวจแล้วว่าดาวน์โหลดจากโปรเจกต์นี้และเชื่อถือแหล่งที่มา ให้ทำตาม [คำแนะนำของ Apple](https://support.apple.com/en-au/102445) ที่ **System Settings → Privacy & Security → Open Anyway** สำหรับแอปนี้ ไม่ต้องปิด Gatekeeper

มีไฟล์ ZIP และ SHA-256 checksums ให้เลือกใน [หน้าดาวน์โหลด](https://github.com/Aikmathee/MAC-NDMG/releases/latest)

## MacNDMG ช่วยอะไรได้บ้าง

- **เห็นไดรฟ์ที่เชื่อมอยู่** รวมถึงไดรฟ์ที่เชื่อมผ่าน Finder พร้อมปุ่ม Open และ Eject
- **เชื่อมหลายลูกพร้อมกัน** เลือกด้วย Command/Shift หรือบันทึกเป็นกลุ่มไว้เรียกใช้ครั้งต่อไป
- **ใช้บัญชีสะดวกขึ้น** ลองใช้การเชื่อมต่อเดิมของ macOS และเลือกจำบัญชี SMB ใน Keychain ได้
- **เชื่อมต่อได้หลายเครือข่าย** ใช้ใน LAN, ผ่าน VPN เช่น Tailscale หรือเพิ่ม WebDAV URL โดยปลายทางต้องเข้าถึงได้และมีสิทธิ์ใช้งาน
- **ติดตามลูกที่เชื่อมไม่ได้** แสดงรายการเมื่อเชื่อมกลุ่มไม่ครบ และค้นหาชื่อแชร์ที่อาจย้ายไปอีกเครื่องให้ผู้ใช้ยืนยัน
- **ถอดไดรฟ์ผ่าน macOS** แจ้งปัญหาเมื่อ Eject ไม่สำเร็จ โดยไม่บังคับถอดหรือปิดแอปอื่น
- **รู้เมื่อมีรุ่นใหม่** เลือกแจ้งทุกวัน ทุก 2 วัน หรือปิดได้ ตรวจขณะเปิดแอปและลิงก์ไปดาวน์โหลดเอง
- **หน้าตาเข้ากับ Mac** เลือก System, Light หรือ Dark และใช้ Liquid Glass บน macOS 26

MacNDMG เน้นการเชื่อมต่อไดรฟ์ ส่วนการเปิดดูและจัดการไฟล์ใช้ Finder ต่อได้ตามปกติ กลุ่มจะเชื่อมเมื่อผู้ใช้กด Connect และยังไม่รองรับการ mount ผ่าน FTP/SFTP

## ก่อนเริ่มทดลอง

**Preview 1 พร้อมสำหรับการทดลองใช้งานและรับข้อเสนอแนะ** แต่ยังอาจพบปัญหาในบางเครือข่าย แนะนำให้เริ่มกับไดรฟ์ที่ไม่กระทบงานสำคัญก่อน โดยเฉพาะการเชื่อมผ่าน VPN หรือการย้ายไดรฟ์ระหว่างเครื่อง

การพบชื่อแชร์เหมือนกันไม่ได้ยืนยันว่าเป็นฮาร์ดดิสก์ลูกเดิม แอปจึงให้ตรวจและยืนยันตำแหน่งใหม่ก่อนบันทึก ส่วนการแจ้งว่าแอปใดกำลังใช้ไดรฟ์อยู่ขึ้นกับข้อมูลที่ macOS อนุญาตให้ตรวจได้

ชื่อรุ่นที่แสดงเริ่มที่ **Preview 1** ส่วนเลขภายใน **2.3.9** ใช้เรียงลำดับอัปเดต ดูทั้งสองค่าได้ที่ **About & support → About MacNDMG**

## แจ้งปัญหาและติดต่อ

เปิดเมนู **About & support** ด้านล่างแถบซ้ายในแอป หรือใช้ลิงก์นี้:

- [Report a bug](https://github.com/Aikmathee/MAC-NDMG/issues/new?template=bug_report.md) — บอกอาการ ขั้นตอนที่ทำ และรุ่นของแอป ต้องลงชื่อเข้าใช้ GitHub ก่อนส่ง
- [Contact me](https://www.instagram.com/aik_mathee/) — ติดต่อผ่าน Instagram
- [Buy me a coffee](https://buymeacoffee.com/aik_mathee) — สนับสนุนผู้พัฒนา

รายงานบน GitHub เป็นสาธารณะ โปรดลบรหัสผ่าน ชื่อบัญชี ชื่อเครื่อง IP และข้อมูลส่วนตัวออกจากข้อความ ภาพ หรือ log ก่อนส่ง แอปไม่ส่งรายงานให้อัตโนมัติ

<details>
<summary><strong>English quick start</strong></summary>

MacNDMG is a native macOS companion for connecting network drives individually or in groups. Use Finder to browse and manage files.

1. Download the **Apple Silicon** or **Intel** DMG for your Mac.
2. Open it and drag **MacNDMG** into **Applications**.
3. Choose a server, load its drives and connect. For remote SMB, connect your VPN first. You can also add an SMB share URL or a WebDAV endpoint.

Requires macOS 13 or later. Python is included. Liquid Glass requires macOS 26.

**Preview 1 is a test release**, ad-hoc signed and not Apple-notarized. macOS may block the first launch; review [Apple's instructions](https://support.apple.com/en-au/102445) and allow this app only if you trust its source. Start with noncritical drives and report issues through **About & support → Report a bug**.

Update reminders run while the app is open. Choose daily, every 2 days or Off under **Updates**. Downloads open on GitHub; installation is manual.

</details>

<details>
<summary><strong>สำหรับนักพัฒนา / Development</strong></summary>

| โฟลเดอร์ | เนื้อหา |
| --- | --- |
| `native/` | SwiftUI, การทำงานร่วมกับ macOS และ Keychain |
| `src/` | บริการ Python สำหรับค้นหาและเชื่อมไดรฟ์ |
| `tests/` | การทดสอบบริการและเครื่องมือ |
| `native/tests/` | การทดสอบ Swift |
| `scripts/` | Build, package และ release |
| `docs/` | คู่มือและบันทึกการพัฒนา |

[Development guide](docs/DEVELOPMENT.md) · [Release process](docs/RELEASING.md) · [Network validation](docs/NETWORK_VALIDATION.md) · [Notarization](docs/NOTARIZATION.md) · [Changelog](CHANGELOG.md)

</details>
