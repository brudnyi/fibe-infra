#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-fibe_db}"
DB_USER="${DB_USER:-fibe_user}"
DB_PASSWORD="${DB_PASSWORD:-change_me}"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

sudo -u postgres psql <<SQL
DO
\$do\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
      CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASSWORD}';
   END IF;
END
\$do\$;
SQL

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"
fi

sudo -u postgres psql -d "${DB_NAME}" -c "CREATE EXTENSION IF NOT EXISTS postgis;"

PG_VERSION=$(sudo -u postgres psql -tAc "SHOW server_version_num" | cut -c1-2)
PG_CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"

if [[ -f "${PG_CONF}" ]]; then
  if ! grep -q "# fibe infra hardening" "${PG_CONF}"; then
    cat <<CONF >> "${PG_CONF}"

# fibe infra hardening
listen_addresses = '127.0.0.1,::1'
password_encryption = scram-sha-256
CONF
  fi
fi

systemctl restart postgresql

echo "PostgreSQL setup completed for ${DB_NAME}"
