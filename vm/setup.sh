#!/bin/bash
# ============================================================
# VM bootstrap — run once on a fresh DigitalOcean Droplet
# Ubuntu 22.04 LTS, 2vCPU / 4GB RAM
#
# Usage:
#   scp -r vm/ root@<VM_IP>:/opt/stateful
#   ssh root@<VM_IP> "cd /opt/stateful && cp .env.example .env && nano .env && bash setup.sh"
# ============================================================
set -euo pipefail

VM_IP="${1:-$(curl -s ifconfig.me)}"
DOMAIN="keycloak.limmengty.com"
EMAIL="nanokh9988@gmail.com"

if command -v docker &>/dev/null; then
  echo "==> Docker already installed, skipping..."
else
  echo "==> Installing Docker..."
  apt-get update -qq
  apt-get install -y ca-certificates curl gnupg ufw

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

  systemctl enable --now docker
fi

echo "==> Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
# Allow PostgreSQL only from K8s cluster CIDR — replace with your DOKS node CIDR
ufw allow from 10.0.0.0/8 to any port 5432
ufw --force enable

echo "==> Getting initial TLS certificate for ${DOMAIN}..."
mkdir -p /var/www/certbot /etc/letsencrypt

# Temporary nginx to answer HTTP-01 challenge (mounts webroot so it can serve challenge files)
docker run --rm -d --name nginx-temp \
  -p 80:80 \
  -v /var/www/certbot:/var/www/certbot \
  nginx:alpine sh -c 'mkdir -p /var/www/certbot && nginx -g "daemon off;" &
cat > /etc/nginx/conf.d/default.conf << EOF
server {
  listen 80;
  location /.well-known/acme-challenge/ { root /var/www/certbot; }
  location / { return 200 "ok"; }
}
EOF
nginx -s reload; wait'

sleep 3

docker run --rm \
  -v /etc/letsencrypt:/etc/letsencrypt \
  -v /var/www/certbot:/var/www/certbot \
  certbot/certbot certonly \
    --webroot \
    --webroot-path /var/www/certbot \
    -d "${DOMAIN}" \
    --email "${EMAIL}" \
    --agree-tos \
    --non-interactive

docker stop nginx-temp 2>/dev/null || true

echo "==> Starting all services..."
docker compose up -d

echo ""
echo "==> Done. Keycloak will be ready in ~90s at https://${DOMAIN}"
echo "==> expense-api PostgreSQL is accessible at ${VM_IP}:5432"
echo ""
echo "IMPORTANT: Update K8s secret expense-api-secret.DB_PASSWORD to match .env EXPENSE_DB_PASSWORD"
echo "IMPORTANT: Update K8s configmap expense-api-configmap SPRING_DATASOURCE_URL to jdbc:postgresql://${VM_IP}:5432/expense_db"
