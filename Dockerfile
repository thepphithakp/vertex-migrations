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

# 🚫 ไม่ COPY seed/ และ bootstrap/ เข้ามา
#    seed/      = ข้อมูลตัวอย่างสำหรับ local เท่านั้น ห้ามหลุดไป production
#    bootstrap/ = script ที่รันด้วยมือครั้งเดียว ไม่ใช่ migration
