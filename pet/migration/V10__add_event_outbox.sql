-- =============================================================================
-- V10 — transactional outbox สำหรับการส่ง event
-- =============================================================================
-- ปัญหาเดิม: service เขียนข้อมูลธุรกิจลง database แล้วค่อยยิง HTTP ไป
-- event-service แบบ fire-and-forget สองอย่างนี้ไม่ได้อยู่ในหน่วยเดียวกัน
-- ถ้า pod ถูกฆ่าหลัง commit แต่ก่อนยิงสำเร็จ event นั้นหายถาวร
-- และไม่มีใครรู้ว่าหายไปกี่ตัว
--
-- outbox แก้ด้วยการเขียน event ลงตารางนี้ "ใน transaction เดียวกับข้อมูลธุรกิจ"
-- ถ้า transaction สำเร็จ event ต้องอยู่ครบเสมอ แล้วมี worker มาส่งทีหลัง
-- ถ้า transaction ล้ม ทั้งข้อมูลและ event หายไปพร้อมกัน ไม่มีทางเหลื่อมกัน
-- =============================================================================

CREATE TABLE IF NOT EXISTS event_outbox (
    id             uuid PRIMARY KEY,

    -- ข้อมูลของ event ตามรูปแบบที่ event-service รับ
    event_type     text        NOT NULL,
    action         text        NOT NULL,
    actor_id       text,
    actor_username text,
    entity_id      text,
    entity_type    text,
    payload        jsonb,

    -- idempotency_key ส่งไปให้ event-service กันบันทึกซ้ำตอน retry
    -- ใช้ id ของแถวนี้เป็นค่า จึงคงที่ตลอดไม่ว่าจะส่งกี่รอบ
    idempotency_key text       NOT NULL,

    created_at     timestamptz NOT NULL DEFAULT now(),

    -- published_at เป็น NULL = ยังไม่ได้ส่ง
    -- ใช้เป็นเงื่อนไขหลักของ worker และของ index ด้านล่าง
    published_at   timestamptz,

    attempts       integer     NOT NULL DEFAULT 0,
    last_error     text,

    -- next_attempt_at ทำ exponential backoff โดยไม่ต้องมี scheduler แยก
    -- worker หยิบเฉพาะแถวที่ถึงเวลาแล้ว
    next_attempt_at timestamptz NOT NULL DEFAULT now()
);

-- index บางส่วน — ครอบเฉพาะแถวที่ยังไม่ได้ส่ง
--
-- แถวที่ส่งแล้วจะสะสมไปเรื่อยๆ จนเป็นส่วนใหญ่ของตาราง
-- ถ้า index ทั้งตารางจะใหญ่ขึ้นตลอดโดยไม่ได้ใช้ประโยชน์
-- แบบนี้ index มีขนาดเท่ากับ "งานที่ค้างอยู่" เท่านั้น
CREATE INDEX IF NOT EXISTS ix_event_outbox_pending
    ON event_outbox (next_attempt_at, created_at)
    WHERE published_at IS NULL;

-- ใช้ตอนล้างแถวเก่าที่ส่งไปแล้ว
CREATE INDEX IF NOT EXISTS ix_event_outbox_published_at
    ON event_outbox (published_at)
    WHERE published_at IS NOT NULL;

COMMENT ON TABLE event_outbox IS
    'event ที่รอส่งไป event-service — เขียนใน transaction เดียวกับข้อมูลธุรกิจ';
