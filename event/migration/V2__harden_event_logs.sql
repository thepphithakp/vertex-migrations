-- =============================================================================
-- V2 — ทำให้ event_logs ใช้งานจริงได้: type ถูกต้อง, index, กัน duplicate
-- =============================================================================
-- ปัญหาของ V1 (ซึ่งมาจาก AutoMigrate):
--   - id เป็น text ทั้งที่เก็บ uuid — เปลืองที่และเทียบช้ากว่า
--   - ไม่มี index เลยนอกจาก PK — หน้า timeline ต้อง seq scan ทั้งตาราง
--   - ทุกคอลัมน์ nullable — event ที่ไม่มี event_type เขียนลงได้เฉยๆ
--   - ไม่มีทางกัน duplicate จากการ retry
--   - ไม่รู้ว่าแถวถูกเขียนเมื่อไหร่ (timestamp มาจากผู้เรียก แก้ได้)
-- =============================================================================

-- ── id: text → uuid ──────────────────────────────────────────────────────────
-- ปลอดภัยเพราะทุกแถวที่มีอยู่เป็น uuid ที่ถูกต้องแล้ว (ตรวจก่อนเขียน migration นี้)
-- ถ้ามีแถวที่แปลงไม่ได้ คำสั่งนี้จะล้มทั้ง migration ไม่ใช่แปลงผิดเงียบๆ
ALTER TABLE event_logs
    ALTER COLUMN id TYPE uuid USING id::uuid;

-- ── created_at: เวลาที่ "ระบบ" บันทึก ───────────────────────────────────────
-- ต่างจาก timestamp ซึ่งเป็นเวลาที่ "ผู้เรียกบอกว่าเหตุการณ์เกิด"
-- ผู้เรียกส่งค่าอะไรมาก็ได้ จึงใช้อ้างอิงสำหรับ retention ไม่ได้
-- ต้องมีค่าที่ฝั่ง database เป็นคนใส่เท่านั้น
ALTER TABLE event_logs
    ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

-- แถวเดิมไม่มี created_at — ใช้ timestamp ที่ผู้เรียกส่งมาเป็นค่าประมาณ
-- ดีกว่าปล่อยให้ทุกแถวเก่ากลายเป็น "เพิ่งสร้างตอน migrate"
UPDATE event_logs SET created_at = timestamp WHERE timestamp IS NOT NULL;

-- ── idempotency_key: กัน duplicate จาก retry ────────────────────────────────
-- ผู้ส่งกำหนดค่าที่แทน "เหตุการณ์นี้ครั้งนี้" เช่น <entity>:<action>:<ts>
-- ส่งซ้ำด้วยคีย์เดิมจะถูกปัดตกที่ database ไม่ใช่หวังให้ฝั่งผู้ส่งไม่ retry
--
-- nullable โดยตั้งใจ — ผู้ส่งที่ยังไม่ได้อัปเดตยังส่งได้เหมือนเดิม
-- UNIQUE ของ PostgreSQL ไม่นับ NULL ว่าซ้ำกัน แถวเก่าจึงไม่ชนกันเอง
ALTER TABLE event_logs
    ADD COLUMN IF NOT EXISTS idempotency_key text;

CREATE UNIQUE INDEX IF NOT EXISTS ux_event_logs_idempotency_key
    ON event_logs (idempotency_key)
    WHERE idempotency_key IS NOT NULL;

-- ── index สำหรับ query ที่ใช้จริง ────────────────────────────────────────────
-- หน้า timeline ของ entity หนึ่งตัว: where entity_type=? and entity_id=? order by timestamp desc
CREATE INDEX IF NOT EXISTS ix_event_logs_entity
    ON event_logs (entity_type, entity_id, timestamp DESC);

-- หน้ารวมของ backoffice: order by timestamp desc limit n
CREATE INDEX IF NOT EXISTS ix_event_logs_timestamp
    ON event_logs (timestamp DESC);

-- ค้นตาม actor เวลาไล่ว่าใครทำอะไรไว้บ้าง
CREATE INDEX IF NOT EXISTS ix_event_logs_actor
    ON event_logs (actor_id, timestamp DESC);

-- ── บังคับให้ event ที่ไม่มีความหมายเขียนลงไม่ได้ ────────────────────────────
-- แถวเดิมผ่านเงื่อนไขนี้หมดแล้ว (ตรวจก่อนเขียน migration นี้)
-- ถ้ามีแถวที่ไม่ผ่าน คำสั่งนี้จะล้ม ไม่ใช่ปล่อยผ่าน
ALTER TABLE event_logs
    ALTER COLUMN timestamp  SET NOT NULL,
    ALTER COLUMN event_type SET NOT NULL,
    ALTER COLUMN action     SET NOT NULL;

ALTER TABLE event_logs
    ALTER COLUMN timestamp SET DEFAULT now();
