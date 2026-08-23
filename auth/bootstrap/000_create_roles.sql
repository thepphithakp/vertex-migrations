-- =============================================================================
-- Bootstrap — DB role ของ auth-service (รันครั้งเดียว ด้วย superuser)
-- =============================================================================
-- ไฟล์ใน bootstrap/ ไม่อยู่ใน image และไม่ได้รันโดย Job
-- เป็น runbook script ที่รันด้วยมือตอนตั้งระบบ
--
--   psql "$SUPERUSER_DSN" -v migrator_pw=... -f 000_create_roles.sql
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

SELECT format('CREATE ROLE auth_migrator LOGIN PASSWORD %L', :'migrator_pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'auth_migrator')
\gexec

GRANT CONNECT ON DATABASE vertex TO auth_migrator;
GRANT USAGE, CREATE ON SCHEMA public TO auth_migrator;

-- ⚠️ GRANT ALL ไม่พอ — ALTER TABLE ต้องการ ownership ไม่ใช่แค่ privilege
--    ถ้าไม่โอน migration V2 จะล้มด้วย "must be owner of table users"
--    (เจอปัญหานี้จริงตอน migrate production ครั้งแรก)
--
-- 🔸 รันเฉพาะ cluster ที่มีตารางอยู่แล้ว
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['users','o_auth_identities']
    LOOP
        IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = t) THEN
            EXECUTE format('ALTER TABLE %I OWNER TO auth_migrator', t);
            RAISE NOTICE 'โอน % ให้ auth_migrator', t;
        END IF;
    END LOOP;
END $$;
