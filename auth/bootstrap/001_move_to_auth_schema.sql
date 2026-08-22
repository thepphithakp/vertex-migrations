-- =============================================================================
-- Bootstrap — ย้ายตารางของ auth จาก public ไป schema auth (รันครั้งเดียว)
-- =============================================================================
-- ⚠️ ลำดับที่ห้ามสลับ
--   1. deploy auth-service ที่ DATABASE_URL มี search_path=auth,public ก่อน
--      (schema ที่ยังไม่มีถูกข้ามไปเฉยๆ ไม่ error แอปจึงยังหาตารางใน public เจอ)
--   2. backup + บันทึก fingerprint
--   3. รันไฟล์นี้ → แอปหาตารางเจอใน auth ทันทีโดยไม่ต้อง restart
--   4. พิสูจน์ fingerprint ก่อน/หลังว่าตรงกัน
--   5. เปลี่ยน FLYWAY_SCHEMAS เป็น auth
--
-- ALTER TABLE ... SET SCHEMA เป็น metadata-only ไม่มีการ copy ข้อมูล
-- และ DDL ของ PostgreSQL เป็น transactional → สำเร็จทั้งหมดหรือ rollback ทั้งหมด
-- =============================================================================

BEGIN;

SET lock_timeout = '5s';
SET statement_timeout = '5min';

CREATE SCHEMA IF NOT EXISTS auth;

DO $$
DECLARE
    t text;
    moved int := 0;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'users', 'o_auth_identities', 'roles', 'user_roles', 'bootstrap_admins'
    ]
    LOOP
        IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = t) THEN
            EXECUTE format('ALTER TABLE public.%I SET SCHEMA auth', t);
            moved := moved + 1;
            RAISE NOTICE 'ย้าย public.% → auth.%', t, t;
        END IF;
    END LOOP;
    RAISE NOTICE 'ย้ายตาราง % รายการ', moved;
END $$;

-- ย้าย history table ตามไปด้วย แล้วเปลี่ยนชื่อให้เหมือน pet
--
-- ตอนอยู่ public ต้องใช้ชื่อ flyway_schema_history_auth เพื่อไม่ให้ชนกับ service อื่น
-- พอมี schema ของตัวเองแล้วไม่จำเป็นอีก ใช้ชื่อมาตรฐานได้
-- ⚠️ ต้องแก้ FLYWAY_TABLE ใน helm values ให้ตรงกันด้วย ไม่งั้น Flyway จะคิดว่า
--    ยังไม่เคย migrate แล้วพยายามรัน V1 ใหม่ทั้งหมด
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='flyway_schema_history_auth') THEN
        ALTER TABLE public.flyway_schema_history_auth SET SCHEMA auth;
        ALTER TABLE auth.flyway_schema_history_auth RENAME TO flyway_schema_history;
        RAISE NOTICE 'ย้าย history table → auth.flyway_schema_history';
    END IF;
END $$;

-- sequence ที่อาจค้างอยู่ที่ public
DO $$
DECLARE s record;
BEGIN
    FOR s IN
        SELECT c.relname FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_depend d ON d.objid = c.oid AND d.deptype = 'a'
        JOIN pg_class t ON t.oid = d.refobjid
        JOIN pg_namespace tn ON tn.oid = t.relnamespace
        WHERE c.relkind = 'S' AND n.nspname = 'public' AND tn.nspname = 'auth'
    LOOP
        EXECUTE format('ALTER SEQUENCE public.%I SET SCHEMA auth', s.relname);
        RAISE NOTICE 'ย้าย sequence % → auth', s.relname;
    END LOOP;
END $$;

GRANT USAGE ON SCHEMA auth TO auth_migrator;
GRANT ALL   ON SCHEMA auth TO auth_migrator;

COMMIT;
