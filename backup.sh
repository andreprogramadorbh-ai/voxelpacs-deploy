#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — backup.sh
# Salva config/, .env, certificados SSL e docker-compose.yml
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[BACKUP]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}${BLUE}── $* ──${NC}\n"; }

BACKUP_DIR="${BACKUP_DIR:-/var/backups/voxelpacs}"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="${BACKUP_DIR}/voxelpacs_backup_${TIMESTAMP}.tar.gz"

section "VOXEL PACS — Backup"
mkdir -p "$BACKUP_DIR"

# Arquivos a incluir no backup
ITEMS=(
    "config/"
    "docker-compose.yml"
    "install.sh"
    "update.sh"
)

# Incluir .env se existir
[ -f ".env" ] && ITEMS+=(".env") || warn ".env não encontrado — pulando."

# Incluir certificados SSL se existirem
if [ -d "/etc/letsencrypt/live" ]; then
    log "Incluindo certificados SSL..."
    ITEMS+=("/etc/letsencrypt/live")
    ITEMS+=("/etc/letsencrypt/renewal")
fi

section "Criando arquivo de backup"
tar -czf "$BACKUP_FILE" "${ITEMS[@]}" 2>/dev/null || true
log "Backup criado: ${BACKUP_FILE}"
log "Tamanho: $(du -sh "$BACKUP_FILE" | cut -f1)"

# Manter apenas os últimos 10 backups
section "Rotacionando backups antigos"
ls -t "${BACKUP_DIR}"/voxelpacs_backup_*.tar.gz 2>/dev/null | tail -n +11 | xargs -r rm -f
log "Backups mantidos: $(ls "${BACKUP_DIR}"/voxelpacs_backup_*.tar.gz 2>/dev/null | wc -l)"

section "Backup concluído!"
echo -e "${GREEN}  Arquivo: ${BACKUP_FILE}${NC}"
echo -e "${GREEN}  Data: $(date '+%d/%m/%Y %H:%M:%S')${NC}"
