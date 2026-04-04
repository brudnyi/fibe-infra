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
verify_postgres_password="${VERIFY_POSTGRES_PASSWORD:-postgres}"
verify_postgres_user="${VERIFY_POSTGRES_USER:-supabase_admin}"
verify_database="${VERIFY_POSTGRES_DB:-restore_verification}"
verify_postgres_host="${VERIFY_POSTGRES_HOST:-127.0.0.1}"
verify_postgres_image="${VERIFY_POSTGRES_IMAGE:-supabase/postgres:17.6.1.096}"
verify_postgres_command="${VERIFY_POSTGRES_COMMAND:-postgres -D /etc/postgresql}"
verify_postgres_platform="${VERIFY_POSTGRES_PLATFORM:-}"
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
docker_run_args=(
  run
  -d
  --rm
  --name "${container_name}"
  -e POSTGRES_PASSWORD="${verify_postgres_password}"
  -e POSTGRES_DB="${verify_database}"
)

if [[ -n "${verify_postgres_platform}" ]]; then
  docker_run_args+=(--platform "${verify_postgres_platform}")
fi

docker_run_args+=("${verify_postgres_image}")

if [[ -n "${verify_postgres_command}" ]]; then
  # shellcheck disable=SC2206
  verify_command_parts=( ${verify_postgres_command} )
  docker_run_args+=("${verify_command_parts[@]}")
fi

docker "${docker_run_args[@]}" >/dev/null

log "Waiting for PostgreSQL to become ready"
for _ in $(seq 1 60); do
  if docker exec "${container_name}" sh -lc \
    "PGPASSWORD='${verify_postgres_password}' pg_isready -U '${verify_postgres_user}' -h '${verify_postgres_host}' -d '${verify_database}'" \
    >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! docker exec "${container_name}" sh -lc \
  "PGPASSWORD='${verify_postgres_password}' pg_isready -U '${verify_postgres_user}' -h '${verify_postgres_host}' -d '${verify_database}'" \
  >/dev/null 2>&1; then
  log "Disposable PostgreSQL container did not become ready in time"
  exit 1
fi

log "Restoring backup into disposable PostgreSQL"
docker cp "${restore_sql_path}" "${container_name}:/tmp/restore.sql"
docker exec "${container_name}" sh -lc \
  "PGPASSWORD='${verify_postgres_password}' psql -v ON_ERROR_STOP=1 -U '${verify_postgres_user}' -h '${verify_postgres_host}' -d '${verify_database}' -f /tmp/restore.sql" \
  >/dev/null

local_table_count="$(
  docker exec "${container_name}" sh -lc \
    "PGPASSWORD='${verify_postgres_password}' psql -At -U '${verify_postgres_user}' -h '${verify_postgres_host}' -d '${verify_database}' <<'SQL'
SELECT COUNT(*)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema');
SQL"
)"

if [[ "${local_table_count}" =~ ^[0-9]+$ ]] && (( local_table_count > 0 )); then
  log "Restore verification passed with ${local_table_count} user tables"
  exit 0
fi

log "Restore verification failed: no user tables found after restore"
exit 1
