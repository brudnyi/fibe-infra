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
  - `caddy` (TLS + reverse proxy)
- Caddy routing for `fibe.pro`, `admin.fibe.pro`, and `api.fibe.pro`
- PostgreSQL setup scripts (system service + PostGIS)
- Backup scripts and systemd units (daily backups, 7-day retention)
- One-click deploy workflow for VM (`.github/workflows/deploy.yml`)

## First-time server bootstrap

### DNS before bootstrap

Create A records:

- `fibe.pro` -> `<YOUR_VM_PUBLIC_IP>`
- `admin.fibe.pro` -> `<YOUR_VM_PUBLIC_IP>`
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

5. Configure backups:

```bash
sudo mkdir -p /etc/fibe
sudo tee /etc/fibe/backup.env >/dev/null <<ENV
PGPASSWORD=<strong_password>
BACKUP_DIR=/var/backups/fibe-postgres
RETENTION_DAYS=7
ENV

sudo cp /opt/fibe/systemd/fibe-postgres-backup.service /etc/systemd/system/
sudo cp /opt/fibe/systemd/fibe-postgres-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now fibe-postgres-backup.timer
```

6. Initial deploy:

```bash
cd /opt/fibe
./scripts/deploy.sh
```

## Continuous deploy model

- `fibe-backend`, `fibe-admin`, and `fibe-website` publish Docker images to GHCR.
- App repositories SSH into the VM and recreate only their own services via `docker compose`.
- `fibe-infra` only syncs `/opt/fibe` on the VM, so service deploys always use the latest compose and Caddy configuration from the infra repo.
- To move to a new server: clone `fibe-infra`, copy `.env`, run bootstrap/postgres/deploy scripts.

## Required GitHub Secrets (in `fibe-infra`)

- `VM_HOST`
- `VM_USER`
- `VM_PORT`
- `VM_SSH_KEY`

## Required GitHub Secrets and Variables (in app repos that deploy over SSH)

- Secrets: `DEPLOY_HOST`, `DEPLOY_SSH_KEY`, `GHCR_READ_TOKEN`, `GHCR_USERNAME`
- Variables or secrets: `DEPLOY_PORT`, `DEPLOY_USER`
- Variables: `DEPLOY_PATH` (example: `/opt/fibe`)
- Optional secrets: `DEPLOY_SSH_PASSPHRASE`, `WEBSITE_HEALTHCHECK_URL`, `API_HEALTHCHECK_URL`, `ADMIN_HEALTHCHECK_URL`
