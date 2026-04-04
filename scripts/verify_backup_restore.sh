#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[verify_backup_restore] %s\n' "$*" >&2
}

backup_path="${1:-}"
if [[ -z "${backup_path}" ]]; then
  log "Usage: $0 <backup_path>"
  exit 1
fi

if [[ ! -f "${backup_path}" ]]; then
  log "Backup file does not exist: ${backup_path}"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  log "docker is required"
  exit 1
fi

if ! command -v gunzip >/dev/null 2>&1; then
  log "gunzip is required"
  exit 1
fi

container_name="fibe-backup-verify-$(date +%s)-$$"
postgres_password="postgres"
verify_database="restore_verification"
verify_postgres_image="${VERIFY_POSTGRES_IMAGE:-postgres:17-alpine}"
work_dir="$(mktemp -d)"
restore_sql_path="${work_dir}/restore.sql"

cleanup() {
  docker rm -f "${container_name}" >/dev/null 2>&1 || true
  rm -rf "${work_dir}"
}

trap cleanup EXIT

gzip -t "${backup_path}"
gunzip -c "${backup_path}" > "${restore_sql_path}"

log "Starting disposable PostgreSQL container ${container_name}"
docker run -d \
  --rm \
  --name "${container_name}" \
  -e POSTGRES_PASSWORD="${postgres_password}" \
  -e POSTGRES_DB="${verify_database}" \
  "${verify_postgres_image}" >/dev/null

log "Waiting for PostgreSQL to become ready"
for _ in $(seq 1 30); do
  if docker exec "${container_name}" pg_isready -U postgres -d "${verify_database}" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! docker exec "${container_name}" pg_isready -U postgres -d "${verify_database}" >/dev/null 2>&1; then
  log "Disposable PostgreSQL container did not become ready in time"
  exit 1
fi

log "Restoring backup into disposable PostgreSQL"
docker cp "${restore_sql_path}" "${container_name}:/tmp/restore.sql"
docker exec "${container_name}" psql -v ON_ERROR_STOP=1 -U postgres -d "${verify_database}" -f /tmp/restore.sql >/dev/null

local_table_count="$(
  docker exec -i "${container_name}" psql -At -U postgres -d "${verify_database}" <<'SQL'
SELECT COUNT(*)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema');
SQL
)"

if [[ "${local_table_count}" =~ ^[0-9]+$ ]] && (( local_table_count > 0 )); then
  log "Restore verification passed with ${local_table_count} user tables"
  exit 0
fi

log "Restore verification failed: no user tables found after restore"
exit 1
