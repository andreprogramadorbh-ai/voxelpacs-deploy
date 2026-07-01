#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — healthcheck.sh
# Verifica: Docker, OHIF, Nginx, SSL, Orthanc remoto, DICOMWeb, Portas, DNS
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}✅ $*${NC}"; }
fail() { echo -e "  ${RED}❌ $*${NC}"; ERRORS=$((ERRORS+1)); }
warn() { echo -e "  ${YELLOW}⚠️  $*${NC}"; }
section() { echo -e "\n${BOLD}${BLUE}── $* ──${NC}"; }

ERRORS=0

[ -f ".env" ] && source .env || true

section "Docker"
if command -v docker &>/dev/null; then
    ok "Docker instalado: $(docker --version)"
else
    fail "Docker não encontrado"
fi

if docker compose version &>/dev/null; then
    ok "Docker Compose: $(docker compose version)"
else
    fail "Docker Compose Plugin não encontrado"
fi

section "Containers"
for CONTAINER in voxelpacs-ohif voxelpacs-nginx; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "not_found")
    HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "no_healthcheck")
    if [[ "$STATUS" == "running" ]]; then
        if [[ "$HEALTH" == "healthy" ]]; then
            ok "${CONTAINER}: running (healthy)"
        elif [[ "$HEALTH" == "no_healthcheck" ]]; then
            ok "${CONTAINER}: running"
        else
            warn "${CONTAINER}: running (${HEALTH})"
        fi
    else
        fail "${CONTAINER}: ${STATUS}"
    fi
done

section "Portas"
for PORT in 80 443; do
    if ss -tlnp 2>/dev/null | grep -q ":${PORT} " || netstat -tlnp 2>/dev/null | grep -q ":${PORT} "; then
        ok "Porta ${PORT}: aberta"
    else
        warn "Porta ${PORT}: não detectada (pode estar dentro do container)"
    fi
done

section "HTTP/HTTPS"
DOMAIN="${DOMAIN:-view.voxelpacs.com.br}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${DOMAIN}/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
    ok "HTTP (${DOMAIN}): ${HTTP_CODE}"
else
    warn "HTTP (${DOMAIN}): ${HTTP_CODE} (pode precisar de SSL)"
fi

HTTPS_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "https://${DOMAIN}/" 2>/dev/null || echo "000")
if [[ "$HTTPS_CODE" == "200" ]]; then
    ok "HTTPS (${DOMAIN}): ${HTTPS_CODE}"
else
    warn "HTTPS (${DOMAIN}): ${HTTPS_CODE}"
fi

section "SSL"
SSL_CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
if [ -f "$SSL_CERT" ]; then
    EXPIRY=$(openssl x509 -enddate -noout -in "$SSL_CERT" 2>/dev/null | cut -d= -f2)
    DAYS_LEFT=$(( ( $(date -d "$EXPIRY" +%s) - $(date +%s) ) / 86400 ))
    if [[ $DAYS_LEFT -gt 30 ]]; then
        ok "SSL válido — expira em ${DAYS_LEFT} dias (${EXPIRY})"
    elif [[ $DAYS_LEFT -gt 0 ]]; then
        warn "SSL expira em ${DAYS_LEFT} dias — renovar em breve!"
    else
        fail "SSL expirado!"
    fi
else
    warn "Certificado SSL não encontrado em ${SSL_CERT}"
fi

section "Orthanc Remoto"
ORTHANC_PROTOCOL="${ORTHANC_PROTOCOL:-https}"
ORTHANC_HOST="${ORTHANC_HOST:-dicom.voxelpacs.com.br}"
ORTHANC_PORT="${ORTHANC_PORT:-8042}"
ORTHANC_URL="${ORTHANC_PROTOCOL}://${ORTHANC_HOST}:${ORTHANC_PORT}"

ORTHANC_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "${ORTHANC_URL}/system" 2>/dev/null || echo "000")
if [[ "$ORTHANC_CODE" =~ ^(200|401)$ ]]; then
    ok "Orthanc acessível em ${ORTHANC_URL} (HTTP ${ORTHANC_CODE})"
else
    fail "Orthanc não acessível em ${ORTHANC_URL} (HTTP ${ORTHANC_CODE})"
fi

section "DICOMWeb"
DICOMWEB_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "${ORTHANC_URL}/dicom-web/studies" 2>/dev/null || echo "000")
if [[ "$DICOMWEB_CODE" =~ ^(200|401)$ ]]; then
    ok "DICOMWeb endpoint acessível (HTTP ${DICOMWEB_CODE})"
else
    warn "DICOMWeb endpoint: HTTP ${DICOMWEB_CODE} (verifique autenticação)"
fi

section "DNS"
if nslookup "$DOMAIN" &>/dev/null; then
    IP=$(nslookup "$DOMAIN" 2>/dev/null | awk '/^Address: / { print $2 }' | head -1)
    ok "DNS resolvido: ${DOMAIN} → ${IP}"
else
    fail "DNS não resolvido para: ${DOMAIN}"
fi

# ── Resultado final ───────────────────────────────────────────────────────────
echo ""
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}  ✅ Sistema saudável — nenhum erro crítico encontrado.${NC}"
else
    echo -e "${RED}${BOLD}  ❌ ${ERRORS} erro(s) encontrado(s). Verifique os itens acima.${NC}"
fi
echo ""
