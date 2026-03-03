#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/pricecompare-pro-327749/postgresql_db"
: "${POSTGRES_APP_USER:=devuser}"
: "${POSTGRES_PASSWORD:=devpass}"
: "${POSTGRES_DB:=devdb}"
: "${PGHOST:=localhost}"
: "${PGPORT:=5432}"
# load secrets if present (root-only file, not exported globally)
if [ -f /root/.postgres_secrets ]; then source /root/.postgres_secrets; fi
# wait for postgres readiness
if ! command -v pg_isready >/dev/null 2>&1; then
  echo '{"status":"fail","reason":"pg_isready missing"}'
  exit 10
fi
if ! pg_isready -h "$PGHOST" -p "$PGPORT" >/dev/null 2>&1; then
  echo '{"status":"fail","reason":"postgres not ready"}'
  exit 2
fi
export PGPASSWORD="${POSTGRES_PASSWORD}"
# run healthcheck as app user
if ! psql -h "$PGHOST" -p "$PGPORT" -U "$POSTGRES_APP_USER" -d "$POSTGRES_DB" -c "SELECT 1;" -t -A 2>/dev/null | grep -q '^1$'; then
  echo '{"status":"fail","reason":"healthcheck failed"}' >&2
  exit 3
fi
# verify schema visibility
if ! psql -h "$PGHOST" -p "$PGPORT" -U "$POSTGRES_APP_USER" -d "$POSTGRES_DB" -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name='app_schema';" -t -A 2>/dev/null | grep -q '^app_schema$'; then
  echo '{"status":"fail","reason":"app_schema not visible"}' >&2
  exit 4
fi
# collect client tool versions (psql and pg_dump)
PSQL_V="unknown"
PG_DUMP_V="unknown"
if command -v psql >/dev/null 2>&1; then PSQL_V=$(psql --version 2>/dev/null | tr -s ' ' ' ' | sed 's/\"/\\\"/g'); fi
if command -v pg_dump >/dev/null 2>&1; then PG_DUMP_V=$(pg_dump --version 2>/dev/null | tr -s ' ' ' ' | sed 's/\"/\\\"/g'); fi
# final machine-friendly JSON
echo "{\"status\":\"ok\",\"psql_version\":\"${PSQL_V}\",\"pg_dump_version\":\"${PG_DUMP_V}\"}"
