-- =============================================================================
-- V2 — ตาราง notification_logs สำหรับ in-app notification feed
-- =============================================================================
-- แยกจาก push_subscriptions โดยสิ้นเชิง — ตารางนี้คือ "ประวัติสิ่งที่เคยแจ้ง"
-- ใช้แสดงเป็นหน้ากระดิ่งแจ้งเตือนในแอป (แบบ Facebook) บันทึกทุกครั้งที่มีการ
-- เรียก POST /api/v1/internal/push/send ไม่ว่า user จะมี push subscription
-- อยู่หรือไม่ก็ตาม
-- =============================================================================

CREATE TABLE IF NOT EXISTS notification_logs (
    id         uuid PRIMARY KEY,
    user_id    text NOT NULL,
    title      text NOT NULL,
    body       text NOT NULL,
    url        text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),

    -- NULL แปลว่ายังไม่ได้อ่าน — ใช้คำนวณ unread badge
    read_at    timestamptz
);

-- หน้า feed: where user_id=? order by created_at desc limit n
CREATE INDEX IF NOT EXISTS ix_notification_logs_user_created
    ON notification_logs (user_id, created_at DESC);

-- unread badge: where user_id=? and read_at is null
CREATE INDEX IF NOT EXISTS ix_notification_logs_unread
    ON notification_logs (user_id)
    WHERE read_at IS NULL;
