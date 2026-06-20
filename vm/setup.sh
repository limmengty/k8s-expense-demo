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

echo "==> Installing Docker..."
apt-get update -qq
apt-get install -y docker.io docker-compose-plugin curl ufw

systemctl enable --now docker

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
# Temporary nginx to answer HTTP-01 challenge
docker run --rm -d --name nginx-temp \
  -p 80:80 \
  -v /opt/stateful/nginx/keycloak.conf:/etc/nginx/conf.d/default.conf:ro \
  nginx:alpine || true

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
