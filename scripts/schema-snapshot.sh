#!/usr/bin/env bash
# =============================================================================
# ดึง "โครง" ของ schema ออกมาเป็นข้อความที่เทียบกันได้
# =============================================================================
# ใช้ร่วมกันทั้งตอนสร้าง snapshot จาก production และตอนเทียบกับ database เปล่า
#
# เก็บ 4 อย่างที่ทำให้ระบบทำงานต่างกันได้จริง:
#   คอลัมน์ (ชื่อ/ชนิด/nullable/default) · index · constraint · sequence
#
# ไม่เก็บข้อมูลในตาราง และไม่เก็บ flyway_schema_history
# =============================================================================
set -euo pipefail

SCHEMA="${SCHEMA:-pet}"

run() { psql -tAq -c "$1"; }

echo "--- columns ---"
run "SELECT table_name||'|'||column_name||'|'||data_type||'|'||is_nullable||'|'||coalesce(column_default,'-')
     FROM information_schema.columns
     WHERE table_schema='$SCHEMA' AND table_name <> 'flyway_schema_history'
     ORDER BY 1;"

echo "--- indexes ---"
run "SELECT indexname||'|'||regexp_replace(indexdef, ' ON [a-z_]+\.', ' ON ')
     FROM pg_indexes
     WHERE schemaname='$SCHEMA' AND tablename <> 'flyway_schema_history'
     ORDER BY 1;"

echo "--- constraints ---"
run "SELECT c.conname||'|'||c.contype::text||'|'||pg_get_constraintdef(c.oid)
     FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace
     WHERE n.nspname='$SCHEMA'
     ORDER BY 1;"

echo "--- sequences ---"
run "SELECT sequence_name FROM information_schema.sequences
     WHERE sequence_schema='$SCHEMA' ORDER BY 1;"
