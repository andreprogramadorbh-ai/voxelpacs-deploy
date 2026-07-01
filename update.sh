#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — update.sh
# Atualiza o repositório e reinicia os containers sem downtime
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

[ -f ".env" ] && source .env || error ".env não encontrado."

# Detectar Compose
if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
elif docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
else
    error "Docker Compose não encontrado."
fi

section "VOXEL PACS — Atualização"
log "Compose detectado: ${COMPOSE}"
log "Commit atual: $(git rev-parse --short HEAD 2>/dev/null || echo 'desconhecido')"

section "Atualizando código"
git fetch origin
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)
if [ "$LOCAL" = "$REMOTE" ]; then
    ok "Código já está na versão mais recente."
else
    git pull origin main
    ok "Código atualizado para: $(git rev-parse --short HEAD)"
fi

section "Atualizando imagens Docker"
docker pull ohif/app:latest
$COMPOSE pull
ok "Imagens atualizadas."

section "Reiniciando containers"
$COMPOSE up -d --build --remove-orphans
ok "Containers reiniciados."

docker image prune -f --filter "dangling=true" 2>/dev/null || true
ok "Imagens antigas removidas."

section "Atualização concluída!"
echo -e "${GREEN}${BOLD}"
echo "  ✅ VOXEL PACS atualizado com sucesso!"
echo "  🌐 OHIF Viewer: https://${DOMAIN:-localhost}"
echo "  📋 Para verificar: bash healthcheck.sh"
echo -e "${NC}"
