#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — update.sh
# Atualiza OHIF, Nginx e imagens Docker sem perder configurações
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[UPDATE]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
section() { echo -e "\n${BOLD}${BLUE}── $* ──${NC}\n"; }

section "VOXEL PACS — Atualização"

# Verificar .env
[ -f ".env" ] || { echo -e "${RED}[ERROR]${NC} .env não encontrado."; exit 1; }
source .env

# Backup automático antes de atualizar
section "Fazendo backup preventivo"
bash ./backup.sh
log "Backup realizado."

# Atualizar repositório
section "Atualizando repositório"
git pull origin main
log "Repositório atualizado."

# Baixar novas imagens
section "Baixando novas imagens Docker"
docker compose pull
log "Imagens atualizadas."

# Rebuild e restart sem downtime
section "Reiniciando containers"
docker compose up -d --build --remove-orphans
log "Containers reiniciados."

# Remover imagens antigas
section "Limpando imagens antigas"
docker image prune -f
log "Limpeza concluída."

# Validar
section "Validando"
sleep 5
bash ./healthcheck.sh

section "Atualização concluída!"
log "VOXEL PACS atualizado com sucesso em $(date '+%d/%m/%Y %H:%M:%S')"
