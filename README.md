# fibe-infra

Infrastructure repository for portable deployment of Fibe services to any single VM.

## Security docs

- Runtime infra audit from 2026-03-28: `infra/docs/fibe-infra-security-audit-2026-03-28.md`
- Infra threat model: `infra/docs/infra-threat-model.md`

## What this repo owns

- Runtime stack (`docker-compose.yml`) for:
  - `backend`
  - `admin`
  - `website`
  - `organizer-cabinet`
  - `caddy` (TLS + reverse proxy)
- Caddy routing for `fibe.pro`, `admin.fibe.pro`, `cabinet.fibe.pro`, and `api.fibe.pro`
- PostgreSQL setup scripts (system service + PostGIS)
- GitHub Actions backup pipeline for PostgreSQL -> S3 with restore verification on every run
- One-click deploy workflow for VM (`.github/workflows/deploy.yml`)

## First-time server bootstrap

### DNS before bootstrap

Create A records:

- `fibe.pro` -> `<YOUR_VM_PUBLIC_IP>`
- `admin.fibe.pro` -> `<YOUR_VM_PUBLIC_IP>`
- `cabinet.fibe.pro` -> `<YOUR_VM_PUBLIC_IP>`
- `api.fibe.pro` -> `<YOUR_VM_PUBLIC_IP>`

1. Copy this repo to VM as `/opt/fibe`.
2. Run bootstrap:

```bash
sudo /opt/fibe/scripts/bootstrap_vm.sh
```

3. Configure env:

```bash
cp /opt/fibe/.env.example /opt/fibe/.env
# edit /opt/fibe/.env and set real secrets (domains are already set for fibe.pro)
```

4. Configure PostgreSQL:

```bash
sudo DB_NAME=fibe_db DB_USER=fibe_user DB_PASSWORD='<strong_password>' /opt/fibe/scripts/setup_postgres.sh
```

5. Initial deploy:

```bash
cd /opt/fibe
./scripts/deploy.sh
```

## Continuous deploy model

- `fibe-backend`, `fibe-admin`, `fibe-website`, and `organizer-cabinet` publish Docker images to GHCR.
- App repositories SSH into the VM and recreate only their own services via `docker compose`.
- `fibe-infra` only syncs `/opt/fibe` on the VM, so service deploys always use the latest compose and Caddy configuration from the infra repo.
- To move to a new server: clone `fibe-infra`, copy `.env`, run bootstrap/postgres/deploy scripts.

## Required GitHub Secrets (in `fibe-infra`)

- `VM_HOST`
- `VM_USER`
- `VM_PORT`
- `VM_SSH_KEY`

## PostgreSQL backup pipeline

- Workflow: `.github/workflows/backup.yml`
- Schedule: daily at `00:00 UTC`
- Trigger: scheduled run plus manual `workflow_dispatch`
- Source DB: direct PostgreSQL connection via `BACKUP_DATABASE_URL`
- Output: gzip-compressed plain SQL dump uploaded to S3
- Upload gate: every dump must restore successfully into a disposable PostgreSQL container before upload
- Retention/immutability: managed by S3 bucket-side `Object Lock`; the workflow does not implement local retention or deletion windows

### Required GitHub Secrets for backups

- `BACKUP_DATABASE_URL`
- `S3_ENDPOINT_URL`
- `S3_REGION`
- `S3_BUCKET`
- `S3_ACCESS_KEY_ID`
- `S3_SECRET_ACCESS_KEY`
- Optional: `S3_PREFIX` (defaults to `postgresql`)

Example `BACKUP_DATABASE_URL`:

```text
postgresql://postgres:<password>@db.gbihbkwogmgnkyuszhki.supabase.co:5432/postgres
```

### Backup flow

1. `scripts/pg_backup.sh create` runs `pg_dump` against `BACKUP_DATABASE_URL`, produces a timestamped `.sql.gz` artifact, and validates gzip integrity.
2. `scripts/verify_backup_restore.sh` starts a disposable PostgreSQL container and restores the dump with `gunzip | psql`.
3. The restore check requires at least one non-system table after restore.
4. Only after restore verification passes, `scripts/pg_backup.sh upload-verified` uploads the artifact to S3, verifies object presence with `head-object`, and removes the local temp file.

### Object naming

- Default prefix: `postgresql/`
- File name: `<database_name>_YYYYMMDD_HHMMSS.sql.gz`
- Resulting object key example: `postgresql/postgres_20260404_000000.sql.gz`

### Manual run

Use GitHub Actions `workflow_dispatch` to trigger an on-demand backup with the same validation path as the scheduled job.

## Required GitHub Secrets and Variables (in app repos that deploy over SSH)

- Secrets: `DEPLOY_HOST`, `DEPLOY_SSH_KEY`, `GHCR_READ_TOKEN`, `GHCR_USERNAME`
- Variables or secrets: `DEPLOY_PORT`, `DEPLOY_USER`
- Variables: `DEPLOY_PATH` (example: `/opt/fibe`)
- Optional secrets: `DEPLOY_SSH_PASSPHRASE`, `WEBSITE_HEALTHCHECK_URL`, `API_HEALTHCHECK_URL`, `ADMIN_HEALTHCHECK_URL`
