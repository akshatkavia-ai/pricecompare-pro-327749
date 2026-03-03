#!/usr/bin/env bash
set -euo pipefail
# Validation: backup/restore + lifecycle evidence (DB-centric)
WORKSPACE="/home/kavia/workspace/code-generation/pricecompare-pro-327749/postgresql_db"
BACKUP="$WORKSPACE/backup.dump"
: "${POSTGRES_APP_USER:=devuser}"
: "${POSTGRES_PASSWORD:=devpass}"
: "${POSTGRES_DB:=devdb}"
# Source secrets if present (root-only file per plan)
if [ -f /root/.postgres_secrets ]; then
  # shellcheck disable=SC1090
  source /root/.postgres_secrets
fi
# Ensure workspace exists
mkdir -p "$WORKSPACE"
# Pre-checks for required tools
for cmd in pg_dump pg_restore pg_isready psql; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "{\"status\":\"fail\",\"reason\":\"$cmd missing\"}" >&2; exit 2; }
done
# Ensure postgres is reachable before proceeding
if ! pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
  echo "{\"status\":\"fail\",\"reason\":\"postgres not ready\"}" >&2
  exit 3
fi
PRE_READY_TS=$(date --iso-8601=seconds 2>/dev/null || date)
# Detect best restart method
RESTART_METHOD="none"
if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
  RESTART_METHOD="systemctl"
elif command -v service >/dev/null 2>&1; then
  RESTART_METHOD="service"
elif command -v pg_ctlcluster >/dev/null 2>&1; then
  RESTART_METHOD="pg_ctlcluster"
elif command -v pg_ctl >/dev/null 2>&1; then
  RESTART_METHOD="pg_ctl"
else
  RESTART_METHOD="none"
fi
RESTARTED=false
case "$RESTART_METHOD" in
  systemctl)
    sudo systemctl restart postgresql.service >/dev/null 2>&1 && RESTARTED=true || RESTARTED=false
    ;;
  service)
    sudo service postgresql restart >/dev/null 2>&1 && RESTARTED=true || RESTARTED=false
    ;;
  pg_ctlcluster)
    # best-effort: try common cluster version(s) if present; safe failure tolerated
    if sudo which pg_ctlcluster >/dev/null 2>&1; then
      # try a generic restart; if it fails, continue without aborting
      sudo pg_ctlcluster --skip-systemctl --force 12 main restart >/dev/null 2>&1 && RESTARTED=true || true
    fi
    ;;
  pg_ctl)
    if [ -n "${PGDATA:-}" ]; then
      sudo -u postgres pg_ctl restart -D "$PGDATA" -m fast >/dev/null 2>&1 && RESTARTED=true || true
    fi
    ;;
  none)
    RESTARTED=false
    ;;
esac
# Wait up to ~30s with backoff for readiness
for s in 0 1 2 4 8 15; do
  if pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
    break
  fi
  sleep "$s"
done
POST_READY_TS=$(date --iso-8601=seconds 2>/dev/null || date)
# Backup using custom format
export PGPASSWORD="${POSTGRES_PASSWORD}"
if ! pg_dump -h localhost -U "${POSTGRES_APP_USER}" -d "${POSTGRES_DB}" -Fc -f "$BACKUP" >/dev/null 2>&1; then
  echo "{\"status\":\"fail\",\"reason\":\"pg_dump failed\"}" >&2; exit 4
fi
[ -f "$BACKUP" ] || { echo "{\"status\":\"fail\",\"reason\":\"backup file missing\"}" >&2; exit 5; }
# Check versions and warn if restore older than dump
DUMP_VER=$(pg_dump --version 2>/dev/null | awk '{print $NF}' || true)
RESTORE_VER=$(pg_restore --version 2>/dev/null | awk '{print $NF}' || true)
if [ -n "$DUMP_VER" ] && [ -n "$RESTORE_VER" ]; then
  if [ "$(printf '%s\n' "$RESTORE_VER" "$DUMP_VER" | sort -V | head -n1)" != "$RESTORE_VER" ]; then
    echo "{\"status\":\"warn\",\"reason\":\"pg_restore version may be older than pg_dump\"}" >&2 || true
  fi
fi
# Restore into temporary DB and verify schema
TMP_DB="${POSTGRES_DB}_restore_tmp"
sudo -u postgres psql -c "DROP DATABASE IF EXISTS \"$TMP_DB\";" >/dev/null 2>&1 || true
if ! sudo -u postgres psql -c "CREATE DATABASE \"$TMP_DB\";" >/dev/null 2>&1; then
  echo "{\"status\":\"fail\",\"reason\":\"create tmp db failed\"}" >&2; exit 6
fi
if ! sudo -u postgres pg_restore -d "$TMP_DB" "$BACKUP" >/dev/null 2>&1; then
  sudo -u postgres psql -c "DROP DATABASE IF EXISTS \"$TMP_DB\";" >/dev/null 2>&1 || true
  echo "{\"status\":\"fail\",\"reason\":\"pg_restore failed\"}" >&2; exit 7
fi
# Verify app_schema exists in restored DB
if ! sudo -u postgres psql -d "$TMP_DB" -t -A -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name='app_schema';" | grep -q app_schema; then
  sudo -u postgres psql -c "DROP DATABASE IF EXISTS \"$TMP_DB\";" >/dev/null 2>&1 || true
  echo "{\"status\":\"fail\",\"reason\":\"restored DB missing app_schema\"}" >&2; exit 8
fi
# Cleanup temporary DB
sudo -u postgres psql -c "DROP DATABASE IF EXISTS \"$TMP_DB\";" >/dev/null 2>&1 || true
# Final evidence JSON
BACKUP_PRESENT=$( [ -f "$BACKUP" ] && echo yes || echo no )
# print JSON single-line
echo "{\"status\":\"ok\",\"pre_ready\":\"$PRE_READY_TS\",\"post_ready\":\"$POST_READY_TS\",\"restart_method\":\"$RESTART_METHOD\",\"restart_attempted\":$RESTARTED,\"backup_present\":\"$BACKUP_PRESENT\" }"
