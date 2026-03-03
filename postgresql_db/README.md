# postgresql_db workspace
- Workspace: /home/kavia/workspace/code-generation/pricecompare-pro-327749/postgresql_db
- Migrations: migrations/*.sql (permissions 600)
- Scripts: scripts/healthcheck.sh (700) scripts/run_migrations.sh (700)
- Secrets: POSTGRES_PASSWORD and SUPABASE_KEY (if set) are stored in /root/.postgres_secrets (root:root, mode 600). They are NOT exported system-wide.
- Supabase CLI: enable by setting SUPABASE_INSTALL=true before running the env install step. npm global bin is added to PATH when CLI is installed.
- Sudo: scripts assume passwordless sudo is available for the agent (image supplies NOPASSWD). If not, run as root or adjust permissions.
- Redis: intentionally omitted for minimal DB-only dev environment.
