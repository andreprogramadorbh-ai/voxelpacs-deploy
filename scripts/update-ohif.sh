#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/update-ohif.sh
# Atualiza apenas o container OHIF sem afetar Nginx ou outras configurações
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${GREEN}[OHIF]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
section() { echo -e "\n${BOLD}${BLUE}── $* ──${NC}\n"; }

section "Atualizando OHIF Viewer"

# Backup preventivo
bash ./backup.sh

# Baixar nova imagem OHIF
log "Baixando nova imagem ohif/app:latest..."
docker pull ohif/app:latest

# Restart apenas do container OHIF
log "Reiniciando container OHIF..."
docker compose up -d --no-deps --build ohif

# Aguardar
sleep 5

# Verificar saúde
STATUS=$(docker inspect --format='{{.State.Health.Status}}' voxelpacs-ohif 2>/dev/null || echo "unknown")
if [[ "$STATUS" == "healthy" ]]; then
    log "OHIF atualizado e saudável!"
else
    warn "OHIF status: ${STATUS} — verifique os logs: docker logs voxelpacs-ohif"
fi

log "OHIF atualizado em $(date '+%d/%m/%Y %H:%M:%S')"
