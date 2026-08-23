#!/usr/bin/env bash
# =============================================================================
# พิสูจน์ว่า database เปล่าที่รัน migration ทั้งหมด ได้ schema เหมือน production
# =============================================================================
# ความเสี่ยงที่กัน:
#
#   cluster ใหม่  → Flyway รัน V1..Vn ทั้งหมดตั้งแต่ต้น
#   production    → baseline ที่ V1 (ข้ามไป) แล้วรัน V2..Vn เท่านั้น
#
# ถ้ามีคนแก้ V1 หลังจากมันถูก baseline ไปแล้ว หรือเขียน migration ที่
# ทำงานได้เฉพาะบน database ที่มีข้อมูลอยู่ สองเส้นทางจะจบที่ schema คนละแบบ
# แล้วบั๊กจะโผล่เฉพาะ environment เดียวโดยหาสาเหตุยากมาก
#
# pet/schema.golden.txt คือ snapshot ที่ดึงมาจาก production จริง
#
# วิธีรัน:
#   PGPORT=55432 ./scripts/verify-schema.sh
#
# อัปเดต snapshot เมื่อเพิ่ม migration ใหม่ (ต้องดู diff ก่อน commit เสมอ):
#   PGPORT=55432 ./scripts/verify-schema.sh --update
# =============================================================================
set -euo pipefail

SERVICE="${SERVICE:-pet}"
SCHEMA="${SCHEMA:-$SERVICE}"
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-vertex}"
PGPASSWORD="${PGPASSWORD:-vertex}"
export PGPASSWORD

UPDATE=0
[ "${1:-}" = "--update" ] && UPDATE=1

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GOLDEN="$REPO_ROOT/$SERVICE/schema.golden.txt"
DB="verify_schema_$$"
WORK="$(mktemp -d)"

PG_IMAGE="postgres:15-alpine"
FLYWAY_IMAGE="flyway/flyway:11-alpine"
NET="${DOCKER_NETWORK:-host}"

psql_run() {
    local db="$1"; shift
    docker run --rm --network "$NET" -e PGPASSWORD \
        "$PG_IMAGE" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$db" "$@"
}

cleanup() {
    psql_run postgres -q -c "DROP DATABASE IF EXISTS $DB;" >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "=== สร้าง database เปล่าแล้วรัน migration ทั้งหมด ==="
psql_run postgres -q -c "DROP DATABASE IF EXISTS $DB;" -c "CREATE DATABASE $DB;"

docker run --rm --network "$NET" \
    -v "$REPO_ROOT/$SERVICE/migration:/flyway/sql/migration:ro" \
    -e FLYWAY_URL="jdbc:postgresql://$PGHOST:$PGPORT/$DB" \
    -e FLYWAY_USER="$PGUSER" -e FLYWAY_PASSWORD="$PGPASSWORD" \
    -e FLYWAY_SCHEMAS="$SCHEMA" -e FLYWAY_DEFAULT_SCHEMA="$SCHEMA" \
    -e FLYWAY_LOCATIONS=filesystem:/flyway/sql/migration \
    -e FLYWAY_FAIL_ON_MISSING_LOCATIONS=true \
    -e FLYWAY_BASELINE_ON_MIGRATE=false \
    -e FLYWAY_CLEAN_DISABLED=true \
    "$FLYWAY_IMAGE" migrate | grep -E 'Successfully|Migrating' | tail -2

docker run --rm --network "$NET" -e PGPASSWORD \
    -v "$REPO_ROOT/scripts/schema-snapshot.sh:/snap.sh:ro" \
    -e PGHOST="$PGHOST" -e PGPORT="$PGPORT" -e PGUSER="$PGUSER" \
    -e PGDATABASE="$DB" -e SCHEMA="$SCHEMA" \
    "$PG_IMAGE" sh /snap.sh | sed 's/[[:space:]]*$//' > "$WORK/fresh.txt"

if [ "$UPDATE" = "1" ]; then
    cp "$WORK/fresh.txt" "$GOLDEN"
    echo "✅ เขียน $GOLDEN ใหม่แล้ว — ตรวจ git diff ก่อน commit"
    exit 0
fi

if [ ! -f "$GOLDEN" ]; then
    echo "🔴 ไม่พบ $GOLDEN — สร้างครั้งแรกด้วย --update"
    exit 1
fi

echo
if diff -u "$GOLDEN" "$WORK/fresh.txt" > "$WORK/diff.txt"; then
    echo "✅ database เปล่าได้ schema เหมือน production ($(grep -cv '^---' "$GOLDEN") รายการ)"
    exit 0
fi

echo "🔴 schema ของ database เปล่าไม่ตรงกับ snapshot ของ production"
echo
echo "   ซ้าย  = snapshot จาก production"
echo "   ขวา   = database เปล่าที่รัน migration ทั้งหมด"
echo
echo "   ถ้าเพิ่ม migration ใหม่แล้วตั้งใจให้ schema เปลี่ยน:"
echo "     1. deploy migration ขึ้น production ก่อน"
echo "     2. รัน --update แล้วตรวจ diff"
echo
cat "$WORK/diff.txt"
exit 1
