#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/healthcheck.sh
#
# Valida toda a stack em cascata:
#
#   Docker
#     └─ Container OHIF (docker ps)
#          └─ HTTP localhost:3000
#               └─ GET /dicom-web/studies (via proxy Nginx)
#                    └─ SSL (dias restantes)
#                         └─ Proxy Nginx → Orthanc
#                              └─ Orthanc /system
#
# Uso:
#   bash scripts/healthcheck.sh           — execução normal
#   bash scripts/healthcheck.sh --quiet   — sem output, apenas exit code
#   bash scripts/healthcheck.sh --json    — saída JSON (para automação)
#
# Chamado automaticamente pelo install.sh após o deploy.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# ── Opções ────────────────────────────────────────────────────────────────────
QUIET=false
JSON_OUTPUT=false
for ARG in "$@"; do
    case "$ARG" in
        --quiet) QUIET=true ;;
        --json)  JSON_OUTPUT=true ;;
    esac
done

# ── Cores ─────────────────────────────────────────────────────────────────────
if [ "$QUIET" = false ] && [ "$JSON_OUTPUT" = false ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

# ── Contadores ────────────────────────────────────────────────────────────────
ERRORS=0
WARNINGS=0
declare -A CHECK_STATUS  # nome → OK|WARN|FAIL
declare -A CHECK_MSG     # nome → mensagem

ok()   {
    local name="$1"; local msg="$2"
    CHECK_STATUS["$name"]="OK"
    CHECK_MSG["$name"]="$msg"
    [ "$QUIET" = false ] && [ "$JSON_OUTPUT" = false ] && \
        echo -e "${GREEN}  ✔${NC} ${msg}"
}
warn() {
    local name="$1"; local msg="$2"
    CHECK_STATUS["$name"]="WARN"
    CHECK_MSG["$name"]="$msg"
    WARNINGS=$(( WARNINGS + 1 ))
    [ "$QUIET" = false ] && [ "$JSON_OUTPUT" = false ] && \
        echo -e "${YELLOW}  ⚠${NC} ${msg}"
}
fail() {
    local name="$1"; local msg="$2"
    CHECK_STATUS["$name"]="FAIL"
    CHECK_MSG["$name"]="$msg"
    ERRORS=$(( ERRORS + 1 ))
    [ "$QUIET" = false ] && [ "$JSON_OUTPUT" = false ] && \
        echo -e "${RED}  ✘${NC} ${msg}"
}
section() {
    [ "$QUIET" = false ] && [ "$JSON_OUTPUT" = false ] && \
        echo -e "\n${BOLD}${BLUE}── $* ${NC}"
}

# ── Cabeçalho ─────────────────────────────────────────────────────────────────
if [ "$QUIET" = false ] && [ "$JSON_OUTPUT" = false ]; then
    echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  VOXEL PACS — Healthcheck${NC}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════${NC}"
    echo -e "  Data: $(date '+%Y-%m-%d %H:%M:%S')\n"
fi

# ── Carregar .env ─────────────────────────────────────────────────────────────
if [ -f ".env" ]; then
    source .env
else
    [ "$QUIET" = false ] && echo -e "${YELLOW}[WARN]${NC} .env não encontrado. Usando defaults."
fi

DOMAIN_VAL="${DOMAIN:-localhost}"
OHIF_PORT_VAL="${OHIF_PORT:-3000}"
ORTHANC_PROTO="${ORTHANC_PROTOCOL:-http}"
ORTHANC_HOST_VAL="${ORTHANC_HOST:-}"
ORTHANC_PORT_VAL="${ORTHANC_PORT:-8042}"
ORTHANC_USER="${ORTHANC_USERNAME:-}"
ORTHANC_PASS="${ORTHANC_PASSWORD:-}"
ORTHANC_URL="${ORTHANC_PROTO}://${ORTHANC_HOST_VAL}:${ORTHANC_PORT_VAL}"

# =============================================================================
# NÍVEL 1 — Docker
# =============================================================================
section "1. Docker"
if command -v docker &>/dev/null; then
    DOCKER_VER=$(docker --version 2>/dev/null | head -1)
    if docker info &>/dev/null; then
        ok "docker" "Docker: ${DOCKER_VER}"
    else
        fail "docker" "Docker instalado mas daemon não está rodando. Execute: systemctl start docker"
    fi
else
    fail "docker" "Docker não encontrado. Execute: bash scripts/install-docker.sh"
fi

# =============================================================================
# NÍVEL 2 — Container OHIF (docker ps)
# =============================================================================
section "2. Container OHIF"
if [[ "${CHECK_STATUS[docker]}" == "OK" ]]; then
    CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' voxelpacs-ohif 2>/dev/null || echo "not_found")
    CONTAINER_HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no_healthcheck{{end}}' voxelpacs-ohif 2>/dev/null || echo "unknown")

    if [[ "$CONTAINER_STATUS" == "running" ]]; then
        CONTAINER_UPTIME=$(docker inspect --format='{{.State.StartedAt}}' voxelpacs-ohif 2>/dev/null | cut -c1-19 | tr 'T' ' ')
        ok "ohif_container" "Container OHIF: running (iniciado: ${CONTAINER_UPTIME}) | health: ${CONTAINER_HEALTH}"
    elif [[ "$CONTAINER_STATUS" == "not_found" ]]; then
        fail "ohif_container" "Container voxelpacs-ohif não encontrado. Execute: cd docker && docker compose up -d"
    else
        fail "ohif_container" "Container OHIF: ${CONTAINER_STATUS}. Verifique: docker logs voxelpacs-ohif"
    fi
else
    warn "ohif_container" "Container OHIF: pulado (Docker com falha)"
fi

# =============================================================================
# NÍVEL 3 — HTTP localhost:3000 (OHIF responde localmente)
# =============================================================================
section "3. HTTP localhost:${OHIF_PORT_VAL} (OHIF)"
if [[ "${CHECK_STATUS[ohif_container]}" == "OK" ]]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        "http://127.0.0.1:${OHIF_PORT_VAL}" --max-time 10 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
        ok "ohif_http" "OHIF HTTP: http://127.0.0.1:${OHIF_PORT_VAL} → ${HTTP_CODE} OK"
    elif [[ "$HTTP_CODE" == "000" ]]; then
        fail "ohif_http" "OHIF HTTP: sem resposta em 127.0.0.1:${OHIF_PORT_VAL}. Container pode estar iniciando."
    else
        warn "ohif_http" "OHIF HTTP: http://127.0.0.1:${OHIF_PORT_VAL} → ${HTTP_CODE}"
    fi
else
    warn "ohif_http" "OHIF HTTP: pulado (container com falha)"
fi

# =============================================================================
# NÍVEL 4 — GET /dicom-web/studies via proxy Nginx
# =============================================================================
section "4. GET /dicom-web/studies (via proxy Nginx)"
if [[ "${CHECK_STATUS[ohif_http]}" == "OK" ]] || [[ "${CHECK_STATUS[ohif_http]}" == "WARN" ]]; then
    # Testa via HTTPS público (proxy Nginx → Orthanc)
    DICOM_VIA_PROXY=$(curl -s -o /dev/null -w "%{http_code}" \
        "https://${DOMAIN_VAL}/dicom-web/studies" \
        --max-time 15 2>/dev/null || echo "000")

    if [[ "$DICOM_VIA_PROXY" == "200" ]]; then
        ok "dicomweb_proxy" "DICOMweb via proxy: https://${DOMAIN_VAL}/dicom-web/studies → ${DICOM_VIA_PROXY} OK"
    elif [[ "$DICOM_VIA_PROXY" == "401" ]]; then
        # 401 = Nginx chegou no Orthanc mas autenticação falhou — proxy funcionando
        ok "dicomweb_proxy" "DICOMweb via proxy: https://${DOMAIN_VAL}/dicom-web/studies → ${DICOM_VIA_PROXY} (proxy ativo, autenticação Orthanc necessária)"
    elif [[ "$DICOM_VIA_PROXY" == "000" ]]; then
        fail "dicomweb_proxy" "DICOMweb via proxy: sem resposta. Verifique DNS e Nginx."
    else
        warn "dicomweb_proxy" "DICOMweb via proxy: https://${DOMAIN_VAL}/dicom-web/studies → ${DICOM_VIA_PROXY}"
    fi
else
    warn "dicomweb_proxy" "DICOMweb via proxy: pulado (OHIF com falha)"
fi

# =============================================================================
# NÍVEL 5 — SSL (certificado e dias restantes)
# =============================================================================
section "5. SSL"
CERT_PATH="/etc/letsencrypt/live/${DOMAIN_VAL}/fullchain.pem"
if [ -f "$CERT_PATH" ]; then
    EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_PATH" 2>/dev/null | cut -d= -f2 || echo "")
    if [ -n "$EXPIRY" ]; then
        DAYS_LEFT=$(( ( $(date -d "$EXPIRY" +%s 2>/dev/null || echo 0) - $(date +%s) ) / 86400 ))
        if [ "$DAYS_LEFT" -gt 30 ]; then
            ok "ssl" "SSL: válido por ${DAYS_LEFT} dias (expira: ${EXPIRY})"
        elif [ "$DAYS_LEFT" -gt 7 ]; then
            warn "ssl" "SSL: expira em ${DAYS_LEFT} dias! Execute: certbot renew"
        else
            fail "ssl" "SSL: CRÍTICO — expira em ${DAYS_LEFT} dias! Execute AGORA: certbot renew"
        fi
    else
        warn "ssl" "SSL: certificado encontrado mas não foi possível ler a validade."
    fi
else
    warn "ssl" "SSL: certificado não encontrado em ${CERT_PATH}. Execute: bash scripts/generate-ssl.sh"
fi

# =============================================================================
# NÍVEL 6 — Proxy Nginx (HTTPS público → OHIF)
# =============================================================================
section "6. Proxy Nginx (HTTPS → OHIF)"
HTTPS_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://${DOMAIN_VAL}" --max-time 15 2>/dev/null || echo "000")

if [[ "$HTTPS_CODE" == "200" ]]; then
    ok "nginx_proxy" "Proxy Nginx: https://${DOMAIN_VAL} → ${HTTPS_CODE} OK"
elif [[ "$HTTPS_CODE" == "000" ]]; then
    fail "nginx_proxy" "Proxy Nginx: sem resposta em https://${DOMAIN_VAL}. Verifique DNS e Nginx."
elif [[ "$HTTPS_CODE" == "502" ]]; then
    fail "nginx_proxy" "Proxy Nginx: 502 Bad Gateway — OHIF não está respondendo em 127.0.0.1:${OHIF_PORT_VAL}"
elif [[ "$HTTPS_CODE" == "301" ]] || [[ "$HTTPS_CODE" == "302" ]]; then
    ok "nginx_proxy" "Proxy Nginx: https://${DOMAIN_VAL} → ${HTTPS_CODE} (redirect OK)"
else
    warn "nginx_proxy" "Proxy Nginx: https://${DOMAIN_VAL} → ${HTTPS_CODE}"
fi

# Verificar se Nginx está ativo no systemd
if systemctl is-active --quiet nginx 2>/dev/null; then
    ok "nginx_service" "Nginx service: active (running)"
else
    fail "nginx_service" "Nginx service: não está rodando. Execute: systemctl start nginx"
fi

# Verificar server_name no Nginx
if nginx -T 2>/dev/null | grep -q "server_name ${DOMAIN_VAL}"; then
    ok "nginx_vhost" "Nginx VirtualHost: server_name '${DOMAIN_VAL}' configurado"
else
    warn "nginx_vhost" "Nginx VirtualHost: server_name '${DOMAIN_VAL}' não encontrado em nginx -T"
fi

# =============================================================================
# NÍVEL 7 — Orthanc (acesso direto ao servidor remoto)
# =============================================================================
section "7. Orthanc (servidor remoto)"
if [ -n "$ORTHANC_HOST_VAL" ]; then
    # Ping básico ao host Orthanc
    if ping -c 1 -W 3 "$ORTHANC_HOST_VAL" &>/dev/null; then
        ok "orthanc_ping" "Orthanc ping: ${ORTHANC_HOST_VAL} acessível"
    else
        warn "orthanc_ping" "Orthanc ping: ${ORTHANC_HOST_VAL} não respondeu ao ping (pode ser bloqueado por firewall)"
    fi

    # HTTP ao endpoint /system do Orthanc
    ORTHANC_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${ORTHANC_USER}:${ORTHANC_PASS}" \
        "${ORTHANC_URL}/system" --max-time 10 2>/dev/null || echo "000")

    if [[ "$ORTHANC_CODE" == "200" ]]; then
        ok "orthanc_system" "Orthanc /system: ${ORTHANC_URL}/system → ${ORTHANC_CODE} OK"
    elif [[ "$ORTHANC_CODE" == "401" ]]; then
        fail "orthanc_system" "Orthanc /system: 401 Unauthorized — verifique ORTHANC_USERNAME e ORTHANC_PASSWORD no .env"
    elif [[ "$ORTHANC_CODE" == "000" ]]; then
        fail "orthanc_system" "Orthanc /system: sem resposta em ${ORTHANC_URL}. Verifique se o servidor remoto está online."
    else
        warn "orthanc_system" "Orthanc /system: ${ORTHANC_URL}/system → ${ORTHANC_CODE}"
    fi

    # DICOMweb direto no Orthanc (sem proxy)
    DICOM_DIRECT=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${ORTHANC_USER}:${ORTHANC_PASS}" \
        "${ORTHANC_URL}/dicom-web/studies" --max-time 10 2>/dev/null || echo "000")

    if [[ "$DICOM_DIRECT" == "200" ]]; then
        ok "orthanc_dicomweb" "Orthanc DICOMweb: ${ORTHANC_URL}/dicom-web/studies → ${DICOM_DIRECT} OK"
    elif [[ "$DICOM_DIRECT" == "404" ]]; then
        warn "orthanc_dicomweb" "Orthanc DICOMweb: 404 — plugin DICOMweb pode não estar instalado no Orthanc"
    elif [[ "$DICOM_DIRECT" == "000" ]]; then
        fail "orthanc_dicomweb" "Orthanc DICOMweb: sem resposta em ${ORTHANC_URL}/dicom-web/studies"
    else
        warn "orthanc_dicomweb" "Orthanc DICOMweb: ${ORTHANC_URL}/dicom-web/studies → ${DICOM_DIRECT}"
    fi
else
    warn "orthanc_system" "Orthanc: ORTHANC_HOST não configurado no .env"
    warn "orthanc_dicomweb" "Orthanc DICOMweb: pulado (ORTHANC_HOST não configurado)"
fi

# =============================================================================
# RECURSOS DO SERVIDOR
# =============================================================================
section "8. Recursos do servidor"

# Disco
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
DISK_INFO=$(df -h / | awk 'NR==2 {print $3 " usados de " $2 " (" $5 ")"}')
if [ "$DISK_USAGE" -lt 80 ]; then   ok "disk" "Disco: ${DISK_INFO}"
elif [ "$DISK_USAGE" -lt 90 ]; then warn "disk" "Disco: ${DISK_INFO} — atenção!"
else                                fail "disk" "Disco crítico: ${DISK_INFO}"; fi

# RAM
RAM_TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
RAM_USED=$(free -m | awk '/^Mem:/ {print $3}')
RAM_PCT=$(( RAM_USED * 100 / RAM_TOTAL ))
RAM_INFO="${RAM_USED}MB usados de ${RAM_TOTAL}MB (${RAM_PCT}%)"
if [ "$RAM_PCT" -lt 80 ]; then   ok "ram" "RAM: ${RAM_INFO}"
elif [ "$RAM_PCT" -lt 90 ]; then warn "ram" "RAM: ${RAM_INFO} — atenção!"
else                             fail "ram" "RAM crítica: ${RAM_INFO}"; fi

# CPU
CPU_LOAD=$(awk '{print $1}' /proc/loadavg)
CPU_CORES=$(nproc)
CPU_PCT=$(echo "$CPU_LOAD $CPU_CORES" | awk '{printf "%d", ($1/$2)*100}')
if [ "$CPU_PCT" -lt 80 ]; then   ok "cpu" "CPU: Load ${CPU_LOAD} em ${CPU_CORES} cores (${CPU_PCT}%)"
elif [ "$CPU_PCT" -lt 95 ]; then warn "cpu" "CPU: Load ${CPU_LOAD} em ${CPU_CORES} cores (${CPU_PCT}%) — atenção!"
else                             fail "cpu" "CPU crítica: Load ${CPU_LOAD} em ${CPU_CORES} cores (${CPU_PCT}%)"; fi

# =============================================================================
# SAÍDA JSON (--json)
# =============================================================================
if [ "$JSON_OUTPUT" = true ]; then
    echo "{"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"domain\": \"${DOMAIN_VAL}\","
    echo "  \"errors\": ${ERRORS},"
    echo "  \"warnings\": ${WARNINGS},"
    echo "  \"checks\": {"
    FIRST=true
    for KEY in "${!CHECK_STATUS[@]}"; do
        STATUS="${CHECK_STATUS[$KEY]}"
        MSG="${CHECK_MSG[$KEY]}"
        MSG_ESCAPED="${MSG//\"/\\\"}"
        if [ "$FIRST" = true ]; then FIRST=false; else echo ","; fi
        printf "    \"%s\": {\"status\": \"%s\", \"message\": \"%s\"}" "$KEY" "$STATUS" "$MSG_ESCAPED"
    done
    echo ""
    echo "  }"
    echo "}"
    exit $ERRORS
fi

# =============================================================================
# RESULTADO FINAL
# =============================================================================
if [ "$QUIET" = false ]; then
    echo ""
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════${NC}"
    echo -e "  Checks: OK=$(echo "${!CHECK_STATUS[@]}" | tr ' ' '\n' | while read k; do [ "${CHECK_STATUS[$k]}" = "OK" ] && echo 1; done | wc -l) | WARN=${WARNINGS} | FAIL=${ERRORS}"
    echo ""
    if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
        echo -e "${GREEN}${BOLD}  ✅ Stack completa: SAUDÁVEL${NC}"
        echo -e "     Docker → OHIF → Nginx → SSL → Proxy → Orthanc"
    elif [ "$ERRORS" -eq 0 ]; then
        echo -e "${YELLOW}${BOLD}  ⚠  Stack operacional com ${WARNINGS} aviso(s). Revise os itens acima.${NC}"
    else
        echo -e "${RED}${BOLD}  ✘ ${ERRORS} falha(s) detectada(s). Revise os itens acima.${NC}"
    fi
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════${NC}\n"
fi

exit $ERRORS
