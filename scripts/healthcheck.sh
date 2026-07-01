#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/healthcheck.sh
# Valida: Docker, Compose, Nginx, OHIF, Orthanc, DICOMweb, SSL, disco, RAM, CPU
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ERRORS=0
ok()   { echo -e "  ${GREEN}✔${NC} $*"; }
fail() { echo -e "  ${RED}✘${NC} $*"; ERRORS=$((ERRORS+1)); }
warn() { echo -e "  ${YELLOW}⚠${NC} $*"; }
section() { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}\n"; }

[ -f ".env" ] && source .env || { echo -e "${RED}[ERROR]${NC} .env não encontrado."; exit 1; }

DOMAIN_VAL="${DOMAIN:-localhost}"
ORTHANC_URL="${ORTHANC_PROTOCOL:-http}://${ORTHANC_HOST:-localhost}:${ORTHANC_PORT:-8042}"
OHIF_PORT_VAL="${OHIF_PORT:-3000}"

echo -e "\n${BOLD}${BLUE}  VOXEL PACS — Health Check${NC}"
echo -e "  $(date '+%d/%m/%Y %H:%M:%S') | Domínio: ${DOMAIN_VAL}\n"

# ── Docker ────────────────────────────────────────────────────────────────────
section "Docker"
if command -v docker &>/dev/null; then
    ok "Docker: $(docker --version)"
else
    fail "Docker não encontrado."
fi

# ── Docker Compose ────────────────────────────────────────────────────────────
section "Docker Compose"
if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
    ok "Docker Compose V1: $(docker-compose --version)"
elif docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
    ok "Docker Compose V2: $(docker compose version)"
else
    fail "Docker Compose não encontrado."
    COMPOSE="docker compose"
fi

# ── Containers ────────────────────────────────────────────────────────────────
section "Containers"
for CONTAINER in voxelpacs-ohif voxelpacs-nginx; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "not found")
    if [ "$STATUS" = "running" ]; then ok "Container ${CONTAINER}: running"
    else fail "Container ${CONTAINER}: ${STATUS}"; fi
done

# ── Nginx ─────────────────────────────────────────────────────────────────────
section "Nginx"
if systemctl is-active --quiet nginx 2>/dev/null; then
    ok "Nginx (systemd): ativo"
else
    fail "Nginx não está ativo."
fi

# ── OHIF Viewer ───────────────────────────────────────────────────────────────
section "OHIF Viewer"
OHIF_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${OHIF_PORT_VAL}" --max-time 10 2>/dev/null || echo "000")
if [[ "$OHIF_CODE" == "200" ]]; then ok "OHIF: http://127.0.0.1:${OHIF_PORT_VAL} (HTTP ${OHIF_CODE})"
else fail "OHIF retornou HTTP ${OHIF_CODE}"; fi

# ── Orthanc ───────────────────────────────────────────────────────────────────
section "Orthanc"
ORTHANC_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ORTHANC_USERNAME:-}:${ORTHANC_PASSWORD:-}" \
    "${ORTHANC_URL}/system" --max-time 10 2>/dev/null || echo "000")
if [[ "$ORTHANC_CODE" == "200" ]]; then ok "Orthanc: ${ORTHANC_URL} (HTTP ${ORTHANC_CODE})"
else fail "Orthanc HTTP ${ORTHANC_CODE} — URL: ${ORTHANC_URL}"; fi

# ── DICOMweb ──────────────────────────────────────────────────────────────────
section "DICOMweb"
DICOM_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ORTHANC_USERNAME:-}:${ORTHANC_PASSWORD:-}" \
    "${ORTHANC_URL}/dicom-web/studies" --max-time 10 2>/dev/null || echo "000")
if [[ "$DICOM_CODE" == "200" ]]; then ok "DICOMweb: ${ORTHANC_URL}/dicom-web/studies (HTTP ${DICOM_CODE})"
else fail "DICOMweb HTTP ${DICOM_CODE}"; fi

