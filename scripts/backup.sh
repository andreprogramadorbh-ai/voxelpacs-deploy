#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/backup.sh
# Gera backup completo: config, docker, logs, certificados, app-config.js
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()      { echo -e "${GREEN}  ✔${NC} $*"; }
section() { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}\n"; }

[ -f ".env" ] && source .env

BACKUP_DIR="${BACKUP_DIR:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="voxelpacs_backup_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

mkdir -p "${BACKUP_PATH}/config"
mkdir -p "${BACKUP_PATH}/docker"
mkdir -p "${BACKUP_PATH}/logs"
mkdir -p "${BACKUP_PATH}/ssl"

section "VOXEL PACS — Backup ${TIMESTAMP}"

# Configurações
cp -r config/ "${BACKUP_PATH}/config/" 2>/dev/null && ok "config/ copiado"
cp .env "${BACKUP_PATH}/.env" 2>/dev/null && ok ".env copiado"

# Docker
cp docker/docker-compose.yml "${BACKUP_PATH}/docker/" 2>/dev/null && ok "docker-compose.yml copiado"
cp docker/app-config.js "${BACKUP_PATH}/docker/" 2>/dev/null && ok "app-config.js copiado"
cp docker/Dockerfile "${BACKUP_PATH}/docker/" 2>/dev/null || true

# Logs dos containers
docker logs voxelpacs-ohif > "${BACKUP_PATH}/logs/ohif.log" 2>&1 || true
docker logs voxelpacs-nginx > "${BACKUP_PATH}/logs/nginx.log" 2>&1 || true
ok "Logs copiados."

# Certificados SSL
if [ -d "/etc/letsencrypt/live/${DOMAIN:-voxelpacs}" ]; then
    cp -r "/etc/letsencrypt/live/${DOMAIN:-voxelpacs}" "${BACKUP_PATH}/ssl/" 2>/dev/null && ok "Certificados SSL copiados."
else
    echo -e "${YELLOW}  ⚠ Certificados SSL não encontrados.${NC}"
fi

# Compactar
cd "${BACKUP_DIR}"
tar -czf "${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}/"
rm -rf "${BACKUP_NAME}/"
cd "$PROJECT_DIR"

BACKUP_SIZE=$(du -sh "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" | cut -f1)
ok "Backup criado: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz (${BACKUP_SIZE})"

# Manter apenas os últimos 10 backups
ls -t "${BACKUP_DIR}"/*.tar.gz 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
echo -e "\n${GREEN}${BOLD}  ✅ Backup concluído!${NC}\n"
