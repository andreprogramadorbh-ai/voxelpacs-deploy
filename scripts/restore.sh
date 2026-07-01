#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/restore.sh
# Restaura completamente o ambiente a partir de um backup
# Uso: bash scripts/restore.sh backups/voxelpacs_backup_YYYYMMDD_HHMMSS.tar.gz
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
ok()    { echo -e "${GREEN}  ✔${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}\n"; }

BACKUP_FILE="${1:-}"
[ -z "$BACKUP_FILE" ] && error "Informe o arquivo de backup. Uso: bash scripts/restore.sh backups/arquivo.tar.gz"
[ -f "$BACKUP_FILE" ] || error "Arquivo não encontrado: ${BACKUP_FILE}"

# Detectar Compose
if command -v docker-compose >/dev/null 2>&1; then COMPOSE="docker-compose"
elif docker compose version >/dev/null 2>&1; then COMPOSE="docker compose"
else error "Docker Compose não encontrado."; fi

section "VOXEL PACS — Restore"
echo -e "  Arquivo: ${BACKUP_FILE}\n"
read -rp "$(echo -e "${YELLOW}Confirmar restore? Isso substituirá as configurações atuais. (s/N): ${NC}")" CONFIRM
[[ "$CONFIRM" =~ ^[sS]$ ]] || error "Restore cancelado."

RESTORE_TMP="/tmp/voxelpacs_restore_$$"
mkdir -p "$RESTORE_TMP"
tar -xzf "$BACKUP_FILE" -C "$RESTORE_TMP"
BACKUP_DIR_NAME=$(ls "$RESTORE_TMP")
BACKUP_EXTRACTED="${RESTORE_TMP}/${BACKUP_DIR_NAME}"

section "Parando containers"
cd docker && $COMPOSE down 2>/dev/null || true; cd "$PROJECT_DIR"

section "Restaurando configurações"
[ -d "${BACKUP_EXTRACTED}/config" ] && cp -r "${BACKUP_EXTRACTED}/config/." config/ && ok "config/ restaurado"
[ -f "${BACKUP_EXTRACTED}/.env" ] && cp "${BACKUP_EXTRACTED}/.env" .env && ok ".env restaurado"
[ -f "${BACKUP_EXTRACTED}/docker/docker-compose.yml" ] && cp "${BACKUP_EXTRACTED}/docker/docker-compose.yml" docker/ && ok "docker-compose.yml restaurado"
[ -f "${BACKUP_EXTRACTED}/docker/app-config.js" ] && cp "${BACKUP_EXTRACTED}/docker/app-config.js" docker/ && ok "app-config.js restaurado"

section "Restaurando certificados SSL"
if [ -d "${BACKUP_EXTRACTED}/ssl" ] && [ "$(ls -A ${BACKUP_EXTRACTED}/ssl)" ]; then
    cp -r "${BACKUP_EXTRACTED}/ssl/." /etc/letsencrypt/live/ 2>/dev/null && ok "Certificados SSL restaurados."
fi

section "Reiniciando containers"
source .env
cd docker && $COMPOSE up -d; cd "$PROJECT_DIR"
ok "Containers reiniciados."

rm -rf "$RESTORE_TMP"
echo -e "\n${GREEN}${BOLD}  ✅ Restore concluído!${NC}\n"
