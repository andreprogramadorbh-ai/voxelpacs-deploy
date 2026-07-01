#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/rollback.sh
# Reverte para o commit anterior do repositório e reinicia os containers
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()     { echo -e "${GREEN}[VOXEL]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
ok()      { echo -e "${GREEN}  ✔${NC} $*"; }
section() { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${NC}\n${BOLD}${CYAN}  $*${NC}\n${BOLD}${BLUE}══════════════════════════════════════════${NC}\n"; }

[ -f ".env" ] && source .env || error ".env não encontrado."

if command -v docker-compose >/dev/null 2>&1; then COMPOSE="docker-compose"
elif docker compose version >/dev/null 2>&1; then COMPOSE="docker compose"
else error "Docker Compose não encontrado."; fi

CURRENT=$(git rev-parse --short HEAD 2>/dev/null || echo "desconhecido")
PREV=$(git rev-parse --short HEAD~1 2>/dev/null || echo "")
[ -z "$PREV" ] && error "Não há commit anterior para reverter."

section "VOXEL PACS — Rollback"
log "Commit atual:    ${CURRENT}"
log "Commit anterior: ${PREV}"
read -rp "$(echo -e "${YELLOW}Confirmar rollback para ${PREV}? (s/N): ${NC}")" CONFIRM
[[ "$CONFIRM" =~ ^[sS]$ ]] || error "Rollback cancelado."

section "Parando containers"
cd docker && $COMPOSE down; cd "$PROJECT_DIR"
ok "Containers parados."

section "Revertendo para ${PREV}"
git reset --hard HEAD~1
ok "Código revertido para: $(git rev-parse --short HEAD)"

section "Reiniciando containers"
cd docker && $COMPOSE pull && $COMPOSE up -d; cd "$PROJECT_DIR"
ok "Containers reiniciados."

section "Rollback concluído!"
echo -e "${GREEN}${BOLD}  ✅ Revertido para: $(git rev-parse --short HEAD)\n  🌐 https://${DOMAIN:-localhost}${NC}\n"
