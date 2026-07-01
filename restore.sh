#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — restore.sh
# Restaura automaticamente um backup
# Uso: ./restore.sh /var/backups/voxelpacs/voxelpacs_backup_20260601_120000.tar.gz
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[RESTORE]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}${BLUE}── $* ──${NC}\n"; }

BACKUP_FILE="${1:-}"

section "VOXEL PACS — Restauração"

# Verificar argumento
if [ -z "$BACKUP_FILE" ]; then
    echo -e "${YELLOW}Uso: ./restore.sh <arquivo_backup.tar.gz>${NC}"
    echo ""
    echo "Backups disponíveis:"
    ls -lh /var/backups/voxelpacs/voxelpacs_backup_*.tar.gz 2>/dev/null || echo "  Nenhum backup encontrado."
    exit 1
fi

[ -f "$BACKUP_FILE" ] || error "Arquivo não encontrado: ${BACKUP_FILE}"

# Confirmação
warn "ATENÇÃO: Isso irá sobrescrever as configurações atuais!"
read -rp "Confirmar restauração de ${BACKUP_FILE}? (s/N): " CONFIRM
[[ "$CONFIRM" =~ ^[sS]$ ]] || { log "Restauração cancelada."; exit 0; }

# Parar containers
section "Parando containers"
docker compose down || warn "Containers já estavam parados."

# Fazer backup do estado atual antes de restaurar
section "Backup preventivo do estado atual"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
mkdir -p /var/backups/voxelpacs
tar -czf "/var/backups/voxelpacs/pre_restore_${TIMESTAMP}.tar.gz" config/ .env docker-compose.yml 2>/dev/null || true
log "Estado atual salvo em: pre_restore_${TIMESTAMP}.tar.gz"

# Restaurar
section "Restaurando arquivos"
tar -xzf "$BACKUP_FILE" -C /
log "Arquivos restaurados."

# Subir containers
section "Reiniciando containers"
docker compose up -d --build
log "Containers reiniciados."

# Validar
sleep 5
bash ./healthcheck.sh

section "Restauração concluída!"
log "Sistema restaurado a partir de: ${BACKUP_FILE}"
