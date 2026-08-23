# =============================================================================
# Migration image รวมของทุก service
# =============================================================================
# image เดียวบรรจุ SQL ของทุก service แล้วเลือกด้วย FLYWAY_LOCATIONS ตอนรัน
# ทำให้ deploy migration ของทุก service ด้วย image tag เดียวกันได้
#
# ⚠️ pin version ห้ามใช้ latest — Flyway major upgrade เปลี่ยนพฤติกรรม checksum ได้
FROM flyway/flyway:11-alpine

COPY pet/migration   /flyway/sql/pet/migration
COPY pet/codeowned   /flyway/sql/pet/codeowned
COPY auth/migration  /flyway/sql/auth/migration
COPY auth/codeowned  /flyway/sql/auth/codeowned
COPY event/migration /flyway/sql/event/migration
COPY event/codeowned /flyway/sql/event/codeowned

# ⚠️ เพิ่ม service ใหม่ต้องเพิ่ม COPY ที่นี่ด้วย
#    ถ้าลืม Flyway จะขึ้น "Skipping filesystem location ... (not found)"
#    แล้ว "No migrations found" — แต่ exit code ยังเป็น 0 และ Job ขึ้น Complete
#    เท่ากับ deploy สำเร็จโดยไม่ได้ทำอะไรเลย
#    FLYWAY_FAIL_ON_MISSING_LOCATIONS ใน job.yaml กันเคสนี้ไว้อีกชั้น

# 🚫 ไม่ COPY seed/ และ bootstrap/ เข้ามา
#    seed/      = ข้อมูลตัวอย่างสำหรับ local เท่านั้น ห้ามหลุดไป production
#    bootstrap/ = script ที่รันด้วยมือครั้งเดียว ไม่ใช่ migration
