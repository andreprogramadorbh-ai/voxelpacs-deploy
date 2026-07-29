#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/backup.sh
# Backup separado em 4 partes (nunca um backup único):
#   1. PostgreSQL Orthanc  (pg_dump → backup/postgres-orthanc/)  — índice DICOM
#   2. MySQL API           (mysqldump → backup/mysql/)            — dados da API PHP
#   3. Storage DICOM       (tar → backup/storage/)               — arquivos binários
#   4. Configs             (tar → backup/configs/)               — configurações
#
# Uso:
#   bash scripts/backup.sh              # backup completo
#   bash scripts/backup.sh --db         # apenas bancos (PostgreSQL + MySQL)
#   bash scripts/backup.sh --storage    # apenas storage DICOM
#   bash scripts/backup.sh --configs    # apenas configs
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
ok()      { echo -e "${GREEN}  ✔${NC} $*"; }
warn()    { echo -e "${YELLOW}  ⚠${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
log()     { echo -e "${BLUE}  →${NC} $*"; }
section() { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}"; }

[ -f ".env" ] && source .env

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_BASE="${BACKUP_DIR:-./backups}/${TIMESTAMP}"
BACKUP_PG_ORTHANC="${BACKUP_BASE}/postgres-orthanc"
BACKUP_MYSQL="${BACKUP_BASE}/mysql"
BACKUP_STORAGE="${BACKUP_BASE}/storage"
BACKUP_CONFIGS="${BACKUP_BASE}/configs"

DO_DB=true; DO_STORAGE=true; DO_CONFIGS=true
[ "${1:-}" == "--db" ]      && { DO_STORAGE=false; DO_CONFIGS=false; }
[ "${1:-}" == "--storage" ] && { DO_DB=false; DO_CONFIGS=false; }
[ "${1:-}" == "--configs" ] && { DO_DB=false; DO_STORAGE=false; }

mkdir -p "$BACKUP_PG_ORTHANC" "$BACKUP_MYSQL" "$BACKUP_STORAGE" "$BACKUP_CONFIGS"

# ── 1. Backup PostgreSQL Orthanc (índice DICOM) ───────────────────────────────
if $DO_DB; then
    section "Backup PostgreSQL Orthanc (índice DICOM)"
    if docker ps --format '{{.Names}}' | grep -q "voxelpacs-postgres-orthanc"; then
        log "Executando pg_dump do índice DICOM..."
        docker exec voxelpacs-postgres-orthanc pg_dump \
            -U "orthanc_user" \
            -d "orthanc_voxel" \
            --format=custom \
            --compress=9 \
            > "${BACKUP_PG_ORTHANC}/orthanc_index_${TIMESTAMP}.dump"
        SIZE=$(du -sh "${BACKUP_PG_ORTHANC}/orthanc_index_${TIMESTAMP}.dump" | cut -f1)
        ok "PostgreSQL Orthanc: ${BACKUP_PG_ORTHANC}/orthanc_index_${TIMESTAMP}.dump (${SIZE})"
    else
        warn "Container voxelpacs-postgres-orthanc não está rodando — backup do índice ignorado"
    fi

    section "Backup MySQL API PHP"
    if docker ps --format '{{.Names}}' | grep -q "voxelpacs-mysql"; then
        log "Executando mysqldump da API PHP..."
        docker exec voxelpacs-mysql mysqldump \
            -u "${DB_USERNAME:-voxelpacs_user}" \
            -p"${DB_PASSWORD:-password}" \
            --single-transaction \
            --routines \
            --triggers \
            "${DB_DATABASE:-voxel_pacs}" \
            | gzip -9 > "${BACKUP_MYSQL}/voxelpacs_api_${TIMESTAMP}.sql.gz"
        SIZE=$(du -sh "${BACKUP_MYSQL}/voxelpacs_api_${TIMESTAMP}.sql.gz" | cut -f1)
        ok "MySQL API: ${BACKUP_MYSQL}/voxelpacs_api_${TIMESTAMP}.sql.gz (${SIZE})"
    else
        warn "Container voxelpacs-mysql não está rodando — backup da API ignorado"
    fi
fi

# ── 2. Backup Storage DICOM ───────────────────────────────────────────────────
if $DO_STORAGE; then
    section "Backup Storage DICOM"
    if [ -d "storage/dicom" ] && [ "$(ls -A storage/dicom 2>/dev/null)" ]; then
        log "Comprimindo storage DICOM..."
        tar -czf "${BACKUP_STORAGE}/dicom_${TIMESTAMP}.tar.gz" -C storage dicom
        SIZE=$(du -sh "${BACKUP_STORAGE}/dicom_${TIMESTAMP}.tar.gz" | cut -f1)
        ok "Storage: ${BACKUP_STORAGE}/dicom_${TIMESTAMP}.tar.gz (${SIZE})"
    else
        warn "storage/dicom vazio ou não encontrado — backup ignorado"
    fi
fi

# ── 3. Backup Configs ─────────────────────────────────────────────────────────
if $DO_CONFIGS; then
    section "Backup Configs"
    # Inclui: orthanc/, nginx/, ohif/, docker/, scripts/, .env
    # Exclui: storage/, postgres/data/, backups/, .git/
    tar -czf "${BACKUP_CONFIGS}/configs_${TIMESTAMP}.tar.gz" \
        --exclude='./storage' \
        --exclude='./postgres/data' \
        --exclude='./backups' \
        --exclude='./.git' \
        --exclude='./logs' \
        .
    SIZE=$(du -sh "${BACKUP_CONFIGS}/configs_${TIMESTAMP}.tar.gz" | cut -f1)
    ok "Configs: ${BACKUP_CONFIGS}/configs_${TIMESTAMP}.tar.gz (${SIZE})"
fi

# ── Resumo ────────────────────────────────────────────────────────────────────
section "Backup concluído"
echo -e "${GREEN}${BOLD}"
echo "  Timestamp: ${TIMESTAMP}"
echo "  Diretório: ${BACKUP_BASE}"
$DO_DB      && echo "  ✔ PostgreSQL Orthanc (índice DICOM)"
$DO_DB      && echo "  ✔ MySQL API PHP"
$DO_STORAGE && echo "  ✔ Storage DICOM"
$DO_CONFIGS && echo "  ✔ Configs"
echo -e "${NC}"
