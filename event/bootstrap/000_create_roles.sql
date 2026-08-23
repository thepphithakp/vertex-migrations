-- =============================================================================
-- Bootstrap — DB role ของ event-service (รันครั้งเดียว ด้วย superuser)
-- =============================================================================
-- ไฟล์ใน bootstrap/ ไม่อยู่ใน FLYWAY_LOCATIONS — เป็น runbook script
-- ที่รันด้วยมือตอนตั้งระบบ ไม่ใช่ migration
--
--   psql "$SUPERUSER_DSN" -v migrator_pw=... -v app_pw=... -f 000_create_roles.sql
--   (ไม่ต้องใส่ single quote ครอบค่า — :'ชื่อตัวแปร' ใส่ให้เองแล้ว)
--
-- 🔴 ก่อนหน้านี้ event-service ต่อฐานข้อมูลด้วย vertex_admin ซึ่งเป็น superuser
--    แปลว่า service ที่แค่ต้องเขียน log อ่านและลบข้อมูลของ pet และ auth ได้หมด
--    ไฟล์นี้คือส่วนที่แก้เรื่องนั้น
-- =============================================================================

-- ⚠️ ห้ามใช้ :ตัวแปร ข้างใน DO $$ ... $$
--
-- psql แทนค่าตัวแปรตอน lex เท่านั้น และมันมองข้อความใน dollar quote
-- เป็น token เดียว จึงไม่แทนค่าให้ ผลคือ syntax error at or near ":"

SELECT format('CREATE ROLE event_migrator LOGIN PASSWORD %L', :'migrator_pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'event_migrator')
\gexec

SELECT format('CREATE ROLE event_app LOGIN PASSWORD %L', :'app_pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'event_app')
\gexec

GRANT CONNECT ON DATABASE vertex TO event_migrator, event_app;

-- ⚠️ GRANT ALL ไม่พอสำหรับ Flyway
--
-- ALTER TABLE ต้องการ ownership ไม่ใช่แค่ privilege
-- ถ้าตารางเป็นของ role อื่นอยู่ migration ที่มี ALTER TABLE จะล้มด้วย
--   ERROR: must be owner of table event_logs
--
-- 🔸 รันเฉพาะ cluster ที่มีตารางอยู่แล้ว — cluster ใหม่ที่ Flyway สร้างตารางเอง
--    ตารางจะเป็นของ migrator ตั้งแต่แรกอยู่แล้ว
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['event_logs']
    LOOP
        IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = t) THEN
            EXECUTE format('ALTER TABLE %I OWNER TO event_migrator', t);
            RAISE NOTICE 'โอน % ให้ event_migrator', t;
        END IF;
    END LOOP;
END $$;

-- event_migrator: DDL ใช้เฉพาะ Flyway Job
-- event_app:      DML เท่านั้น ใช้ใน runtime
--
-- 🔐 ผลที่ได้: event_app รัน CREATE/ALTER/DROP TABLE ไม่ได้
--    → AutoMigrate กลับมาเองไม่ได้อีก
--    → และมองไม่เห็นข้อมูลของ pet/auth เลย (ไม่ได้ GRANT USAGE ให้)
