-- =============================================================================
-- Bootstrap — DB role + schema ของ chat-service (รันครั้งเดียว ด้วย superuser)
-- =============================================================================
-- รูปแบบเดียวกับ notification/ev — service ใหม่ ไม่มีตารางเดิมใน public ให้ย้าย
--
--   psql "$SUPERUSER_DSN" -v migrator_pw=... -v app_pw=... \
--        -f chat/bootstrap/000_create_roles.sql
-- =============================================================================

SELECT format('CREATE ROLE chat_migrator LOGIN PASSWORD %L', :'migrator_pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'chat_migrator')
\gexec

SELECT format('CREATE ROLE chat_app LOGIN PASSWORD %L', :'app_pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'chat_app')
\gexec

GRANT CONNECT ON DATABASE vertex TO chat_migrator, chat_app;

CREATE SCHEMA IF NOT EXISTS chat AUTHORIZATION chat_migrator;

GRANT USAGE ON SCHEMA chat TO chat_app;

ALTER DEFAULT PRIVILEGES FOR ROLE chat_migrator IN SCHEMA chat
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO chat_app;
ALTER DEFAULT PRIVILEGES FOR ROLE chat_migrator IN SCHEMA chat
    GRANT USAGE, SELECT ON SEQUENCES TO chat_app;
