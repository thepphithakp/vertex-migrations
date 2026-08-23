-- =============================================================================
-- V1 — baseline ของ schema event
-- =============================================================================
-- สะท้อนหน้าตาตารางที่ AutoMigrate ของ GORM สร้างไว้ ณ ตอนเลิกใช้ AutoMigrate
-- ไม่ได้ตั้งใจให้สวย แค่ต้องตรงกับของจริงเพื่อให้ cluster เดิม baseline ได้
-- ส่วนที่ควรปรับปรุงอยู่ใน V2
--
-- cluster เดิม: ตารางถูกย้ายมาแล้วโดย bootstrap/001 → IF NOT EXISTS ข้ามไป
-- cluster ใหม่: ไฟล์นี้สร้างตารางให้
-- =============================================================================

CREATE TABLE IF NOT EXISTS event_logs (
    id             text PRIMARY KEY,
    timestamp      timestamptz,
    event_type     text,
    action         text,
    actor_id       text,
    actor_username text,
    entity_id      text,
    entity_type    text,
    payload        jsonb
);
