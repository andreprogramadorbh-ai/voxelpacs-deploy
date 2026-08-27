#!/usr/bin/env bash
# Restauração segregada por tenant. Nunca restaura sobre runtime ativo.
set -euo pipefail

usage() {
  cat <<'EOF'
Uso: restore-tenant.sh --tenant <slug> --snapshot <id> --target <diretorio-vazio>

A restauração não inicia Orthanc, PostgreSQL ou rotas de gateway. O alvo deve ser
um diretório novo fora de /var/lib/orthanc e /etc/voxelpacs para validação isolada.
EOF
}

TENANT=""
SNAPSHOT=""
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant) TENANT="${2:-}"; shift 2 ;;
    --snapshot) SNAPSHOT="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Argumento inválido: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ $(id -u) -eq 0 ]] || { echo "Execute como root" >&2; exit 1; }
[[ "$TENANT" =~ ^[a-z][a-z0-9-]{1,30}$ ]] || { echo "Tenant inválido" >&2; exit 2; }
[[ "$SNAPSHOT" =~ ^[a-f0-9]{8,64}$ ]] || { echo "Snapshot inválido" >&2; exit 2; }
[[ -n "$TARGET" && "$TARGET" == /* ]] || { echo "Informe um diretório absoluto" >&2; exit 2; }
case "$TARGET" in
  /var/lib/orthanc|/var/lib/orthanc/*|/etc/voxelpacs|/etc/voxelpacs/*)
    echo "Recusado: o alvo não pode ser um diretório de runtime" >&2; exit 2 ;;
esac
[[ ! -e "$TARGET" ]] || { echo "Recusado: o alvo já existe" >&2; exit 2; }

COMMON_ENV=/etc/voxelpacs-backup/common.env
TENANT_ENV="/etc/voxelpacs-backup/tenants/${TENANT}.env"
for REQUIRED in "$COMMON_ENV" "$TENANT_ENV"; do
  [[ -f "$REQUIRED" ]] || { echo "Pré-requisito ausente: $REQUIRED" >&2; exit 1; }
done
command -v restic >/dev/null || { echo "restic não instalado" >&2; exit 1; }
set -a
. "$COMMON_ENV"
. "$TENANT_ENV"
set +a
[[ "${BACKUP_ENABLED:-false}" == "true" ]] || { echo "Restauração bloqueada: backup do tenant não está habilitado" >&2; exit 1; }
[[ -n "${RESTIC_REPOSITORY_BASE:-}" && -n "${BACKUP_NAMESPACE:-}" && -f "${RESTIC_PASSWORD_FILE:-}" ]] || { echo "Configuração Restic incompleta" >&2; exit 1; }
[[ "$BACKUP_NAMESPACE" == "$TENANT" ]] || { echo "Namespace de backup deve coincidir com o tenant" >&2; exit 1; }
export RESTIC_REPOSITORY="${RESTIC_REPOSITORY_BASE%/}/${BACKUP_NAMESPACE}"
export RESTIC_CACHE_DIR="${RESTIC_CACHE_DIR:-/var/cache/voxelpacs/restic}"
install -d -m 0700 "$RESTIC_CACHE_DIR"
# Manter compatibilidade com o endpoint S3 do Object Storage Hetzner.
restic_s3() { restic -o s3.bucket-lookup=path "$@"; }

# Confirma que o snapshot pertence ao tenant. Não permite recuperação cruzada.
restic_s3 snapshots "$SNAPSHOT" --json | grep -Fq "\"tenant:${TENANT}\"" || {
  echo "Recusado: snapshot não pertence ao tenant solicitado" >&2
  exit 1
}

umask 077
mkdir -p "$TARGET"
trap 'rm -rf "$TARGET"' ERR
restic_s3 restore "$SNAPSHOT" --target "$TARGET"

INDEX_COUNT=$(find "$TARGET" -name orthanc-index.dump -type f | wc -l)
DICOM_ROOT_COUNT=$(find "$TARGET" -type d -path '*/dicom' | wc -l)
[[ "$INDEX_COUNT" -ge 1 && "$DICOM_ROOT_COUNT" -ge 1 ]] || {
  echo "Restauração incompleta: índice ou diretório de objetos ausente" >&2
  exit 1
}
trap - ERR
printf 'restore_completed tenant=%s snapshot=%s target=%s timestamp=%s\n' "$TENANT" "$SNAPSHOT" "$TARGET" "$(date --iso-8601=seconds)"
