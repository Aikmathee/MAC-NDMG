# ติดตั้ง MacNDMG Preview 1 บน Mac

[ดาวน์โหลดเวอร์ชันล่าสุด](https://github.com/Aikmathee/MAC-NDMG/releases/latest)

## เลือกไฟล์

เปิดเมนู  → About This Mac ดูชื่อชิป:

- Apple M1 ขึ้นไป: เลือก `Network-Drive-Manager-macOS-Apple-Silicon.dmg`
- Intel: เลือก `Network-Drive-Manager-macOS-Intel.dmg`

ต้องใช้ macOS 13 ขึ้นไป ไม่ต้องติดตั้ง Python หรือใช้ Terminal

## ติดตั้ง

1. เปิดไฟล์ DMG ที่ดาวน์โหลด
2. ลาก MacNDMG ไปยัง Applications
3. เปิดแอพจาก Applications แล้วนำดิสก์ติดตั้งออกได้

รุ่นทดลองนี้ยังไม่ได้รับการ notarize จาก Apple ถ้าระบบบล็อกการเปิด ให้ตรวจแหล่งดาวน์โหลด แล้วไปที่ System Settings → Privacy & Security → Open Anyway สำหรับแอพนี้ ดู [คำแนะนำของ Apple](https://support.apple.com/en-au/102445) ไม่จำเป็นต้องปิดการป้องกันของระบบ

## เริ่มเชื่อมต่อ

- เลือกเครื่องใน Overview แล้ว Load drives หรือ Connect all
- หน้าต่างเข้าสู่ระบบมี Remember account สำหรับบันทึกบัญชี SMB ใน Keychain
- Connected แสดงไดรฟ์ที่เชื่อมอยู่ รวมไดรฟ์ที่เชื่อมจาก Finder
- กด Command หรือ Shift เพื่อเลือกหลายรายการ แล้ว Connect หรือ Eject
- Groups ใช้บันทึกชุดไดรฟ์จากหลายเครื่อง กด Connect group เมื่อต้องการใช้งาน
- Add server รับ IP, DNS, MagicDNS, `smb://server/Share` หรือ WebDAV URL
- ถ้าอยู่นอก LAN ให้เชื่อม Tailscale/VPN ก่อน เครื่องปลายทางต้องเปิดบริการแชร์และอนุญาตการเข้าถึง
- Appearance ด้านล่างแถบซ้ายมี System, Light และ Dark
- About & support รวมข้อมูล Preview/build, Updates, ติดต่อผู้พัฒนา แจ้งบั๊ก และสนับสนุนผ่าน Buy me a coffee
- Updates เลือกตรวจทุกวัน ทุก 2 วัน หรือปิดได้ ตรวจขณะเปิดแอปและให้ดาวน์โหลดรุ่นใหม่เอง

แนะนำให้เริ่มทดลองกับไดรฟ์ที่ไม่กระทบงานสำคัญก่อน หากพบปัญหา เปิด About & support → Report a bug ต้องลงชื่อเข้าใช้ GitHub และตรวจว่าไม่มีข้อมูลส่วนตัวก่อนส่งรายงานสาธารณะ

หากใช้ไฟล์ ZIP แทน DMG ให้แตก ZIP แล้วลากแอพไปยัง Applications เช่นกัน

ไดรฟ์ที่มีไฟล์กำลังใช้งานอาจ Eject ไม่สำเร็จ ให้ปิดไฟล์แล้วลองใหม่ แอพไม่บังคับถอดไดรฟ์

[คู่มือทั้งหมด](USER_GUIDE.md) · [กลับหน้าดาวน์โหลด](../README.md)
