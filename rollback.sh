#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — rollback.sh
# Reverte para o commit anterior do repositório e reinicia os containers
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[VOXEL]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
ok()      { echo -e "${GREEN}  ✔${NC} $*"; }
section() {
    echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $*${NC}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════${NC}\n"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Carregar .env ─────────────────────────────────────────────────────────────
[ -f ".env" ] && source .env || error ".env não encontrado."

# ── Detectar Compose ──────────────────────────────────────────────────────────
if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
elif docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
else
    error "Docker Compose não encontrado."
fi

section "VOXEL PACS — Rollback"

# ── Verificar histórico Git ───────────────────────────────────────────────────
CURRENT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "desconhecido")
PREV_COMMIT=$(git rev-parse --short HEAD~1 2>/dev/null || echo "")

if [ -z "$PREV_COMMIT" ]; then
    error "Não há commit anterior para reverter. Este é o primeiro commit."
fi

log "Commit atual:   ${CURRENT_COMMIT}"
log "Commit anterior: ${PREV_COMMIT}"
echo ""
read -rp "$(echo -e "${YELLOW}Confirmar rollback para ${PREV_COMMIT}? (s/N): ${NC}")" CONFIRM
[[ "$CONFIRM" =~ ^[sS]$ ]] || error "Rollback cancelado."

# ── Parar containers ──────────────────────────────────────────────────────────
section "Parando containers"
$COMPOSE down
ok "Containers parados."

# ── Reverter código ───────────────────────────────────────────────────────────
section "Revertendo para commit ${PREV_COMMIT}"
git reset --hard HEAD~1
ok "Código revertido para: $(git rev-parse --short HEAD)"

# ── Reiniciar containers ──────────────────────────────────────────────────────
section "Reiniciando containers"
$COMPOSE pull
$COMPOSE up -d
ok "Containers reiniciados."

section "Rollback concluído!"
echo -e "${GREEN}${BOLD}"
echo "  ✅ Sistema revertido para o commit: $(git rev-parse --short HEAD)"
echo "  🌐 OHIF Viewer: https://${DOMAIN:-localhost}"
echo ""
echo "  Para desfazer o rollback, execute: bash update.sh"
echo -e "${NC}"
