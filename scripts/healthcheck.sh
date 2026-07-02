#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/healthcheck.sh
# Validação completa da stack em cascata:
#
#   docker ps
#       ↓ Container OHIF
#       ↓ Container Orthanc
#       ↓ Container PostgreSQL
#       ↓ Container API VOXEL PACS
#   HTTP localhost:3000 (OHIF)
#   HTTP localhost:8042 (Orthanc)
#   GET /dicom-web/studies (via proxy Nginx)
#   SSL (dias restantes)
#   Proxy Nginx
#   Endpoints: /health, /ready, /live
#   Recursos: disco, RAM, CPU
#
# Uso:
#   bash scripts/healthcheck.sh           # saída colorida
#   bash scripts/healthcheck.sh --quiet   # apenas exit code
#   bash scripts/healthcheck.sh --json    # saída JSON
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

[ -f ".env" ] && source .env

DOMAIN="${DOMAIN:-view.voxelpacs.com.br}"
OHIF_PORT="${OHIF_PORT:-3000}"
MODE="${1:-}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

PASS=0; FAIL=0; WARN=0
declare -A RESULTS

check() {
    local name="$1" cmd="$2"
    if eval "$cmd" &>/dev/null; then
        RESULTS["$name"]="OK"
        PASS=$((PASS+1))
        [[ "$MODE" != "--quiet" && "$MODE" != "--json" ]] && \
            echo -e "${GREEN}  ✔${NC} ${name}"
    else
        RESULTS["$name"]="FAIL"
        FAIL=$((FAIL+1))
        [[ "$MODE" != "--quiet" && "$MODE" != "--json" ]] && \
            echo -e "${RED}  ✘${NC} ${name}"
    fi
}

warn_check() {
    local name="$1" cmd="$2"
    if eval "$cmd" &>/dev/null; then
        RESULTS["$name"]="OK"
        PASS=$((PASS+1))
        [[ "$MODE" != "--quiet" && "$MODE" != "--json" ]] && \
            echo -e "${GREEN}  ✔${NC} ${name}"
    else
        RESULTS["$name"]="WARN"
        WARN=$((WARN+1))
        [[ "$MODE" != "--quiet" && "$MODE" != "--json" ]] && \
            echo -e "${YELLOW}  ⚠${NC} ${name} (aviso)"
    fi
}

[[ "$MODE" != "--quiet" && "$MODE" != "--json" ]] && \
    echo -e "\n${BOLD}${BLUE}══ VOXEL PACS — Healthcheck ══${NC}"

# ── 1. Docker daemon ──────────────────────────────────────────────────────────
check "Docker daemon ativo" "docker info"

# ── 2. Containers em execução ─────────────────────────────────────────────────
check "Container: voxelpacs-postgres" \
    "docker ps --filter name=voxelpacs-postgres --filter status=running | grep -q voxelpacs-postgres"
check "Container: voxelpacs-orthanc" \
    "docker ps --filter name=voxelpacs-orthanc --filter status=running | grep -q voxelpacs-orthanc"
check "Container: voxelpacs-ohif" \
    "docker ps --filter name=voxelpacs-ohif --filter status=running | grep -q voxelpacs-ohif"
warn_check "Container: voxelpacs-api" \
    "docker ps --filter name=voxelpacs-api --filter status=running | grep -q voxelpacs-api"

# ── 3. HTTP localhost (sem proxy) ─────────────────────────────────────────────
check "OHIF HTTP localhost:${OHIF_PORT}" \
    "curl -sf --max-time 5 http://localhost:${OHIF_PORT}/ -o /dev/null"
check "Orthanc HTTP localhost:8042" \
    "curl -sf --max-time 5 http://localhost:8042/system -o /dev/null -u '${ORTHANC_USERNAME:-admin}:${ORTHANC_PASSWORD:-admin}'"

# ── 4. PostgreSQL via container ───────────────────────────────────────────────
check "PostgreSQL pronto" \
    "docker exec voxelpacs-postgres pg_isready -U ${POSTGRES_USER:-voxelpacs} -d ${POSTGRES_DB:-voxelpacs}"

# ── 5. DICOMweb via proxy Nginx ───────────────────────────────────────────────
# 401 é aceito (proxy funcionando, autenticação necessária)
check "GET /dicom-web/studies via Nginx" \
    "curl -sf --max-time 10 -o /dev/null -w '%{http_code}' https://${DOMAIN}/dicom-web/studies | grep -qE '^(200|401|403)$'"

