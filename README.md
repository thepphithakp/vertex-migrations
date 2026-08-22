# vertex-migrations

Database migration ของทุก service ใน Vertex รวมไว้ที่เดียว

---

## ทำไมถึงรวมไว้ที่เดียว

ทุก service ใช้ database `vertex_pet` ตัวเดียวกัน การมี migration กระจายอยู่ 3 repo
ที่ต่างก็แก้ database เดียวกัน ทำให้ไม่มีที่ไหนเลยที่เห็นภาพรวมของ schema ทั้งระบบ

repo นี้แก้ปัญหานั้น — เปิดที่เดียวเห็นครบว่า database เปลี่ยนไปอย่างไรบ้าง

---

## ⚠️ กฎเหล็กที่มาพร้อมกับการแยก repo

การแยก migration ออกจาก service ทำให้ **schema version กับ code version หลุดจากกัน**
เดิม migration image ใช้ tag เดียวกับ app image จึงตรงกันเสมอโดยอัตโนมัติ

ตอนนี้ต้องอาศัยวินัยแทน:

### 1. deploy migration ก่อน app เสมอ

```
migration (repo นี้)  →  แล้วค่อย  →  app (repo ของ service)
```

ถ้าสลับลำดับ app จะล้มตั้งแต่ boot พร้อมข้อความว่าต้องรัน migration ก่อน
(ดู `internal/bootstrap/schema.go` `AssertSchemaVersion` ที่ pet-service)
— ล้มแบบนี้ปลอดภัยกว่าปล่อยให้ขึ้นแล้วไปพังตอน query แรก

### 2. เพิ่ม V__ ใหม่ที่โค้ดพึ่งพา → ต้องอัปเดต 2 ที่

| ที่ | ทำอะไร |
|---|---|
| repo นี้ | เพิ่มไฟล์ `V<n>__*.sql` |
| service repo | เพิ่ม `RequiredSchemaVersion` ใน `internal/bootstrap/schema.go` |
| service repo | ปรับ `migration.image.tag` ใน `helm/*/values.yaml` ให้ชี้ image ใหม่ |

### 3. ห้ามแก้ไฟล์ V__ ที่ apply บน environment ใดแล้ว
checksum จะเพี้ยน `flyway validate` fail ทั้ง pipeline — เขียน `V<ถัดไป>__fix_xxx.sql` แทน

---

## โครงสร้าง

```
pet/
├── migration/   V__  DDL + seed ครั้งแรก · รันครั้งเดียว · IMMUTABLE
├── codeowned/   R__  เฉพาะตารางที่ backoffice แก้ไม่ได้
├── seed/        R__  ข้อมูลตัวอย่าง local เท่านั้น (ไม่เข้า image)
└── bootstrap/        script รันด้วยมือครั้งเดียว (ไม่เข้า image)
auth/
├── migration/
├── codeowned/
└── bootstrap/
verify/          SQL พิสูจน์ว่าข้อมูลครบ
rollback/        เอกสารว่าถ้าต้องถอยจะรันอะไร (ไม่ถูกรันอัตโนมัติ)
```

---

## การตั้งค่าต่อ service

| | pet | auth |
|---|---|---|
| `FLYWAY_SCHEMAS` | `pet` | `public` |
| `FLYWAY_TABLE` | `flyway_schema_history` | `flyway_schema_history_auth` |
| `FLYWAY_LOCATIONS` | `filesystem:/flyway/sql/pet/migration,filesystem:/flyway/sql/pet/codeowned` | `filesystem:/flyway/sql/auth/migration,filesystem:/flyway/sql/auth/codeowned` |

> auth ยังอยู่ schema `public` — การย้ายไป schema `auth` เป็นงานแยก
> ระหว่างที่ยังใช้ database เดียวกัน ต้องใช้ `FLYWAY_TABLE` คนละชื่อ
> ไม่งั้นสอง service จะแย่งกันเขียนตาราง history เดียวกัน

---

## คำสั่งที่ใช้บ่อย

```bash
make db-up            # ยก postgres + migrate ทั้ง pet และ auth
make migrate-pet      # migrate เฉพาะ pet
make migrate-auth     # migrate เฉพาะ auth
make info             # ดูสถานะ migration ทั้งสอง service
make validate         # ตรวจ checksum
make db-reset         # ล้างแล้วสร้างใหม่
```

---

## กติกาการเขียน migration

อ่าน `vertex-pet-service/docs/MIGRATION_GUIDE.md` — สรุปข้อที่พลาดบ่อยที่สุด:

1. **`R__` รันหลัง `V__` ทั้งหมดเสมอ** → `V__` ห้ามพึ่งข้อมูลที่ `R__` เป็นคน seed
   (เคยทำให้ V3 ของ auth ล้มด้วย foreign key violation มาแล้ว)
2. **`R__` ใช้ได้เฉพาะข้อมูลที่ UI แก้ไม่ได้** — ไม่งั้นการแก้ไฟล์ครั้งเดียว
   จะลบสิ่งที่ admin แก้ผ่าน UI ทิ้งทั้งตาราง
3. **ห้าม CHECK constraint กับค่าที่มาจาก master data** ที่แก้ผ่าน UI ได้
   ใช้ FOREIGN KEY แบบ `NOT VALID` แทน
4. **ชื่อตารางที่ GORM สร้างอาจไม่ตรงกับที่คิด** — `OAuthIdentity` กลายเป็น
   `o_auth_identities` ไม่ใช่ `oauth_identities` ตรวจกับฐานข้อมูลจริงเสมอ
