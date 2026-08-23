-- =============================================================================
-- V11 — ล้างซากคอลัมน์เก่าใน caregiver_permissions
-- =============================================================================
-- 🔴 แก้ปัญหาที่ production ใช้งานไม่ได้จริง
--
-- ตอน AutoMigrate ยุคแรก GORM สร้าง join table ด้วยชื่อคอลัมน์
-- (pet_caregiver_id, pet_permission_id) ต่อมา struct ถูกเปลี่ยนชื่อ
-- GORM จึงสร้างคอลัมน์ชุดใหม่ (caregiver_model_id, permission_model_id)
-- เพิ่มเข้าไป "โดยไม่ลบของเก่า" — เพราะ AutoMigrate ไม่เคยลบอะไร
--
-- ผลบน production:
--   pet_permission_id  NOT NULL ไม่มี default
--   แต่โค้ดเขียนเฉพาะ caregiver_model_id / permission_model_id
--   → ทุก INSERT ล้มด้วย null value in column "pet_permission_id"
--   → ตั้งสิทธิ์ให้ผู้ดูแลไม่ได้เลย
--
-- และ primary key อยู่บนคอลัมน์เก่าที่มี default เป็น gen_random_uuid()
-- ถ้า INSERT ผ่านได้ ก็จะไม่กันค่าซ้ำบนคอลัมน์ที่ใช้จริงอยู่ดี
--
-- database เปล่าไม่มีปัญหานี้เพราะ V1 สร้างเฉพาะคอลัมน์ชุดใหม่
-- จึงเจอได้เฉพาะตอนเทียบ schema ของ production กับ database เปล่า
-- (scripts/verify-schema.sh)
-- =============================================================================

-- ย้ายข้อมูลที่อาจอยู่ในคอลัมน์เก่ามาไว้ในคอลัมน์ใหม่ก่อน
--
-- ตอนเขียน migration นี้ production มี 0 แถว แต่เขียนเผื่อไว้
-- เพราะ environment อื่นอาจมีข้อมูลค้างอยู่
UPDATE caregiver_permissions
SET caregiver_model_id = pet_caregiver_id
WHERE caregiver_model_id IS NULL AND pet_caregiver_id IS NOT NULL;

UPDATE caregiver_permissions
SET permission_model_id = pet_permission_id
WHERE permission_model_id IS NULL AND pet_permission_id IS NOT NULL;

-- ทิ้งแถวที่ยังไม่มีคอลัมน์ใหม่ครบ — เป็นข้อมูลที่โค้ดปัจจุบันอ่านไม่เห็นอยู่แล้ว
DELETE FROM caregiver_permissions
WHERE caregiver_model_id IS NULL OR permission_model_id IS NULL;

-- ลบ constraint ที่ผูกกับคอลัมน์เก่า
ALTER TABLE caregiver_permissions
    DROP CONSTRAINT IF EXISTS caregiver_permissions_pkey,
    DROP CONSTRAINT IF EXISTS fk_caregiver_permissions_pet_caregiver,
    DROP CONSTRAINT IF EXISTS fk_caregiver_permissions_pet_permission;

ALTER TABLE caregiver_permissions
    DROP COLUMN IF EXISTS pet_caregiver_id,
    DROP COLUMN IF EXISTS pet_permission_id;

-- คอลัมน์ที่ใช้จริงต้องห้ามว่าง
ALTER TABLE caregiver_permissions
    ALTER COLUMN caregiver_model_id SET NOT NULL,
    ALTER COLUMN permission_model_id SET NOT NULL;

-- default gen_random_uuid() บน foreign key ไม่มีความหมาย
-- และเคยเป็นสาเหตุที่ทำให้ primary key เก่าไม่กันค่าซ้ำ
ALTER TABLE caregiver_permissions
    ALTER COLUMN caregiver_model_id DROP DEFAULT;

-- primary key บนคอลัมน์ที่ใช้จริง — กันสิทธิ์ซ้ำของ caregiver คนเดียวกัน
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        WHERE t.relname = 'caregiver_permissions' AND c.contype = 'p'
    ) THEN
        ALTER TABLE caregiver_permissions
            ADD CONSTRAINT caregiver_permissions_pkey
            PRIMARY KEY (caregiver_model_id, permission_model_id);
    END IF;
END $$;

-- ชื่อ FK ให้ตรงกับ database เปล่า เพื่อให้ทั้งสองเส้นทางเหมือนกันจริง
ALTER TABLE caregiver_permissions
    DROP CONSTRAINT IF EXISTS fk_caregiver_permissions_caregiver_model,
    DROP CONSTRAINT IF EXISTS fk_caregiver_permissions_permission_model,
    DROP CONSTRAINT IF EXISTS fk_caregiver_permissions_caregiver,
    DROP CONSTRAINT IF EXISTS fk_caregiver_permissions_permission;

ALTER TABLE caregiver_permissions
    ADD CONSTRAINT fk_caregiver_permissions_caregiver
        FOREIGN KEY (caregiver_model_id) REFERENCES pet_caregivers(id) ON DELETE CASCADE,
    ADD CONSTRAINT fk_caregiver_permissions_permission
        FOREIGN KEY (permission_model_id) REFERENCES pet_permissions(id) ON DELETE CASCADE;

-- ซากอีกตัวจากยุค AutoMigrate: FK ซ้ำบน litter_logs
-- fk_litter_logs_pet ทำหน้าที่เดียวกันอยู่แล้ว
ALTER TABLE litter_logs
    DROP CONSTRAINT IF EXISTS fk_pets_litter_logs;