# ── SSL ───────────────────────────────────────────────────────────────────────
section "SSL"
CERT_PATH="/etc/letsencrypt/live/${DOMAIN_VAL}/fullchain.pem"
if [ -f "$CERT_PATH" ]; then
    EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_PATH" 2>/dev/null | cut -d= -f2 || echo "desconhecido")
    DAYS_LEFT=$(( ( $(date -d "$EXPIRY" +%s 2>/dev/null || echo 0) - $(date +%s) ) / 86400 ))
    if [ "$DAYS_LEFT" -gt 14 ]; then ok "SSL válido. Expira em: ${EXPIRY} (${DAYS_LEFT} dias)"
    elif [ "$DAYS_LEFT" -gt 0 ]; then warn "SSL expira em ${DAYS_LEFT} dias! Execute: certbot renew"
    else fail "Certificado SSL expirado!"; fi
else
    warn "Certificado SSL não encontrado. Execute: bash scripts/generate-ssl.sh"
fi

# ── HTTPS público ─────────────────────────────────────────────────────────────
section "HTTPS público"
HTTPS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://${DOMAIN_VAL}" --max-time 15 2>/dev/null || echo "000")
if [[ "$HTTPS_CODE" == "200" ]]; then ok "HTTPS: https://${DOMAIN_VAL} (HTTP ${HTTPS_CODE})"
elif [[ "$HTTPS_CODE" == "000" ]]; then warn "HTTPS não acessível — verifique DNS."
else warn "HTTPS HTTP ${HTTPS_CODE}"; fi

# ── Espaço em disco ───────────────────────────────────────────────────────────
section "Espaço em disco"
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
DISK_INFO=$(df -h / | awk 'NR==2 {print $3 " usados de " $2 " (" $5 ")"}')
if [ "$DISK_USAGE" -lt 80 ]; then ok "Disco: ${DISK_INFO}"
elif [ "$DISK_USAGE" -lt 90 ]; then warn "Disco: ${DISK_INFO} — atenção!"
else fail "Disco crítico: ${DISK_INFO}"; fi

# ── RAM ───────────────────────────────────────────────────────────────────────
section "Memória RAM"
RAM_TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
RAM_USED=$(free -m | awk '/^Mem:/ {print $3}')
RAM_PCT=$(( RAM_USED * 100 / RAM_TOTAL ))
RAM_INFO="${RAM_USED}MB usados de ${RAM_TOTAL}MB (${RAM_PCT}%)"
if [ "$RAM_PCT" -lt 80 ]; then ok "RAM: ${RAM_INFO}"
elif [ "$RAM_PCT" -lt 90 ]; then warn "RAM: ${RAM_INFO} — atenção!"
else fail "RAM crítica: ${RAM_INFO}"; fi

# ── CPU ───────────────────────────────────────────────────────────────────────
section "CPU"
CPU_LOAD=$(awk '{print $1}' /proc/loadavg)
CPU_CORES=$(nproc)
CPU_PCT=$(echo "$CPU_LOAD $CPU_CORES" | awk '{printf "%d", ($1/$2)*100}')
if [ "$CPU_PCT" -lt 80 ]; then ok "CPU: Load ${CPU_LOAD} em ${CPU_CORES} cores (${CPU_PCT}%)"
elif [ "$CPU_PCT" -lt 95 ]; then warn "CPU: Load ${CPU_LOAD} em ${CPU_CORES} cores (${CPU_PCT}%) — atenção!"
else fail "CPU crítica: Load ${CPU_LOAD} em ${CPU_CORES} cores (${CPU_PCT}%)"; fi

# ── Resultado ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${BLUE}══════════════════════════════════════════${NC}"
if [ "$ERRORS" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}  ✅ Todos os checks passaram!${NC}"
else
    echo -e "${RED}${BOLD}  ✘ ${ERRORS} check(s) falharam. Revise os itens acima.${NC}"
fi
echo -e "${BOLD}${BLUE}══════════════════════════════════════════${NC}\n"
exit $ERRORS
