#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/firewall.sh
# Configura UFW para produção: permite 22 (SSH), 80 (HTTP), 443 (HTTPS)
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${GREEN}[FIREWALL]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
section() { echo -e "\n${BOLD}${BLUE}── $* ──${NC}\n"; }

section "Configurando Firewall (UFW)"

# Instalar UFW se necessário
if ! command -v ufw &>/dev/null; then
    apt-get install -y -qq ufw
fi

# Resetar regras
ufw --force reset

# Política padrão: bloquear entrada, permitir saída
ufw default deny incoming
ufw default allow outgoing

# Permitir SSH (evitar bloqueio)
ufw allow 22/tcp comment 'SSH'

# Permitir HTTP e HTTPS
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# Habilitar
ufw --force enable

log "Firewall configurado:"
ufw status verbose
