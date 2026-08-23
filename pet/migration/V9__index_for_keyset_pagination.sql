-- =============================================================================
-- V9 — ดัชนีที่ตรงกับลำดับที่ใช้จริงของ log
-- =============================================================================
-- log endpoint เรียงด้วย (date DESC, id DESC) และแบ่งหน้าแบบ keyset
-- ด้วยเงื่อนไข (date, id) < (?, ?)
--
-- ดัชนีเดิมคือ (pet_id, date DESC) ซึ่งขาด id ทำให้ PostgreSQL ต้อง
-- อ่านแถวที่ date เท่ากันทั้งหมดออกมาก่อนแล้วค่อยกรอง id ทีหลัง
-- ตอนนี้ยังไม่เห็นผลเพราะข้อมูลน้อย (water 53 / litter 23 แถว)
-- แต่จะกลายเป็นปัญหาเมื่อมี log วันเดียวกันจำนวนมาก
--
-- 🔸 ใช้ CREATE INDEX ธรรมดา ไม่ใช่ CONCURRENTLY เพราะ Flyway รันใน transaction
--    ตารางตอนนี้เล็กมาก การ lock จึงสั้นจนไม่กระทบ
--    ถ้าวันหนึ่งตารางใหญ่ขึ้นมาก ให้สร้าง index ใหม่ด้วย CONCURRENTLY นอก Flyway
--    แล้วค่อยเขียน migration ที่เป็น IF NOT EXISTS ตามหลัง
--
-- ไม่ลบดัชนีเดิม (pet_id, date DESC) ทิ้งในไฟล์นี้ — ปล่อยให้อยู่ก่อน
-- เพราะ query อื่นอาจใช้อยู่ และการลบดัชนีย้อนกลับยากกว่าการเพิ่ม
-- =============================================================================

CREATE INDEX IF NOT EXISTS ix_water_logs_pet_date_id
    ON water_logs (pet_id, date DESC, id DESC);

CREATE INDEX IF NOT EXISTS ix_litter_logs_pet_date_id
    ON litter_logs (pet_id, date DESC, id DESC);
