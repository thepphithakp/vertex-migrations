# vertex-migrations

Database migration ของทุก service ใน Vertex รวมไว้ที่เดียว

---

## ทำไมถึงรวมไว้ที่เดียว

ทุก service ใช้ database `vertex` ตัวเดียวกัน การมี migration กระจายอยู่ 3 repo
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
| `FLYWAY_SCHEMAS` | `pet` | `auth` |
| `FLYWAY_TABLE` | `flyway_schema_history` | `flyway_schema_history` |
| `FLYWAY_LOCATIONS` | `filesystem:/flyway/sql/pet/migration,...` | `filesystem:/flyway/sql/auth/migration,...` |

ทั้งสองใช้ชื่อ history table เดียวกันได้ เพราะอยู่คนละ schema แล้ว

> ⚠️ ตอน `event` ย้ายมา (Phase 10) ก็ใช้แพตเทิร์นเดียวกัน
> **ตราบใดที่ service ไหนยังอยู่ `public` service นั้นต้องใช้ชื่อ history table
> ที่ไม่ซ้ำกับตัวอื่น** ไม่งั้นจะแย่งกันเขียนตารางเดียวกัน

---

## Deploy ขึ้น cluster

Flyway รันเป็น **Kubernetes Job** ผ่าน helm chart ใน `helm/vertex-migrations`
chart นี้แยกจาก service โดยตั้งใจ — deploy migration ก่อน แล้วค่อย deploy app

```bash
# ครั้งแรก (database มีข้อมูลอยู่แล้ว → baseline ที่ V1)
helm upgrade --install vertex-migrations ./helm/vertex-migrations \
  --namespace vertex \
  --set image.tag=sha-<commit>

# ดูผล
kubectl get jobs -n vertex -l app.kubernetes.io/component=migration
kubectl logs -n vertex job/vertex-migrations-pet-1

# ดูสถานะเฉยๆ ไม่แก้อะไร
helm upgrade vertex-migrations ./helm/vertex-migrations -n vertex \
  --reuse-values --set command=info
```

### ใช้กับ cluster อื่น

chart รับค่าทั้งหมดผ่าน values จึงย้าย cluster ได้ด้วยการเปลี่ยนไฟล์ values อย่างเดียว

```yaml
# values-staging.yaml
db:
  host: postgres.staging.svc.cluster.local
  sslMode: require
image:
  tag: sha-abc1234
services:
  - name: auth
    enabled: true
    schema: public
    historyTable: flyway_schema_history_auth
    credentialsSecret: auth-db-migrator
    baselineOnMigrate: false   # cluster ใหม่ที่ database เปล่า ไม่ต้อง baseline
  - name: pet
    enabled: true
    schema: pet
    historyTable: flyway_schema_history
    credentialsSecret: pet-db-migrator
    baselineOnMigrate: false
```

### RBAC สำหรับ CI/CD

`cluster/vertex-sa-rbac.yaml` สร้าง ServiceAccount ที่ CD ใช้ deploy
พร้อม Role ที่**จำกัดไว้ที่ namespace เดียว**

```bash
kubectl apply -f cluster/vertex-sa-rbac.yaml
```

ใช้ `Role` ไม่ใช่ `ClusterRole` โดยตั้งใจ — token ที่หลุดออกไปแตะ namespace อื่น
หรือ resource ระดับ cluster ไม่ได้เลย และจงใจไม่ให้ `pods/exec` เพราะ CD ไม่ต้องใช้

Secret ชนิด `kubernetes.io/service-account-token` ทำให้ได้ token ที่ไม่หมดอายุ
(ตั้งแต่ Kubernetes 1.24 ServiceAccount ไม่มี token ให้อัตโนมัติแล้ว
และ token จาก `kubectl create token` มีอายุจำกัด — เป็นสาเหตุที่ CD เคยพังมาแล้ว)

> ⚠️ token ที่ไม่หมดอายุแลกมาด้วยความเสี่ยง
> ถ้าหลุดต้องเพิกถอนด้วย `kubectl delete secret vertex-sa-token -n vertex`

### สิ่งที่ต้องมีอยู่ก่อนใน cluster

| ต้องมี | สร้างอย่างไร |
|---|---|
| Secret `pet-db-migrator` / `auth-db-migrator` (key: username, password) | สร้างจาก DB role ที่มีสิทธิ์ DDL |
| DB role ที่มีสิทธิ์ DDL **และเป็นเจ้าของตาราง** | `pet/bootstrap/000_create_roles.sql`, `auth/bootstrap/000_create_roles.sql` |
| schema `pet` + ตารางที่ย้ายมาแล้ว (เฉพาะ cluster ที่มีข้อมูลเดิม) | `pet/bootstrap/001_move_to_pet_schema.sql` |

