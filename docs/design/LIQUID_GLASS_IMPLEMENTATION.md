# ผลการปรับ Liquid Glass — v2.2.0

วันที่: 21 ตุลาคม 2026

## สิ่งที่ทำ

- ใช้ NavigationSplitView และ toolbar ของ macOS แทนโครงหน้าต่างแบบแบ่งความกว้างคงที่
- Sidebar ปรับความกว้างและซ่อนได้ หน้าต่างมีขนาดเริ่มต้นปกติและบันทึกตำแหน่ง/ขนาด
- ไฟล์แจก build ด้วย Xcode 26 / SDK 26+ และใช้ SwiftUI glass/glassProminent แบบ typed บน macOS 26
- ชุดคำสั่งเมื่อเลือกหลายรายการใช้กระจกหนึ่งพื้นผิว พร้อม transition ที่คำนึงถึง Reduce Motion
- แยกพื้นผิวข้อมูลเป็น ContentCard; hover, selection และ increased contrast มีการแสดงผลแยกกัน
- หน้าแรกเรียง Connected → Groups แบบย่อ → Servers และปรับจำนวนคอลัมน์ตามพื้นที่
- เพิ่มพื้นที่กด Open/Eject และใช้สี/ตัวอักษรตามระบบ
- Add server และ Sign in ใช้ grouped forms ของระบบ โดยคงการตรวจบัญชีและ Keychain เดิม
- แยก native/Design และ native/Views ออกจาก store และ app entry point
- กำหนดเงื่อนไข SDK 26 ทั้งตอน build และตรวจ bundle ใน CI; งาน branch เก่าถูกยกเลิกเมื่อมี commit ใหม่ แต่คงงาน release tags

## การตรวจที่ทำแล้ว

| การตรวจ | ผล / ขอบเขต |
| --- | --- |
| Python services | 43 เทสต์ผ่าน; ไม่มีการเปลี่ยน protocol, mounter หรือไฟล์ข้อมูลผู้ใช้ |
| Compatibility compilation | คอมไพล์ด้วย SDK 15.5 โดยคง deployment target macOS 13 |
| Modern compilation | CI รอบหลักผ่านทั้ง Apple Silicon / Intel ด้วย SDK 26.2 |
| App bundle | ตรวจ signature, version และ clean-install service responses; CI ตรวจ modern glass build flag เพิ่ม |
| หน้าต่างและ sidebar | ตรวจขนาดเล็กประมาณ 900 × 680 และการลากเปลี่ยนความกว้าง sidebar |
| Native selection | Command-click, Shift/arrow selection, Command-A และเมนูคลิกขวา ทำงานกับรายการหลายสิบรายการ |
| Appearance | ตรวจ Dark / Light จาก artifact SDK 26 จริง และคืนเป็น Dark หลังทดสอบ |
| Forms | ตรวจ Add server และ Sign in ด้วยปลายทาง .invalid ชั่วคราว ไม่มีการส่งบัญชีหรือเชื่อมไดรฟ์ |
| Accessibility semantics | ตรวจชื่อปุ่ม, secure password field, switch และสถานะ selected ผ่าน accessibility tree |
| ข้อมูลส่วนตัว | ไม่อัปโหลดภาพหน้าจอที่มีชื่อเครื่องหรือ IP จริง; ไม่มีข้อมูลตัวอย่างจากการตรวจค้างในรายการเซิร์ฟเวอร์ที่บันทึก |

ผล build ของ release สุดท้ายตรวจใน GitHub Actions และหน้า Releases ของ v2.2.0

## ข้อจำกัดที่ยังต้องระบุ

- ยังไม่ได้ทดสอบ UI จริงบน macOS 13, 14 และ 15 แม้โค้ด fallback จะคอมไพล์และตรวจ availability แล้ว
- ยังไม่ได้ walkthrough ด้วย VoiceOver เต็มรูปแบบ หรือทดสอบการเปิด/ปิด accessibility preferences ทุกชุดบนเครื่องจริง
- ลดความโปร่งใสและ motion มีทางเลือกในโค้ด; native controls ใช้การปรับของระบบ แต่ยังไม่ใช่ผลตรวจเชิงภาพครบทุก combination
- ยังไม่มีตัวเลข FPS หรือผล Instruments เปรียบเทียบก่อน/หลัง การตรวจครั้งนี้เป็น visual/interaction QA กับรายการหลายสิบรายการ
- ยังไม่ได้เพิ่ม custom morph IDs เพราะชุดคำสั่งปัจจุบันไม่มีการเปลี่ยนรูปที่จำเป็น ใช้ interaction ของระบบและ transition สั้นของแถบเลือกแทน
- ไอคอนแบบ Icon Composer และ Apple notarization ยังเป็นงานแยก ไม่ได้อ้างว่าเสร็จในรุ่นนี้
- การทดสอบนี้ไม่ยืนยัน authenticated mount บนเซิร์ฟเวอร์ภายนอก และไม่ได้ทดลองถอดไดรฟ์ที่ใช้งานอยู่

## การ build ในเครื่อง

เครื่องที่มี SDK 26+ ใช้คำสั่งใน Development guide เพื่อ build ตัวจริง หากใช้ SDK 15.5 จะได้ compatibility build สำหรับตรวจ layout ซึ่งไม่ใช่ตัวแทนของปุ่ม Liquid Glass บนไฟล์แจก ต้องใช้ artifact/release SDK 26 สำหรับ visual QA ขั้นสุดท้าย

[แผนต้นฉบับ](LIQUID_GLASS_PLAN.md) · [Development](../DEVELOPMENT.md)
