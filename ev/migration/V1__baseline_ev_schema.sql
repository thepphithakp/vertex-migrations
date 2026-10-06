-- =============================================================================
-- V1 — baseline ของ schema ev
-- =============================================================================
-- service ใหม่ ไม่มี AutoMigrate มาก่อน เขียน schema ที่ถูกต้องได้ตั้งแต่ต้น
-- =============================================================================

CREATE TABLE IF NOT EXISTS parking_sessions (
    id               uuid PRIMARY KEY,

    -- sub จาก JWT ของ auth-service — ไม่ใช่ FK ข้าม schema โดยตั้งใจ
    user_id          text NOT NULL,

    floor            text NOT NULL DEFAULT '',
    zone             text NOT NULL DEFAULT '',
    notes            text NOT NULL DEFAULT '',
    location_type    text NOT NULL,
    is_double_parked boolean NOT NULL DEFAULT false,

    -- เวลาที่เริ่มจอด — ใช้กำหนดว่า reminder รอบไหน "อยู่ก่อนเริ่มจอด" บ้าง
    parked_at        timestamptz NOT NULL,

    -- label ของรอบที่ยิง push ไปแล้วแล้ว เช่น ["09:00","12:45"]
    -- กัน worker ยิงซ้ำ — ดู internal/worker/reminder_worker.go
    reminders_sent   jsonb NOT NULL DEFAULT '[]',

    -- ไม่ใช่ NULL แปลว่า session นี้จบแล้ว (ผู้ใช้กด Clear) — เก็บเป็นประวัติ
    -- ไม่ลบทิ้ง ต่างจาก IndexedDB ฝั่ง client ที่ clear ทับเลย
    ended_at         timestamptz,

    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);

-- มีได้แค่หนึ่ง active session (ended_at IS NULL) ต่อ user — partial unique index
CREATE UNIQUE INDEX IF NOT EXISTS ux_parking_sessions_active_user
    ON parking_sessions (user_id)
    WHERE ended_at IS NULL;

-- worker สแกนหา session ที่จอดซ้อนคันและยัง active อยู่ทุกนาที
CREATE INDEX IF NOT EXISTS ix_parking_sessions_double_parked_active
    ON parking_sessions (is_double_parked)
    WHERE ended_at IS NULL AND is_double_parked = true;
