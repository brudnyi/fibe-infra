#!/usr/bin/env bash
set -euo pipefail

INFRA_DIR="${INFRA_DIR:-/opt/fibe}"
API_HEALTHCHECK_URL="${API_HEALTHCHECK_URL:-https://api.fibe.pro/health}"
ADMIN_HEALTHCHECK_URL="${ADMIN_HEALTHCHECK_URL:-https://admin.fibe.pro/}"

cd "${INFRA_DIR}"

if [[ -n "${GHCR_TOKEN:-}" && -n "${GHCR_USERNAME:-}" ]]; then
  echo "${GHCR_TOKEN}" | docker login ghcr.io -u "${GHCR_USERNAME}" --password-stdin
fi

PREV_BACKEND_IMAGE=$(grep '^BACKEND_IMAGE=' .env | cut -d '=' -f2-)
PREV_ADMIN_IMAGE=$(grep '^ADMIN_IMAGE=' .env | cut -d '=' -f2-)

if [[ -n "${BACKEND_IMAGE:-}" ]]; then
  sed -i "s|^BACKEND_IMAGE=.*|BACKEND_IMAGE=${BACKEND_IMAGE}|" .env
fi
if [[ -n "${ADMIN_IMAGE:-}" ]]; then
  sed -i "s|^ADMIN_IMAGE=.*|ADMIN_IMAGE=${ADMIN_IMAGE}|" .env
fi

docker compose pull backend admin caddy

if ! docker compose run --rm backend npm run migration:up; then
  sed -i "s|^BACKEND_IMAGE=.*|BACKEND_IMAGE=${PREV_BACKEND_IMAGE}|" .env
  docker compose up -d backend
  exit 1
fi

docker compose up -d

if ! curl -fsS --max-time 10 "${API_HEALTHCHECK_URL}" >/dev/null; then
  sed -i "s|^BACKEND_IMAGE=.*|BACKEND_IMAGE=${PREV_BACKEND_IMAGE}|" .env
  docker compose up -d backend
  exit 1
fi

if ! curl -fsS --max-time 10 "${ADMIN_HEALTHCHECK_URL}" >/dev/null; then
  sed -i "s|^ADMIN_IMAGE=.*|ADMIN_IMAGE=${PREV_ADMIN_IMAGE}|" .env
  docker compose up -d admin
  exit 1
fi

echo "Deploy completed"
