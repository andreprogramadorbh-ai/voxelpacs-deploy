#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/update-ohif.sh
# Atualiza apenas o container OHIF sem apagar configurações
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()      { echo -e "${GREEN}  ✔${NC} $*"; }
section() { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}\n"; }

[ -f ".env" ] && source .env

if command -v docker-compose >/dev/null 2>&1; then COMPOSE="docker-compose"
elif docker compose version >/dev/null 2>&1; then COMPOSE="docker compose"
else echo "Docker Compose não encontrado."; exit 1; fi

section "VOXEL PACS — Atualização OHIF"
docker pull ohif/app:latest
ok "Imagem OHIF atualizada."

cd docker
$COMPOSE up -d --no-deps --build ohif
cd "$PROJECT_DIR"
ok "Container OHIF reiniciado com nova imagem."

docker image prune -f --filter "dangling=true" 2>/dev/null || true
echo -e "\n${GREEN}${BOLD}  ✅ OHIF atualizado!${NC}\n"
