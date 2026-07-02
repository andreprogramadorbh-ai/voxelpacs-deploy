#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/update.sh
# Atualiza a plataforma sem downtime:
#   1. git pull (configs e scripts)
#   2. docker pull (novas imagens)
#   3. docker compose up --remove-orphans (sem parar containers saudáveis)
#   4. docker image prune (limpar imagens antigas)
#   5. healthcheck automático
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
ok()      { echo -e "${GREEN}  ✔${NC} $*"; }
warn()    { echo -e "${YELLOW}  ⚠${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
log()     { echo -e "${BLUE}  →${NC} $*"; }
section() { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}"; }

[ -f ".env" ] && source .env

# Detectar Compose
if docker compose version &>/dev/null 2>&1; then COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then COMPOSE="docker-compose"
else error "Docker Compose não encontrado"; fi

section "Atualizando VOXEL PACS"
log "Compose: $COMPOSE"

section "1. Atualizando código (git pull)"
git pull origin main || warn "git pull falhou — continuando com versão atual"
ok "Código atualizado"

section "2. Baixando novas imagens"
cd docker
$COMPOSE pull 2>/dev/null || warn "Algumas imagens não atualizadas"
cd "$PROJECT_DIR"
ok "Imagens atualizadas"

section "3. Regenerando configurações"
bash scripts/install-ohif.sh
ok "app-config.js regenerado"

section "4. Subindo containers"
cd docker
$COMPOSE up -d --build --remove-orphans
cd "$PROJECT_DIR"
ok "Containers atualizados"

section "5. Limpando imagens antigas"
docker image prune -f 2>/dev/null || true
ok "Imagens antigas removidas"

section "6. Healthcheck"
sleep 10
bash scripts/healthcheck.sh

section "Atualização concluída!"
