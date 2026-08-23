-- =============================================================================
-- Bootstrap 000 — DB user แยกสิทธิ์ (รันครั้งเดียว ด้วย superuser)
-- =============================================================================
-- ไฟล์ในโฟลเดอร์ bootstrap/ ไม่อยู่ใน FLYWAY_LOCATIONS — เป็น runbook script
-- ที่รันด้วยมือครั้งเดียวตอนตั้งระบบ ไม่ใช่ migration
--
-- วิธีรัน:
--   psql "$SUPERUSER_DSN" -v migrator_pw=... -v app_pw=... -f 000_create_roles.sql
--   (ไม่ต้องใส่ single quote ครอบค่า — :'ชื่อตัวแปร' ใส่ให้เองแล้ว)
-- =============================================================================

-- ⚠️ ห้ามใช้ :ตัวแปร ข้างใน DO $$ ... $$
--
-- psql แทนค่าตัวแปรตอน lex เท่านั้น และมันมองข้อความใน dollar quote
-- เป็น token เดียว จึงไม่แทนค่าให้ ผลคือ syntax error at or near ":"
-- (บั๊กนี้ทำให้ bootstrap ทั้งชุดรันบนคลัสเตอร์ใหม่ไม่ได้ เจอ 2026-08-23)
--
-- วิธีที่ถูกคือสร้างคำสั่งด้วย SELECT format(...) ที่อยู่นอก dollar quote
-- แล้วให้ \gexec เอาไปรัน

SELECT format('CREATE ROLE pet_migrator LOGIN PASSWORD %L', :'migrator_pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pet_migrator')
\gexec

SELECT format('CREATE ROLE pet_app LOGIN PASSWORD %L', :'app_pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pet_app')
\gexec

-- ⚠️ GRANT ALL ไม่พอสำหรับ Flyway
--
-- ALTER TABLE ต้องการ "ownership" ไม่ใช่แค่ privilege
-- ถ้าตารางเป็นของ role อื่นอยู่ migration ที่มี ALTER TABLE จะล้มด้วย
--   ERROR: must be owner of table <ชื่อตาราง>
--
-- จึงต้องโอน ownership ให้ migrator ของแต่ละ service
-- (เจอปัญหานี้จริงตอน migrate production ครั้งแรก)
--
-- 🔸 รันเฉพาะ cluster ที่มีตารางอยู่แล้ว — cluster ใหม่ที่ Flyway สร้างตารางเอง
--    ตารางจะเป็นของ migrator ตั้งแต่แรกอยู่แล้ว
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['pets','pet_permissions','pet_caregivers',
                             'caregiver_permissions','litter_logs','water_logs']
    LOOP
        IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = t) THEN
            EXECUTE format('ALTER TABLE %I OWNER TO pet_migrator', t);
            RAISE NOTICE 'โอน % ให้ pet_migrator', t;
        END IF;
    END LOOP;
END $$;

-- pet_migrator: มีสิทธิ์ DDL ใช้เฉพาะ Flyway Job
-- pet_app:      DML เท่านั้น ใช้ใน runtime
--
-- 🔐 ผลที่ได้: pet_app รัน CREATE/ALTER/DROP TABLE ไม่ได้
--    → AutoMigrate กลับมาเองไม่ได้อีกตลอดกาล
--    → แม้โดน SQL injection ก็ DROP TABLE ไม่ได้
