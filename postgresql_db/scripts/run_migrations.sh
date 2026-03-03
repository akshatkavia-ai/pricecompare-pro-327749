#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="${WORKSPACE}"
: "${POSTGRES_DB:=devdb}"
# Source secrets for PGPASSWORD
if [ -f /root/.postgres_secrets ]; then source /root/.postgres_secrets; fi
pg_isready -h localhost -p 5432 >/dev/null || { echo "postgres not ready" >&2; exit 2; }
shopt -s nullglob
for f in "${WORKSPACE}"/migrations/*.sql; do
  [ -f "$f" ] || continue
  sudo -u postgres psql -v ON_ERROR_STOP=1 -d "${POSTGRES_DB}" -f "$f" || { echo "migration failed: $f" >&2; exit 3; }
done
