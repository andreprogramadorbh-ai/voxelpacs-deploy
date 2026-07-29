#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/migrate-sqlite-to-postgres.sh
# Migração do índice DICOM: SQLite (legado) → PostgreSQL 16 (Fase 2)
#
# O QUE ESTE SCRIPT FAZ:
#   1. Valida pré-requisitos (Docker, containers, .env)
#   2. Faz backup do SQLite atual (storage/dicom/orthanc.db)
#   3. Para o container Orthanc
#   4. Sobe o container postgres-orthanc (se não estiver rodando)
#   5. Aguarda o PostgreSQL estar pronto
#   6. Reinicia o Orthanc com o plugin PostgreSQL ativo
#   7. Aguarda o Orthanc reindexar automaticamente os arquivos DICOM
#   8. Valida que o índice PostgreSQL está populado
#   9. Executa healthcheck completo
#
# COMO O ORTHANC MIGRA:
#   O plugin PostgreSQL do Orthanc (EnableIndex=true, EnableStorage=false)
#   reconstrói o índice automaticamente ao iniciar, varrendo todos os arquivos
#   DICOM no StorageDirectory (/var/lib/orthanc/db). Não há ferramenta de
#   migração direta SQLite→PostgreSQL — o Orthanc reindexará tudo.
#
# PRÉ-REQUISITOS:
#   - .env configurado com POSTGRES_ORTHANC_PASSWORD
#   - orthanc/postgresql.json com POSTGRES_ORTHANC_PASSWORD_PLACEHOLDER
#     já substituído pelo install.sh (ou manualmente)
#   - Container voxelpacs-orthanc existente (mesmo que parado)
#   - storage/dicom/ com os arquivos DICOM existentes
#
# TEMPO ESTIMADO:
#   - Depende do volume de arquivos DICOM no storage
#   - ~1000 estudos: ~5-10 minutos
#   - ~10000 estudos: ~30-60 minutos
#
# ROLLBACK:
#   Se algo der errado, o SQLite original está em:
#   backups/<timestamp>/sqlite/orthanc.db
#   Para reverter: copiar de volta para storage/dicom/orthanc.db e
#   remover o postgresql.json do volume do Orthanc.
#
# Uso:
#   sudo bash scripts/migrate-sqlite-to-postgres.sh
#   sudo bash scripts/migrate-sqlite-to-postgres.sh --dry-run   # apenas valida
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# ── Cores e funções de output ─────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
ok()      { echo -e "${GREEN}  ✔${NC} $*"; }
warn()    { echo -e "${YELLOW}  ⚠${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
log()     { echo -e "${BLUE}  →${NC} $*"; }
section() { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}"; }

DRY_RUN=false
[ "${1:-}" == "--dry-run" ] && DRY_RUN=true

echo -e "\n${BOLD}${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║  VOXEL PACS — Migração SQLite → PostgreSQL (Fase 2)  ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
$DRY_RUN && echo -e "${YELLOW}  [DRY-RUN] Apenas validação — nenhuma alteração será feita${NC}"

# ── 1. Verificar root ─────────────────────────────────────────────────────────
section "Verificando pré-requisitos"
[[ $EUID -ne 0 ]] && error "Execute como root: sudo bash scripts/migrate-sqlite-to-postgres.sh"
ok "Executando como root"

# ── 2. Carregar .env ──────────────────────────────────────────────────────────
[ -f ".env" ] || error ".env não encontrado. Execute: cp .env.example .env && nano .env"
source .env
ok ".env carregado"

# ── 3. Validar variáveis obrigatórias ─────────────────────────────────────────
[ -z "${POSTGRES_ORTHANC_PASSWORD:-}" ] && \
    error "POSTGRES_ORTHANC_PASSWORD não configurado no .env"
ok "POSTGRES_ORTHANC_PASSWORD configurado"

# ── 4. Verificar Docker ───────────────────────────────────────────────────────
command -v docker &>/dev/null || error "Docker não encontrado"
docker info &>/dev/null || error "Docker daemon não está rodando"
ok "Docker disponível"

# Detectar Docker Compose V1 ou V2
if docker compose version &>/dev/null 2>&1; then
    COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE="docker-compose"
else
    error "Docker Compose não encontrado"
fi
ok "Docker Compose disponível: $COMPOSE"

# ── 5. Verificar postgresql.json ──────────────────────────────────────────────
[ -f "orthanc/postgresql.json" ] || \
    error "orthanc/postgresql.json não encontrado. Execute: bash scripts/install.sh"

# Verificar se o placeholder foi substituído
if grep -q "POSTGRES_ORTHANC_PASSWORD_PLACEHOLDER" orthanc/postgresql.json; then
    warn "postgresql.json ainda tem placeholder — substituindo agora..."
    if ! $DRY_RUN; then
        sed -i "s/POSTGRES_ORTHANC_PASSWORD_PLACEHOLDER/${POSTGRES_ORTHANC_PASSWORD}/g" \
            orthanc/postgresql.json
        ok "postgresql.json: placeholder substituído"
    else
        warn "[DRY-RUN] postgresql.json precisaria ser atualizado"
    fi
else
    ok "postgresql.json: senha já configurada"
fi

# ── 6. Verificar storage DICOM ────────────────────────────────────────────────
[ -d "storage/dicom" ] || error "storage/dicom não encontrado"
DICOM_COUNT=$(find storage/dicom -name "*.dcm" 2>/dev/null | wc -l || echo 0)
SQLITE_FILE="storage/dicom/orthanc.db"
log "Arquivos DICOM no storage: ${DICOM_COUNT}"

if [ -f "$SQLITE_FILE" ]; then
    SQLITE_SIZE=$(du -sh "$SQLITE_FILE" | cut -f1)
    ok "SQLite encontrado: ${SQLITE_FILE} (${SQLITE_SIZE})"
else
    warn "SQLite não encontrado em ${SQLITE_FILE} — Orthanc pode já estar usando PostgreSQL"
fi

if $DRY_RUN; then
    echo -e "\n${GREEN}${BOLD}  ✅ Dry-run concluído — todos os pré-requisitos OK${NC}"
    echo -e "  Execute sem --dry-run para realizar a migração."
    exit 0
fi

# ── 7. Backup do SQLite ───────────────────────────────────────────────────────
section "Backup do SQLite (pré-migração)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_SQLITE="${BACKUP_DIR:-./backups}/${TIMESTAMP}/sqlite"
mkdir -p "$BACKUP_SQLITE"

if [ -f "$SQLITE_FILE" ]; then
    log "Copiando ${SQLITE_FILE} → ${BACKUP_SQLITE}/"
    cp "$SQLITE_FILE" "${BACKUP_SQLITE}/orthanc_pre_migration_${TIMESTAMP}.db"
    SIZE=$(du -sh "${BACKUP_SQLITE}/orthanc_pre_migration_${TIMESTAMP}.db" | cut -f1)
    ok "Backup SQLite: ${BACKUP_SQLITE}/orthanc_pre_migration_${TIMESTAMP}.db (${SIZE})"
else
    warn "SQLite não encontrado — backup ignorado"
fi

# Backup das configs também
tar -czf "${BACKUP_SQLITE}/configs_pre_migration_${TIMESTAMP}.tar.gz" \
    --exclude='./storage' \
    --exclude='./postgres-orthanc/data' \
    --exclude='./postgres/data' \
    --exclude='./backups' \
    --exclude='./.git' \
    . 2>/dev/null || true
ok "Backup de configs: ${BACKUP_SQLITE}/configs_pre_migration_${TIMESTAMP}.tar.gz"

# ── 8. Parar o Orthanc ────────────────────────────────────────────────────────
section "Parando Orthanc"
cd docker
if docker ps --format '{{.Names}}' | grep -q "voxelpacs-orthanc"; then
    log "Parando container voxelpacs-orthanc..."
    $COMPOSE stop orthanc
    ok "Orthanc parado"
else
    warn "Container voxelpacs-orthanc já estava parado"
fi
cd "$PROJECT_DIR"

# ── 9. Subir PostgreSQL Orthanc ───────────────────────────────────────────────
section "Iniciando PostgreSQL Orthanc"
cd docker
if ! docker ps --format '{{.Names}}' | grep -q "voxelpacs-postgres-orthanc"; then
    log "Subindo container voxelpacs-postgres-orthanc..."
    $COMPOSE up -d postgres-orthanc
    ok "Container postgres-orthanc iniciado"
else
    ok "Container postgres-orthanc já estava rodando"
fi
cd "$PROJECT_DIR"

# Aguardar PostgreSQL estar pronto
log "Aguardando PostgreSQL Orthanc estar pronto..."
MAX_WAIT=60
WAITED=0
until docker exec voxelpacs-postgres-orthanc \
    pg_isready -U orthanc_user -d orthanc_voxel &>/dev/null; do
    sleep 2
    WAITED=$((WAITED + 2))
    [ $WAITED -ge $MAX_WAIT ] && error "PostgreSQL Orthanc não ficou pronto em ${MAX_WAIT}s"
    echo -n "."
done
echo ""
ok "PostgreSQL Orthanc pronto (${WAITED}s)"

# ── 10. Reiniciar Orthanc com PostgreSQL ──────────────────────────────────────
section "Reiniciando Orthanc com plugin PostgreSQL"
log "O Orthanc irá reindexar automaticamente todos os arquivos DICOM..."
log "Este processo pode levar vários minutos dependendo do volume de dados."
log "Arquivos DICOM a reindexar: ${DICOM_COUNT}"

cd docker
$COMPOSE up -d orthanc
cd "$PROJECT_DIR"

# Aguardar Orthanc inicializar
log "Aguardando Orthanc inicializar (pode demorar para reindexar)..."
MAX_WAIT=300
WAITED=0
until curl -sf --max-time 5 \
    -u "${ORTHANC_USERNAME}:${ORTHANC_PASSWORD}" \
    http://localhost:8042/system &>/dev/null; do
    sleep 5
    WAITED=$((WAITED + 5))
    [ $WAITED -ge $MAX_WAIT ] && error "Orthanc não ficou pronto em ${MAX_WAIT}s — verifique os logs: docker logs voxelpacs-orthanc"
    echo -n "."
done
echo ""
ok "Orthanc respondendo (${WAITED}s)"

# ── 11. Validar índice PostgreSQL ─────────────────────────────────────────────
section "Validando índice PostgreSQL"

# Verificar se o Orthanc está usando PostgreSQL
SYSTEM_INFO=$(curl -sf --max-time 10 \
    -u "${ORTHANC_USERNAME}:${ORTHANC_PASSWORD}" \
    http://localhost:8042/system 2>/dev/null || echo "{}")

# Contar estudos no Orthanc
STUDY_COUNT=$(curl -sf --max-time 10 \
    -u "${ORTHANC_USERNAME}:${ORTHANC_PASSWORD}" \
    http://localhost:8042/statistics 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('CountStudies',0))" 2>/dev/null || echo "?")

ok "Orthanc respondendo via HTTP"
log "Estudos indexados no PostgreSQL: ${STUDY_COUNT}"

# Verificar tabelas no PostgreSQL
PG_TABLES=$(docker exec voxelpacs-postgres-orthanc \
    psql -U orthanc_user -d orthanc_voxel -t \
    -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public'" \
    2>/dev/null | tr -d ' ' || echo "0")
log "Tabelas no PostgreSQL Orthanc: ${PG_TABLES}"

if [ "${PG_TABLES:-0}" -gt 0 ]; then
    ok "Índice PostgreSQL criado com ${PG_TABLES} tabelas"
else
    warn "Nenhuma tabela encontrada no PostgreSQL — verifique os logs do Orthanc"
fi

# ── 12. Healthcheck final ─────────────────────────────────────────────────────
section "Healthcheck final"
bash scripts/healthcheck.sh || true

# ── Resultado final ───────────────────────────────────────────────────────────
section "Migração concluída!"
echo -e "${GREEN}${BOLD}"
echo "  ✅ Migração SQLite → PostgreSQL concluída!"
echo ""
echo "  📊 Resumo:"
echo "     Estudos indexados: ${STUDY_COUNT}"
echo "     Tabelas PostgreSQL: ${PG_TABLES}"
echo "     Backup SQLite: ${BACKUP_SQLITE}/"
echo ""
echo "  🔄 Rollback (se necessário):"
echo "     1. Parar Orthanc: docker compose -f docker/docker-compose.yml stop orthanc"
echo "     2. Remover postgresql.json do volume"
echo "     3. Restaurar SQLite: cp ${BACKUP_SQLITE}/orthanc_pre_migration_${TIMESTAMP}.db storage/dicom/orthanc.db"
echo "     4. Reiniciar Orthanc"
echo ""
echo "  📋 Próximos passos:"
echo "     - Monitorar logs: docker logs -f voxelpacs-orthanc"
echo "     - Verificar saúde: bash scripts/healthcheck.sh"
echo "     - Backup regular: bash scripts/backup.sh --db"
echo -e "${NC}"