# ── 6. SSL ────────────────────────────────────────────────────────────────────
if [ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
    DAYS_LEFT=$(( ($(date -d "$(openssl x509 -enddate -noout -in /etc/letsencrypt/live/${DOMAIN}/fullchain.pem | cut -d= -f2)" +%s) - $(date +%s)) / 86400 ))
    if [ "$DAYS_LEFT" -gt 30 ]; then
        RESULTS["SSL certificado"]="OK"
        PASS=$((PASS+1))
        [[ "$MODE" != "--quiet" && "$MODE" != "--json" ]] && \
            echo -e "${GREEN}  ✔${NC} SSL certificado (${DAYS_LEFT} dias restantes)"
    elif [ "$DAYS_LEFT" -gt 7 ]; then
        RESULTS["SSL certificado"]="WARN"
        WARN=$((WARN+1))
        [[ "$MODE" != "--quiet" && "$MODE" != "--json" ]] && \
            echo -e "${YELLOW}  ⚠${NC} SSL certificado expira em ${DAYS_LEFT} dias — renovar em breve"
    else
        RESULTS["SSL certificado"]="FAIL"
        FAIL=$((FAIL+1))
        [[ "$MODE" != "--quiet" && "$MODE" != "--json" ]] && \
            echo -e "${RED}  ✘${NC} SSL certificado expira em ${DAYS_LEFT} dias — CRÍTICO"
    fi
else
    warn_check "SSL certificado" "false"
fi

# ── 7. Nginx ──────────────────────────────────────────────────────────────────
check "Nginx ativo" "systemctl is-active nginx"
check "Nginx server_name ${DOMAIN}" "nginx -T 2>/dev/null | grep -q 'server_name ${DOMAIN}'"

# ── 8. Endpoints de monitoramento ─────────────────────────────────────────────
check "GET /health" \
    "curl -sf --max-time 5 https://${DOMAIN}/health -o /dev/null"
check "GET /live" \
    "curl -sf --max-time 5 https://${DOMAIN}/live -o /dev/null"
warn_check "GET /ready (API)" \
    "curl -sf --max-time 10 https://${DOMAIN}/ready -o /dev/null"

# ── 9. Recursos do sistema ────────────────────────────────────────────────────
DISK_USE=$(df / | awk 'NR==2{print $5}' | tr -d '%')
RAM_USE=$(free | awk '/^Mem/{printf "%.0f", $3/$2*100}')
CPU_USE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | tr -d '%us,' | cut -d. -f1)

[ "${DISK_USE:-0}" -lt 90 ] && \
    check "Disco (${DISK_USE}% usado)" "true" || \
    check "Disco (${DISK_USE}% usado — CRÍTICO)" "false"
[ "${RAM_USE:-0}" -lt 90 ] && \
    check "RAM (${RAM_USE}% usada)" "true" || \
    warn_check "RAM (${RAM_USE}% usada)" "false"

# ── Resultado final ───────────────────────────────────────────────────────────
TOTAL=$((PASS+FAIL+WARN))

if [[ "$MODE" == "--json" ]]; then
    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"domain\": \"${DOMAIN}\","
    echo "  \"pass\": ${PASS},"
    echo "  \"fail\": ${FAIL},"
    echo "  \"warn\": ${WARN},"
    echo "  \"total\": ${TOTAL},"
    echo "  \"status\": \"$([ $FAIL -eq 0 ] && echo OK || echo FAIL)\","
    echo "  \"checks\": {"
    for key in "${!RESULTS[@]}"; do
        echo "    \"${key}\": \"${RESULTS[$key]}\","
    done | sed '$ s/,$//'
    echo "  }"
    echo "}"
elif [[ "$MODE" != "--quiet" ]]; then
    echo ""
    if [ $FAIL -eq 0 ]; then
        echo -e "${GREEN}${BOLD}  ✅ Stack saudável — ${PASS}/${TOTAL} verificações OK${NC}"
    else
        echo -e "${RED}${BOLD}  ❌ ${FAIL} verificação(ões) falharam — ${PASS}/${TOTAL} OK${NC}"
    fi
    [ $WARN -gt 0 ] && echo -e "${YELLOW}  ⚠ ${WARN} aviso(s)${NC}"
fi

exit $FAIL
