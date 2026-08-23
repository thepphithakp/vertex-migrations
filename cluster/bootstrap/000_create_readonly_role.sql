-- =============================================================================
-- Bootstrap — vertex_readonly: อ่านได้ทุก schema เขียนไม่ได้
-- =============================================================================
-- ไฟล์ในโฟลเดอร์ bootstrap/ ไม่อยู่ใน FLYWAY_LOCATIONS — เป็น runbook script
-- ที่รันด้วยมือครั้งเดียวตอนตั้งระบบ ไม่ใช่ migration
--
-- ใช้กับ DBeaver / psql ตอนสำรวจข้อมูล จึงต้องอ่านข้าม schema ได้
-- (pet, auth, public) แต่ต้องเขียนอะไรไม่ได้เลย
--
-- อยู่ที่ cluster/ ไม่ใช่ pet/ หรือ auth/ เพราะเป็น role ระดับฐานข้อมูล
-- ไม่ได้เป็นของ service ไหน
--
-- วิธีรัน:
--   psql "$SUPERUSER_DSN" -v readonly_pw=... -f 000_create_readonly_role.sql
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

SELECT format('CREATE ROLE vertex_readonly LOGIN PASSWORD %L', :'readonly_pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'vertex_readonly')
\gexec

-- pg_read_all_data (PostgreSQL 14+) ให้ SELECT ทุกตารางและ USAGE ทุก schema
-- รวมถึง schema ที่สร้างขึ้นในอนาคตด้วย จึงไม่ต้องมาไล่ GRANT ใหม่ทุกครั้ง
-- ที่เพิ่ม service
GRANT pg_read_all_data TO vertex_readonly;

-- ⚠️ ต้องใส่ทุก schema ที่มี ไม่งั้นเปิด DBeaver แล้วมองไม่เห็นตารางแบบ
--    ไม่ระบุ schema — เคยพลาดมาแล้วตอนย้าย auth ออกจาก public (Phase 9)
--    เพิ่ม schema ใหม่เมื่อไหร่ ต้องกลับมาแก้บรรทัดนี้ด้วย
ALTER ROLE vertex_readonly SET search_path = pet, auth, public;

-- กันเขียนซ้ำอีกชั้น เผื่อมี GRANT อื่นหลุดเข้ามาภายหลัง
REVOKE CREATE ON SCHEMA public FROM vertex_readonly;

-- ตรวจผล
--   \du vertex_readonly
--   select rolconfig from pg_roles where rolname = 'vertex_readonly';