> ⚠️ **`GRANT ALL` ไม่พอ** — `ALTER TABLE` ต้องการ *ownership* ไม่ใช่แค่ privilege
> ถ้า cluster มีตารางอยู่แล้วและเป็นของ role อื่น migration จะล้มด้วย
> `must be owner of table ...` — script ใน `bootstrap/` โอน ownership ให้แล้ว
>
> ⚠️ `bootstrap/` ไม่ได้อยู่ใน image และไม่ได้รันโดย Job
> เป็น script ที่รันด้วยมือครั้งเดียวตอนตั้งระบบ ต้องมี backup ก่อนเสมอ

---

## CI/CD

| ไฟล์ | ใช้เมื่อ |
|---|---|
| `.github/workflows/ci.yml` | ทุก PR — lint, migrate บน DB เปล่า, รันซ้ำเช็ค idempotent, validate |
| `.github/workflows/deploy.yml` | push main หรือกดเอง — build image แล้วรัน Flyway Job บน cluster |
| `Jenkinsfile` | สำรองไว้ถ้าย้ายไป Jenkins — ทำงานเทียบเท่า deploy.yml |

### รันเองแบบเลือกคำสั่งได้

ทั้ง GitHub Actions และ Jenkins รับ parameter เหมือนกัน

| parameter | ค่า | ความหมาย |
|---|---|---|
| `command` | `migrate` | รัน migration ที่ยังไม่ถูก apply |
| | `info` | **ดูสถานะเฉยๆ ไม่แก้อะไร** — ใช้ตรวจก่อนลงมือจริง |
| | `validate` | ตรวจ checksum ว่าไฟล์ที่ apply แล้วไม่ถูกแก้ |
| | `repair` | ซ่อม history table หลัง migration ล้ม ⚠️ ไม่ย้อนข้อมูล |
| `services` | `all` หรือ `pet,auth` | เลือกรันเฉพาะบาง service |

```bash
# ตรวจสถานะก่อนโดยไม่แตะอะไร
gh workflow run deploy.yml -f command=info -f services=all

# รัน migration เฉพาะ pet
gh workflow run deploy.yml -f command=migrate -f services=pet
```

### สิ่งที่ต้องตั้งก่อนใช้

| | GitHub Actions | Jenkins |
|---|---|---|
| kubeconfig | secret `KUBECONFIG_CONTENT` | credential file `kubeconfig-production` |
| registry | ใช้ `GITHUB_TOKEN` อัตโนมัติ | credential `registry-creds` |
| อนุมัติก่อน deploy | ตั้ง protection rule ที่ Settings → Environments | ใส่ `input` stage เพิ่ม |

> 🔐 kubeconfig ควรใช้ ServiceAccount ที่จำกัดสิทธิ์ไว้ที่ namespace เดียว
> ดู `cluster/vertex-sa-rbac.yaml`

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

## ข้อควรระวังตอนเขียน migration

### เปลี่ยนชนิดคอลัมน์ = ต้อง rollout restart pod หลัง migrate

`ALTER COLUMN ... TYPE ...` ทำให้ prepared statement ที่ pod เดิม cache ไว้ใช้ไม่ได้
PostgreSQL จะตอบ `cached plan must not change result type` (SQLSTATE 0A000)
กับทุก query จนกว่า connection จะถูกสร้างใหม่ — pod ที่รันอยู่จะ 500 ทั้งหมด

เกิดขึ้นจริงตอน `event` V2 เปลี่ยน `id` จาก text เป็น uuid (2026-08-23)
แก้ด้วย `kubectl rollout restart deploy/<service> -n vertex`

ถ้าห้าม downtime ให้ทำแบบสองเฟสแทน: เพิ่มคอลัมน์ใหม่ → ให้แอปเขียนทั้งสองที่ →
ย้ายข้อมูล → เปลี่ยนให้แอปอ่านคอลัมน์ใหม่ → ค่อยลบคอลัมน์เก่า

### ห้ามแก้ไฟล์ `V__` ที่ถูก apply ไปแล้ว

Flyway เก็บ checksum ของทุก migration ที่รันไปแล้ว แก้ไฟล์แม้แต่คอมเมนต์
จะทำให้ `validate` ล้มด้วย `Migration checksum mismatch` แล้ว deploy รอบถัดไปพัง
ต้องการเปลี่ยนอะไรให้เขียน `V__` ตัวใหม่เสมอ
