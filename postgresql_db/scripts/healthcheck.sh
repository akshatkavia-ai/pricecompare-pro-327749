#!/usr/bin/env bash
set -euo pipefail
: "${PGHOST:=localhost}"
: "${PGPORT:=5432}"
: "${POSTGRES_USER:=devuser}"
: "${POSTGRES_DB:=devdb}"
# Source secrets if present
if [ -f /root/.postgres_secrets ]; then source /root/.postgres_secrets; fi
pg_isready -h "$PGHOST" -p "$PGPORT" >/dev/null || { echo "not ready" >&2; exit 2; }
export PGPASSWORD="${POSTGRES_PASSWORD:-}"
psql -h "$PGHOST" -p "$PGPORT" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c "SELECT 1;" -t -A
