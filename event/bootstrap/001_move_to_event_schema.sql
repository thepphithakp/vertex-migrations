-- =============================================================================
-- Bootstrap — ย้าย event_logs จาก public ไป schema event (รันครั้งเดียว)
-- =============================================================================
-- ⚠️ ลำดับที่ห้ามสลับ
--   1. deploy event-service ที่มี search_path=event,public ก่อน
--      (schema ที่ยังไม่มีถูกข้ามไปเฉยๆ ไม่ error แอปจึงยังหาตารางใน public เจอ)
--   2. backup + บันทึก fingerprint
--   3. รันไฟล์นี้ → แอปหาตารางเจอใน event ทันทีโดยไม่ต้อง restart
--   4. พิสูจน์ fingerprint ก่อน/หลังว่าตรงกัน
--   5. เปิด Flyway ของ event ใน values-prod.yaml
--
-- ALTER TABLE ... SET SCHEMA เป็น metadata-only ไม่มีการ copy ข้อมูล
-- และ DDL ของ PostgreSQL เป็น transactional → สำเร็จทั้งหมดหรือ rollback ทั้งหมด
--
-- event_logs เป็นตารางสุดท้ายที่เหลือใน public — ย้ายเสร็จแล้ว public ควรว่าง
-- =============================================================================

BEGIN;

SET lock_timeout = '5s';
SET statement_timeout = '5min';

CREATE SCHEMA IF NOT EXISTS event;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'event_logs') THEN
        ALTER TABLE public.event_logs SET SCHEMA event;
        RAISE NOTICE 'ย้าย public.event_logs → event.event_logs';
    ELSE
        RAISE NOTICE 'ไม่มี public.event_logs — ข้าม (อาจย้ายไปแล้ว)';
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
        WHERE c.relkind = 'S' AND n.nspname = 'public' AND tn.nspname = 'event'
    LOOP
        EXECUTE format('ALTER SEQUENCE public.%I SET SCHEMA event', s.relname);
        RAISE NOTICE 'ย้าย sequence % → event', s.relname;
    END LOOP;
END $$;

GRANT USAGE ON SCHEMA event TO event_app, event_migrator;
GRANT ALL   ON SCHEMA event TO event_migrator;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA event TO event_app;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA event TO event_app;

-- ตารางที่ Flyway สร้างในอนาคตต้องให้สิทธิ์ event_app อัตโนมัติ
-- ไม่งั้นทุก migration ที่เพิ่มตารางใหม่จะต้องมาไล่ GRANT เองทุกครั้ง
ALTER DEFAULT PRIVILEGES FOR ROLE event_migrator IN SCHEMA event
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO event_app;
ALTER DEFAULT PRIVILEGES FOR ROLE event_migrator IN SCHEMA event
    GRANT USAGE, SELECT ON SEQUENCES TO event_app;

COMMIT;
