#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/pricecompare-pro-327749/postgresql_db"
MIGRATIONS="$WORKSPACE/migrations"
SCRIPTS="$WORKSPACE/scripts"
umask 0077 && mkdir -p "$MIGRATIONS" "$SCRIPTS"
# initial migration
MIGRATION_FILE="$MIGRATIONS/0001_init.sql"
if [ ! -f "$MIGRATION_FILE" ]; then
  cat > "$MIGRATION_FILE" <<'SQL'
-- initial migration: create application schema and sample table
CREATE SCHEMA IF NOT EXISTS app_schema;
CREATE TABLE IF NOT EXISTS app_schema.example (
  id serial PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now()
);
SQL
  sudo chmod 600 "$MIGRATION_FILE" || true
fi
# healthcheck script
cat > "$SCRIPTS/healthcheck.sh" <<'BASH'
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
psql -h "$PGHOST" -p "$PGPORT" -U "${POSTGRES_USER}" -d "$POSTGRES_DB" -c "SELECT 1;" -t -A
BASH
sudo chmod 700 "$SCRIPTS/healthcheck.sh" || true
# run_migrations: run sorted migrations and abort on first failure
cat > "$SCRIPTS/run_migrations.sh" <<'BASH'
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
BASH
sudo chmod 700 "$SCRIPTS/run_migrations.sh" || true
# README
README="$WORKSPACE/README.md"
if [ ! -f "$README" ]; then
  cat > "$README" <<MD
# postgresql_db workspace
- Workspace: /home/kavia/workspace/code-generation/pricecompare-pro-327749/postgresql_db
- Migrations: migrations/*.sql (permissions 600)
- Scripts: scripts/healthcheck.sh (700) scripts/run_migrations.sh (700)
- Secrets: POSTGRES_PASSWORD and SUPABASE_KEY (if set) are stored in /root/.postgres_secrets (root:root, mode 600). They are NOT exported system-wide.
- Supabase CLI: enable by setting SUPABASE_INSTALL=true before running the env install step. npm global bin is added to PATH when CLI is installed.
- Sudo: scripts assume passwordless sudo is available for the agent (image supplies NOPASSWD). If not, run as root or adjust permissions.
- Redis: intentionally omitted for minimal DB-only dev environment.
MD
  sudo chmod 644 "$README" || true
fi
