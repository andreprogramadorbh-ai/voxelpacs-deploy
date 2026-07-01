#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/install-docker.sh
# Instala Docker Engine + Docker Compose Plugin no Ubuntu 24.04
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'
log() { echo -e "${GREEN}[DOCKER]${NC} $*"; }

log "Atualizando pacotes..."
apt-get update -qq

log "Instalando dependências..."
apt-get install -y -qq ca-certificates curl gnupg lsb-release

log "Adicionando chave GPG do Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

log "Adicionando repositório Docker..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

log "Instalando Docker Engine..."
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

log "Habilitando Docker no boot..."
systemctl enable docker
systemctl start docker

log "Docker instalado: $(docker --version)"
log "Docker Compose: $(docker compose version)"
