#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release postgresql postgresql-contrib postgis caddy

install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
fi
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
systemctl enable --now postgresql
systemctl enable --now caddy

id -u deployer >/dev/null 2>&1 || useradd -m -s /bin/bash deployer
usermod -aG docker deployer

mkdir -p /opt/fibe/scripts
chown -R deployer:deployer /opt/fibe

mkdir -p /etc/fibe
chmod 750 /etc/fibe

echo "VM bootstrap completed"
