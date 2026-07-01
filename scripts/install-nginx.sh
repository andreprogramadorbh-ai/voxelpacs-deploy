#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/install-nginx.sh
# Nota: O Nginx é gerenciado via Docker. Este script é apenas para referência
# de instalação nativa, caso necessário para desenvolvimento local.
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${GREEN}[NGINX]${NC} $*"; }

log "Instalando Nginx (nativo — apenas para desenvolvimento)..."
apt-get update -qq
apt-get install -y -qq nginx
systemctl enable nginx
systemctl start nginx
log "Nginx instalado: $(nginx -v 2>&1)"
log "ATENÇÃO: Em produção, use o Nginx via Docker (docker-compose.yml)."
