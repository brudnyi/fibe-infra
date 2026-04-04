#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[pg_backup] %s\n' "$*" >&2
}

require_env() {
  local var_name="$1"
  if [[ -z "${!var_name:-}" ]]; then
    log "Missing required environment variable: ${var_name}"
    exit 1
  fi
}

database_name_from_url() {
  local database_url="$1"
  local database_name="${database_url##*/}"
  database_name="${database_name%%\?*}"

  if [[ -z "${database_name}" ]]; then
    log "Could not determine database name from BACKUP_DATABASE_URL"
    exit 1
  fi

  printf '%s\n' "${database_name}"
}

build_s3_key() {
  local file_name="$1"
  local prefix="${S3_PREFIX:-postgresql}"
  prefix="${prefix#/}"
  prefix="${prefix%/}"

  if [[ -z "${prefix}" ]]; then
    printf '%s\n' "${file_name}"
    return
  fi

  printf '%s/%s\n' "${prefix}" "${file_name}"
}

create_backup() {
  require_env "BACKUP_DATABASE_URL"

  local work_dir="${BACKUP_WORK_DIR:-$(mktemp -d)}"
  mkdir -p "${work_dir}"

  local database_name
  database_name="$(database_name_from_url "${BACKUP_DATABASE_URL}")"

  local timestamp
  timestamp="$(date -u +%Y%m%d_%H%M%S)"

  local target_path="${work_dir}/${database_name}_${timestamp}.sql.gz"

  log "Creating dump for database ${database_name}"
  pg_dump \
    --dbname="${BACKUP_DATABASE_URL}" \
    --no-owner \
    --no-privileges \
    --format=plain \
    | gzip --stdout > "${target_path}"

  gzip -t "${target_path}"
  log "Backup created at ${target_path}"
  printf '%s\n' "${target_path}"
}

upload_verified_backup() {
  local backup_path="${1:-}"
  if [[ -z "${backup_path}" ]]; then
    log "Usage: $0 upload-verified <backup_path>"
    exit 1
  fi

  if [[ ! -f "${backup_path}" ]]; then
    log "Backup file does not exist: ${backup_path}"
    exit 1
  fi

  require_env "S3_ENDPOINT_URL"
  require_env "S3_REGION"
  require_env "S3_BUCKET"
  require_env "S3_ACCESS_KEY_ID"
  require_env "S3_SECRET_ACCESS_KEY"

  local file_name
  file_name="$(basename "${backup_path}")"

  local s3_key
  s3_key="$(build_s3_key "${file_name}")"

  local s3_uri="s3://${S3_BUCKET}/${s3_key}"

  log "Uploading ${backup_path} to ${s3_uri}"
  AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID}" \
  AWS_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY}" \
  AWS_DEFAULT_REGION="${S3_REGION}" \
    aws --endpoint-url "${S3_ENDPOINT_URL}" s3 cp "${backup_path}" "${s3_uri}" --only-show-errors

  log "Verifying uploaded object ${s3_uri}"
  AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID}" \
  AWS_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY}" \
  AWS_DEFAULT_REGION="${S3_REGION}" \
    aws --endpoint-url "${S3_ENDPOINT_URL}" s3api head-object --bucket "${S3_BUCKET}" --key "${s3_key}" >/dev/null

  rm -f "${backup_path}"
  log "Upload verified and local file removed"
  printf '%s\n' "${s3_uri}"
}

usage() {
  cat >&2 <<'EOF'
Usage:
  pg_backup.sh create
  pg_backup.sh upload-verified <backup_path>
EOF
}

main() {
  local command="${1:-}"

  case "${command}" in
    create)
      shift
      create_backup "$@"
      ;;
    upload-verified)
      shift
      upload_verified_backup "$@"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
