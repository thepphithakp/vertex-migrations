-- =============================================================================
-- V1 — baseline ของ schema notification
-- =============================================================================
-- service ใหม่ ไม่มี AutoMigrate มาก่อนเหมือน pet/event จึงเขียน schema ที่ถูกต้อง
-- ตั้งแต่ต้นได้เลย ไม่ต้องมี V2 แยกมา "แก้ของเดิม" แบบที่ event-service เจอ
-- =============================================================================

CREATE TABLE IF NOT EXISTS push_subscriptions (
    id             uuid PRIMARY KEY,

    -- sub จาก JWT ของ auth-service — ไม่ใช่ FK ข้าม schema โดยตั้งใจ
    -- (notification_app มองไม่เห็นตารางของ auth เลย ตามโมเดลสิทธิ์ของระบบนี้)
    user_id        text NOT NULL,

    -- endpoint มาจาก browser's push service เอง การันตีไม่ซ้ำกันข้ามอุปกรณ์อยู่แล้ว
    endpoint       text NOT NULL,

    -- คีย์เข้ารหัสตาม RFC 8291 ที่ browser สร้างไว้ตอน subscribe
    p256dh         text NOT NULL,
    auth           text NOT NULL,

    user_agent     text,

    created_at     timestamptz NOT NULL DEFAULT now(),
    last_seen_at   timestamptz NOT NULL DEFAULT now()
);

-- ผู้ใช้คนเดียว subscribe ซ้ำจากอุปกรณ์เดิม (เช่น service worker ถูกปลุกใหม่)
-- ต้องอัปเดตคีย์ล่าสุด ไม่ใช่สร้างแถวซ้ำ — ดู ON CONFLICT ใน push_repo.go
CREATE UNIQUE INDEX IF NOT EXISTS ux_push_subscriptions_user_endpoint
    ON push_subscriptions (user_id, endpoint);

-- query ที่ใช้จริงตอนส่ง push: หา subscription ทั้งหมดของ user คนหนึ่ง
CREATE INDEX IF NOT EXISTS ix_push_subscriptions_user
    ON push_subscriptions (user_id);
