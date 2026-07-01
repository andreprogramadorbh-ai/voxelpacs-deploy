#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/generate-ssl.sh
# Instala Certbot, gera certificado Let's Encrypt e configura renovação automática
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[SSL]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}${BLUE}── $* ──${NC}\n"; }

[ -f ".env" ] && source .env || error ".env não encontrado."
: "${DOMAIN:?Variável DOMAIN não definida}"
: "${CERTBOT_EMAIL:?Variável CERTBOT_EMAIL não definida}"

section "Instalando Certbot"
if ! command -v certbot &>/dev/null; then
    apt-get update -qq
    apt-get install -y -qq certbot
    log "Certbot instalado."
else
    log "Certbot já instalado: $(certbot --version)"
fi

section "Gerando certificado para ${DOMAIN}"
mkdir -p /var/www/certbot

certbot certonly \
    --webroot \
    --webroot-path /var/www/certbot \
    --email "${CERTBOT_EMAIL}" \
    --agree-tos \
    --no-eff-email \
    -d "${DOMAIN}" \
    --non-interactive

log "Certificado gerado com sucesso."

section "Configurando renovação automática"
CRON_JOB="0 3 * * * certbot renew --quiet --post-hook 'docker compose -f $(pwd)/docker-compose.yml exec nginx nginx -s reload'"
(crontab -l 2>/dev/null | grep -v "certbot renew"; echo "$CRON_JOB") | crontab -
log "Cron configurado: renovação diária às 03:00."

section "Recarregando Nginx"
docker compose exec nginx nginx -s reload 2>/dev/null || docker compose restart nginx
log "Nginx recarregado."

section "SSL configurado com sucesso!"
EXPIRY=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" | cut -d= -f2)
log "Certificado válido até: ${EXPIRY}"
log "Acesse: https://${DOMAIN}"
