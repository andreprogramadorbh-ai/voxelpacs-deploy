#!/usr/bin/env bash
# Backup tenant-scoped para a célula híbrida VOXEL PACS.
# Não registra nomes de pacientes, IDs, UIDs ou caminhos individuais de objetos.
set -euo pipefail

usage() {
  cat <<'EOF'
Uso: backup-tenant.sh --tenant <slug> [--validate-only]

Pré-requisitos root-only no host:
  /etc/voxelpacs-backup/common.env
  /etc/voxelpacs-backup/tenants/<slug>.env
  /etc/voxelpacs-backup/production-enabled  (criado apenas após aprovação explícita)
EOF
}

TENANT=""
VALIDATE_ONLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant) TENANT="${2:-}"; shift 2 ;;
    --validate-only) VALIDATE_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Argumento inválido: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ $(id -u) -eq 0 ]] || { echo "Execute como root" >&2; exit 1; }
[[ "$TENANT" =~ ^[a-z][a-z0-9-]{1,30}$ ]] || { echo "Tenant inválido" >&2; exit 2; }

COMMON_ENV=/etc/voxelpacs-backup/common.env
TENANT_ENV="/etc/voxelpacs-backup/tenants/${TENANT}.env"
TENANT_APP_ENV="/etc/voxelpacs/tenants/${TENANT}/tenant.env"
TENANT_COMPOSE="/opt/voxelpacs/phase2/hybrid/tenants/${TENANT}/docker-compose.yml"
TENANT_DATA="/var/lib/orthanc/tenants/${TENANT}"
CONFIG_ROOT="/etc/voxelpacs/tenants/${TENANT}"

for REQUIRED in "$TENANT_ENV" "$TENANT_APP_ENV" "$TENANT_COMPOSE" "$TENANT_DATA/dicom" "$CONFIG_ROOT"; do
  [[ -f "$REQUIRED" || -d "$REQUIRED" ]] || { echo "Pré-requisito ausente: $REQUIRED" >&2; exit 1; }
done

# O contrato individual é lido primeiro: backups desabilitados não devem exigir,
# carregar ou validar credenciais de Object Storage ainda não aprovadas.
set -a
. "$TENANT_ENV"
set +a
[[ "${BACKUP_ENABLED:-false}" == "true" ]] || { echo "Backup de ${TENANT} permanece desabilitado no contrato"; exit 0; }

[[ -f "$COMMON_ENV" ]] || { echo "Configuração comum de backup ausente" >&2; exit 1; }
command -v restic >/dev/null || { echo "restic não instalado" >&2; exit 1; }
command -v docker >/dev/null || { echo "Docker não instalado" >&2; exit 1; }
docker compose version >/dev/null || { echo "Docker Compose V2 é obrigatório" >&2; exit 1; }

# common.env contém referências operacionais ao bucket cifrado e à senha;
# tenant.env define um namespace próprio. Nunca exibir seus conteúdos em logs.
set -a
. "$COMMON_ENV"
. "$TENANT_APP_ENV"
set +a

[[ -n "${RESTIC_REPOSITORY_BASE:-}" && -n "${BACKUP_NAMESPACE:-}" && -n "${RESTIC_PASSWORD_FILE:-}" ]] || { echo "Configuração Restic incompleta" >&2; exit 1; }
[[ "$BACKUP_NAMESPACE" == "$TENANT" ]] || { echo "Namespace de backup deve coincidir com o tenant" >&2; exit 1; }
[[ -f "$RESTIC_PASSWORD_FILE" ]] || { echo "Arquivo de senha Restic ausente" >&2; exit 1; }
export RESTIC_REPOSITORY="${RESTIC_REPOSITORY_BASE%/}/${BACKUP_NAMESPACE}"
export RESTIC_CACHE_DIR="${RESTIC_CACHE_DIR:-/var/cache/voxelpacs/restic}"
install -d -m 0700 "$RESTIC_CACHE_DIR"
# Hetzner Object Storage é S3-compatível. Forçar path-style elimina a ambiguidade
# de descoberta de bucket e mantém a chamada compatível com o endpoint hel1.
restic_s3() { restic -o s3.bucket-lookup=path "$@"; }
[[ -n "${COMPOSE_PROJECT:-}" && -n "${POSTGRES_DB:-}" && -n "${POSTGRES_USER:-}" ]] || { echo "Ambiente da célula incompleto" >&2; exit 1; }

if [[ "$VALIDATE_ONLY" == true ]]; then
  restic_s3 snapshots --tag "tenant:${TENANT}" --quiet >/dev/null
  echo "BACKUP_TENANT_VALIDATION_OK tenant=${TENANT}"
  exit 0
fi

[[ -f /etc/voxelpacs-backup/production-enabled ]] || {
  echo "Backup produtivo bloqueado: requer marcador de aprovação explícita" >&2
  exit 0
}

LOCK_FILE="/run/lock/voxelpacs-backup-${TENANT}.lock"
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "Já existe backup em execução para ${TENANT}" >&2; exit 1; }

WORKDIR=$(mktemp -d "/var/backups/voxelpacs/${TENANT}.XXXXXX")
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT
chmod 0700 "$WORKDIR"

# O dump de índice é consistente e não exige parar o Orthanc. O arquivo temporário
# é removido mesmo em falha e nunca é emitido no journal.
docker compose --env-file "$TENANT_APP_ENV" -p "$COMPOSE_PROJECT" -f "$TENANT_COMPOSE" \
  exec -T postgres pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --compress=9 \
  > "$WORKDIR/orthanc-index.dump"
chmod 0600 "$WORKDIR/orthanc-index.dump"

restic_s3 backup --quiet --tag "tenant:${TENANT}" --tag "component:index" "$WORKDIR/orthanc-index.dump"
restic_s3 backup --quiet --tag "tenant:${TENANT}" --tag "component:objects" "$TENANT_DATA/dicom"
restic_s3 backup --quiet --tag "tenant:${TENANT}" --tag "component:config" "$CONFIG_ROOT"

# Política por tenant: esquecer snapshots vencidos exige aprovação de retenção; execute
# somente quando RETENTION_PRUNE_APPROVED=true no contrato root-only.
if [[ "${RETENTION_PRUNE_APPROVED:-false}" == "true" ]]; then
  restic_s3 forget --quiet --tag "tenant:${TENANT}" --keep-within "${RETENTION_DAYS:-30}d" --prune
fi

SNAPSHOT_ID=$(restic_s3 snapshots --tag "tenant:${TENANT}" --latest 1 --json | sed -n 's/.*"short_id":"\([a-f0-9]*\)".*/\1/p' | head -1)
printf 'backup_completed tenant=%s snapshot=%s timestamp=%s\n' "$TENANT" "${SNAPSHOT_ID:-unknown}" "$(date --iso-8601=seconds)"
