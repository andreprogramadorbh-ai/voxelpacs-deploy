#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/install-certbot.sh
# Instala apenas o Certbot (sem gerar certificado)
# Para gerar o certificado, use: ./scripts/generate-ssl.sh
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${GREEN}[CERTBOT]${NC} $*"; }

log "Instalando Certbot..."
apt-get update -qq
apt-get install -y -qq certbot
log "Certbot instalado: $(certbot --version)"
log "Para gerar o certificado, execute: ./scripts/generate-ssl.sh"
