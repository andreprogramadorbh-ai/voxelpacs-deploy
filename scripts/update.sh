#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/update.sh
# Atualiza código, imagens Docker e reinicia sem downtime
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()     { echo -e "${GREEN}[VOXEL]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
ok()      { echo -e "${GREEN}  ✔${NC} $*"; }
section() { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${NC}\n${BOLD}${CYAN}  $*${NC}\n${BOLD}${BLUE}══════════════════════════════════════════${NC}\n"; }

[ -f ".env" ] && source .env || error ".env não encontrado."

if command -v docker-compose >/dev/null 2>&1; then COMPOSE="docker-compose"
elif docker compose version >/dev/null 2>&1; then COMPOSE="docker compose"
else error "Docker Compose não encontrado."; fi

section "VOXEL PACS — Atualização"
log "Compose: ${COMPOSE} | Commit atual: $(git rev-parse --short HEAD 2>/dev/null || echo 'N/A')"

section "Atualizando código"
git fetch origin
LOCAL=$(git rev-parse HEAD); REMOTE=$(git rev-parse origin/main)
if [ "$LOCAL" = "$REMOTE" ]; then ok "Código já está na versão mais recente."
else git pull origin main && ok "Código atualizado para: $(git rev-parse --short HEAD)"; fi

section "Atualizando imagens Docker"
docker pull ohif/app:latest
cd docker && $COMPOSE pull; cd "$PROJECT_DIR"
ok "Imagens atualizadas."

section "Reiniciando containers"
cd docker && $COMPOSE up -d --build --remove-orphans; cd "$PROJECT_DIR"
docker image prune -f --filter "dangling=true" 2>/dev/null || true
ok "Containers reiniciados."

section "Atualização concluída!"
echo -e "${GREEN}${BOLD}  ✅ VOXEL PACS atualizado!\n  🌐 https://${DOMAIN:-localhost}${NC}\n"
