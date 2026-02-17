# fibe-infra

Infrastructure repository for portable deployment of Fibe services to any single VM.

## What this repo owns

- Runtime stack (`docker-compose.yml`) for:
  - `backend`
  - `admin`
  - `caddy` (TLS + reverse proxy)
- Caddy subdomain routing (`admin.*`, `api.*`)
- PostgreSQL setup scripts (system service + PostGIS)
- Backup scripts and systemd units (daily backups, 7-day retention)
- One-click deploy workflow for VM (`.github/workflows/deploy.yml`)

## First-time server bootstrap

### DNS before bootstrap

Create A records:

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

- `fibe-backend` and `fibe_admin` publish Docker images to GHCR.
- `fibe-backend` and `fibe_admin` send `repository_dispatch` event to `fibe-infra` after image publish.
- `fibe-infra` performs VM rollout via SSH (`infra-deploy` workflow).
- To move to a new server: clone `fibe-infra`, copy `.env`, run bootstrap/postgres/deploy scripts.

## Required GitHub Secrets (in `fibe-infra`)

- `VM_HOST`
- `VM_USER`
- `VM_PORT`
- `VM_SSH_KEY`
- `GHCR_TOKEN`
- Optional: `API_HEALTHCHECK_URL`, `ADMIN_HEALTHCHECK_URL`

## Required GitHub Secrets (in `fibe-backend` and `fibe_admin`)

- `INFRA_REPO` (example: `Akbarbiinazar/fibe-infra`)
- `INFRA_REPO_TOKEN` (PAT with access to call repository dispatch on infra repo)
