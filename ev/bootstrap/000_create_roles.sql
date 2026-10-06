-- =============================================================================
-- Bootstrap — DB role + schema ของ ev-service (รันครั้งเดียว ด้วย superuser)
-- =============================================================================
-- service ใหม่ ไม่มีตารางเดิมใน public ให้ย้าย — รูปแบบเดียวกับ notification
--
--   psql "$SUPERUSER_DSN" -v migrator_pw=... -v app_pw=... \
--        -f ev/bootstrap/000_create_roles.sql
-- =============================================================================

SELECT format('CREATE ROLE ev_migrator LOGIN PASSWORD %L', :'migrator_pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ev_migrator')
\gexec

SELECT format('CREATE ROLE ev_app LOGIN PASSWORD %L', :'app_pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ev_app')
\gexec

GRANT CONNECT ON DATABASE vertex TO ev_migrator, ev_app;

CREATE SCHEMA IF NOT EXISTS ev AUTHORIZATION ev_migrator;

GRANT USAGE ON SCHEMA ev TO ev_app;

ALTER DEFAULT PRIVILEGES FOR ROLE ev_migrator IN SCHEMA ev
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ev_app;
ALTER DEFAULT PRIVILEGES FOR ROLE ev_migrator IN SCHEMA ev
    GRANT USAGE, SELECT ON SEQUENCES TO ev_app;
