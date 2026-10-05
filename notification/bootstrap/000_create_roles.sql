-- =============================================================================
-- Bootstrap — DB role + schema ของ notification-service (รันครั้งเดียว ด้วย superuser)
-- =============================================================================
-- service นี้เป็น service ใหม่ ไม่มีตารางเดิมใน public ให้ย้าย ต่างจาก pet/event
-- ที่ต้องมีสคริปต์ 001_move_to_*_schema.sql แยกต่างหาก — ที่นี่รวบเป็นไฟล์เดียว
--
--   psql "$SUPERUSER_DSN" -v migrator_pw=... -v app_pw=... \
--        -f notification/bootstrap/000_create_roles.sql
--   (ไม่ต้องใส่ single quote ครอบค่า — :'ชื่อตัวแปร' ใส่ให้เองแล้ว)
-- =============================================================================

-- ⚠️ ห้ามใช้ :ตัวแปร ข้างใน DO $$ ... $$ — psql แทนค่าตอน lex เท่านั้น
-- และมองข้อความใน dollar quote เป็น token เดียว จึงไม่แทนค่าให้

SELECT format('CREATE ROLE notification_migrator LOGIN PASSWORD %L', :'migrator_pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'notification_migrator')
\gexec

SELECT format('CREATE ROLE notification_app LOGIN PASSWORD %L', :'app_pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'notification_app')
\gexec

GRANT CONNECT ON DATABASE vertex TO notification_migrator, notification_app;

CREATE SCHEMA IF NOT EXISTS notification AUTHORIZATION notification_migrator;

-- notification_migrator: DDL ใช้เฉพาะ Flyway Job (เป็นเจ้าของ schema จึง CREATE
--                         TABLE / ALTER TABLE ได้โดยไม่ต้องมีสิทธิ์ระดับ database)
-- notification_app:      DML เท่านั้น ใช้ใน runtime
--
-- 🔐 ผลที่ได้: notification_app รัน CREATE/ALTER/DROP TABLE ไม่ได้
--    → AutoMigrate กลับมาเองไม่ได้ และมองไม่เห็นข้อมูลของ pet/auth/event เลย
GRANT USAGE ON SCHEMA notification TO notification_app;

-- ตารางที่ Flyway สร้างในอนาคตต้องให้สิทธิ์ notification_app อัตโนมัติ
-- ไม่งั้นทุก migration ที่เพิ่มตารางใหม่ต้องมาไล่ GRANT เองทุกครั้ง
ALTER DEFAULT PRIVILEGES FOR ROLE notification_migrator IN SCHEMA notification
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO notification_app;
ALTER DEFAULT PRIVILEGES FOR ROLE notification_migrator IN SCHEMA notification
    GRANT USAGE, SELECT ON SEQUENCES TO notification_app;
