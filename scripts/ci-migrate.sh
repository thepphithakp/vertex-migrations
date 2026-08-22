#!/usr/bin/env bash
# รัน flyway ของ service ที่ระบุ — ใช้ทั้งใน CI และตอนทำงานจริง
#
#   ./scripts/ci-migrate.sh pet            → migrate
#   ./scripts/ci-migrate.sh auth validate  → validate
set -euo pipefail

SERVICE="${1:?ต้องระบุ service: pet หรือ auth}"
CMD="${2:-migrate}"

case "$SERVICE" in
  pet)  SCHEMA=pet;    TABLE=flyway_schema_history ;;
  auth) SCHEMA=public; TABLE=flyway_schema_history_auth ;;
  *)    echo "ไม่รู้จัก service: $SERVICE"; exit 1 ;;
esac

DB_URL="${FLYWAY_URL:-jdbc:postgresql://localhost:5432/vertex_pet}"
DB_USER="${FLYWAY_USER:-vertex}"
DB_PASS="${FLYWAY_PASSWORD:-vertex}"

docker run --rm --network host \
  -v "$PWD/$SERVICE/migration:/flyway/sql/migration:ro" \
  -v "$PWD/$SERVICE/codeowned:/flyway/sql/codeowned:ro" \
  -e FLYWAY_URL="$DB_URL" \
  -e FLYWAY_USER="$DB_USER" \
  -e FLYWAY_PASSWORD="$DB_PASS" \
  -e FLYWAY_SCHEMAS="$SCHEMA" \
  -e FLYWAY_DEFAULT_SCHEMA="$SCHEMA" \
  -e FLYWAY_TABLE="$TABLE" \
  -e FLYWAY_LOCATIONS=filesystem:/flyway/sql/migration,filesystem:/flyway/sql/codeowned \
  -e FLYWAY_BASELINE_ON_MIGRATE="${FLYWAY_BASELINE_ON_MIGRATE:-true}" \
  -e FLYWAY_BASELINE_VERSION=1 \
  -e FLYWAY_CLEAN_DISABLED=true \
  -e FLYWAY_CONNECT_RETRIES=20 \
  flyway/flyway:11-alpine "$CMD"
