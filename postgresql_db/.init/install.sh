#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/pricecompare-pro-327749/postgresql_db"
: "${POSTGRES_USER:=devuser}"
: "${POSTGRES_DB:=devdb}"
: "${POSTGRES_PASSWORD:=devpass}"
: "${SUPABASE_URL:=}"
: "${SUPABASE_KEY:=}"
: "${SUPABASE_INSTALL:=false}"
: "${MIN_SUPABASE_CLI_VER:=1.70.0}"
# ensure workspace exists with restrictive perms
umask 0077 && mkdir -p "$WORKSPACE"
# verify required postgres client binaries
for b in psql pg_dump pg_restore pg_isready; do command -v "$b" >/dev/null || { echo "$b not found" >&2; exit 2; }; done
# write non-sensitive env to /etc/profile.d (idempotent)
sudo mkdir -p /etc/profile.d
sudo tee /etc/profile.d/postgres_env.sh >/dev/null <<EOF
export POSTGRES_USER="${POSTGRES_USER}"
export POSTGRES_DB="${POSTGRES_DB}"
export SUPABASE_URL="${SUPABASE_URL}"
export POSTGRES_APP_USER="${POSTGRES_USER}"
EOF
sudo chown root:root /etc/profile.d/postgres_env.sh && sudo chmod 644 /etc/profile.d/postgres_env.sh
# store secrets in root-only file (not exported globally)
if [ -n "${POSTGRES_PASSWORD}" ] || [ -n "${SUPABASE_KEY}" ]; then
  sudo tee /root/.postgres_secrets >/dev/null <<'EOF'
POSTGRES_PASSWORD='${POSTGRES_PASSWORD}'
SUPABASE_KEY='${SUPABASE_KEY}'
EOF
  sudo chown root:root /root/.postgres_secrets && sudo chmod 600 /root/.postgres_secrets
fi
# optional supabase CLI install non-interactive
if [ "${SUPABASE_INSTALL}" = "true" ]; then
  command -v npm >/dev/null || { echo "npm required for supabase install" >&2; exit 3; }
  if ! command -v supabase >/dev/null 2>&1; then
    sudo npm i -g supabase --no-audit --no-fund --silent || { echo "supabase npm install failed" >&2; exit 4; }
  fi
  # ensure npm global bin exported for future shells
  NPM_GLOB_BIN=$(npm bin -g 2>/dev/null || true)
  if [ -n "$NPM_GLOB_BIN" ]; then
    sudo tee /etc/profile.d/supabase_path.sh >/dev/null <<EOF
# Added by env-01: ensure npm global bin is on PATH for future shells
export PATH="$NPM_GLOB_BIN":\$PATH
EOF
    sudo chown root:root /etc/profile.d/supabase_path.sh && sudo chmod 644 /etc/profile.d/supabase_path.sh
  fi
  # verify supabase CLI availability
  if ! command -v supabase >/dev/null 2>&1; then echo "supabase not available after install" >&2; exit 5; fi
  SUP_VER=$(supabase --version 2>/dev/null | awk '{print $NF}' || true)
  if [ -n "$SUP_VER" ]; then
    # fail if installed version is older than minimum recommended
    if [ "$(printf '%s\n' "$MIN_SUPABASE_CLI_VER" "$SUP_VER" | sort -V | head -n1)" != "$MIN_SUPABASE_CLI_VER" ]; then
      echo "supabase CLI version $SUP_VER is older than recommended $MIN_SUPABASE_CLI_VER" >&2; exit 6
    fi
  fi
fi
# emit versions for diagnostics
psql --version || true
pg_dump --version || true
pg_restore --version || true
pg_isready --version || true
if command -v supabase >/dev/null 2>&1; then supabase --version || true; fi
