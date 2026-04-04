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

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    log "Required command is missing: ${command_name}"
    exit 1
  fi
}

create_backup() {
  require_env "BACKUP_DATABASE_URL"
  require_command "docker"

  local work_dir="${BACKUP_WORK_DIR:-$(mktemp -d)}"
  mkdir -p "${work_dir}"

  local database_name
  database_name="$(database_name_from_url "${BACKUP_DATABASE_URL}")"

  local timestamp
  timestamp="$(date -u +%Y%m%d_%H%M%S)"

  local target_path="${work_dir}/${database_name}_${timestamp}.sql.gz"
  local target_name
  target_name="$(basename "${target_path}")"
  local pg_client_image="${PG_CLIENT_IMAGE:-postgres:16-alpine}"

  log "Creating dump for database ${database_name} with ${pg_client_image}"
  docker run --rm \
    -e BACKUP_DATABASE_URL="${BACKUP_DATABASE_URL}" \
    -e TARGET_NAME="${target_name}" \
    -v "${work_dir}:/backup" \
    "${pg_client_image}" \
    sh -ceu '
      pg_dump \
        --dbname="${BACKUP_DATABASE_URL}" \
        --no-owner \
        --no-privileges \
        --format=plain \
        | gzip --stdout > "/backup/${TARGET_NAME}"
    '

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
  require_command "docker"

  local file_name
  file_name="$(basename "${backup_path}")"
  local backup_dir
  backup_dir="$(cd "$(dirname "${backup_path}")" && pwd)"

  local s3_key
  s3_key="$(build_s3_key "${file_name}")"

  local s3_uri="s3://${S3_BUCKET}/${s3_key}"
  local aws_cli_image="${AWS_CLI_IMAGE:-amazon/aws-cli:2.31.18}"

  log "Uploading ${backup_path} to ${s3_uri} with ${aws_cli_image}"
  docker run --rm \
    -e AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID}" \
    -e AWS_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY}" \
    -e AWS_DEFAULT_REGION="${S3_REGION}" \
    -v "${backup_dir}:/backup" \
    "${aws_cli_image}" \
    s3 cp "/backup/${file_name}" "${s3_uri}" --endpoint-url "${S3_ENDPOINT_URL}" --only-show-errors

  log "Verifying uploaded object ${s3_uri}"
  docker run --rm \
    -e AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID}" \
    -e AWS_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY}" \
    -e AWS_DEFAULT_REGION="${S3_REGION}" \
    "${aws_cli_image}" \
    s3api head-object --bucket "${S3_BUCKET}" --key "${s3_key}" --endpoint-url "${S3_ENDPOINT_URL}" >/dev/null

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
