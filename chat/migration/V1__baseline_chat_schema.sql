-- =============================================================================
-- V1 — baseline ของ schema chat
-- =============================================================================
-- service ใหม่ ไม่มี AutoMigrate มาก่อน เขียน schema ที่ถูกต้องได้ตั้งแต่ต้น
--
-- ขอบเขต v1: ข้อความ 1:1 ระหว่างคนสองคนที่มีสัตว์เลี้ยงร่วมกัน (เจ้าของ +
-- ผู้ดูแล) ไม่มีกลุ่มแชท ไม่มีการโทร — ตัดออกแล้วตอน figure-it-out Phase A
-- เพราะ ISP ของผู้ใช้ไม่มี public IP ให้ทำ TURN server เอง
-- =============================================================================

-- หนึ่งคู่ผู้ใช้มีได้แค่หนึ่งบทสนทนาเสมอ — บังคับด้วย CHECK + unique index
-- ไม่ใช่โดย application logic เพียงอย่างเดียว กัน race ตอนสองฝั่งเปิดแชทพร้อมกัน
CREATE TABLE IF NOT EXISTS conversations (
    id            uuid PRIMARY KEY,
    user_a_id     text NOT NULL,
    user_b_id     text NOT NULL,

    -- สัตว์เลี้ยงที่ทำให้สองคนนี้คุยกันได้ (เจ้าของ/ผู้ดูแลร่วมกัน) — เก็บไว้
    -- เป็นเหตุผลตอน audit ไม่ใช่ FK ข้าม schema (pet อยู่คนละ schema)
    origin_pet_id uuid NOT NULL,

    created_at    timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT ck_conversations_pair_ordered CHECK (user_a_id < user_b_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_conversations_pair
    ON conversations (user_a_id, user_b_id);

CREATE TABLE IF NOT EXISTS messages (
    id              uuid PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES conversations(id),
    sender_id       text NOT NULL,

    -- client-generated UUID — ส่งซ้ำ (เช่น ตอน reconnect แล้ว retry) ต้องได้
    -- แถวเดิมกลับมา ไม่ใช่สร้างข้อความซ้ำ
    client_msg_id   text NOT NULL,

    body            text NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT ck_messages_body_not_empty CHECK (body <> '')
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_messages_dedupe
    ON messages (conversation_id, sender_id, client_msg_id);

-- หน้าแชท: keyset pagination ใหม่สุดก่อน
CREATE INDEX IF NOT EXISTS ix_messages_keyset
    ON messages (conversation_id, created_at DESC, id DESC);

-- แต่ละฝ่ายเขียนแค่แถวของตัวเอง (conversation_id, user_id) — ไม่มีสองคนเขียน
-- แถวเดียวกัน จึงไม่มี race ให้ต้องกังวล unread badge คำนวณจากแถวของตัวเอง
-- "seen" tick บนข้อความของเราคำนวณจากแถวของอีกฝ่าย
CREATE TABLE IF NOT EXISTS conversation_reads (
    conversation_id uuid NOT NULL REFERENCES conversations(id),
    user_id         text NOT NULL,
    read_through_at timestamptz NOT NULL,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (conversation_id, user_id)
);

-- ชื่อที่โชว์ในหน้าแชท — เขียนจาก JWT ของเจ้าของแถวเองเท่านั้น (อัปเดตทุกครั้ง
-- ที่ผู้ใช้คนนั้นเรียก API ของ chat-service) จึงมีเจ้าของแถวแค่คนเดียวเสมอ
-- ไม่ต้องพึ่ง auth-service แบบ cross-service call
CREATE TABLE IF NOT EXISTS user_profiles (
    user_id      text PRIMARY KEY,
    display_name text NOT NULL,
    updated_at   timestamptz NOT NULL DEFAULT now()
);
