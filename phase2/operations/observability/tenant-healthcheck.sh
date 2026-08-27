#!/usr/bin/env bash
# Métricas técnicas por tenant; não lê nem lista objetos DICOM.
set -euo pipefail

TENANT="${1:-}"
[[ "$TENANT" =~ ^[a-z][a-z0-9-]{1,30}$ ]] || { echo "Uso: tenant-healthcheck.sh <tenant>" >&2; exit 2; }
[[ $(id -u) -eq 0 ]] || { echo "Execute como root" >&2; exit 1; }

ENV_FILE="/etc/voxelpacs/tenants/${TENANT}/tenant.env"
COMPOSE_FILE="/opt/voxelpacs/phase2/hybrid/tenants/${TENANT}/docker-compose.yml"
DATA_ROOT="/var/lib/orthanc/tenants/${TENANT}"
[[ -f "$ENV_FILE" && -f "$COMPOSE_FILE" && -d "$DATA_ROOT" ]] || { echo "Célula não provisionada: ${TENANT}" >&2; exit 1; }
set -a; . "$ENV_FILE"; set +a

ORTHANC_ID=$(docker compose --env-file "$ENV_FILE" -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE" ps -q orthanc)
POSTGRES_ID=$(docker compose --env-file "$ENV_FILE" -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE" ps -q postgres)
[[ -n "$ORTHANC_ID" && -n "$POSTGRES_ID" ]] || { echo "Container ausente para ${TENANT}" >&2; exit 1; }

health() {
  docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1"
}
ORTHANC_HEALTH=$(health "$ORTHANC_ID")
POSTGRES_HEALTH=$(health "$POSTGRES_ID")
DISK_USED=$(df -P "$DATA_ROOT" | awk 'NR==2 {gsub("%", "", $5); print $5}')
CONFIG_MODE=$(stat -c '%a' "$ENV_FILE")
NOW=$(date +%s)

METRICS="voxelpacs_tenant_container_healthy{tenant=\"${TENANT}\",component=\"orthanc\"} $([[ "$ORTHANC_HEALTH" == "healthy" ]] && echo 1 || echo 0)
voxelpacs_tenant_container_healthy{tenant=\"${TENANT}\",component=\"postgres\"} $([[ "$POSTGRES_HEALTH" == "healthy" ]] && echo 1 || echo 0)
voxelpacs_tenant_storage_used_percent{tenant=\"${TENANT}\"} ${DISK_USED}
voxelpacs_tenant_config_private{tenant=\"${TENANT}\"} $([[ "$CONFIG_MODE" -le 600 ]] && echo 1 || echo 0)
voxelpacs_tenant_healthcheck_timestamp_seconds{tenant=\"${TENANT}\"} ${NOW}
"

COLLECTOR_DIR=/var/lib/node_exporter/textfile_collector
if [[ -d "$COLLECTOR_DIR" ]]; then
  TMP=$(mktemp "$COLLECTOR_DIR/.voxelpacs-${TENANT}.XXXXXX")
  printf '%s' "$METRICS" > "$TMP"
  chmod 0644 "$TMP"
  mv "$TMP" "$COLLECTOR_DIR/voxelpacs-${TENANT}.prom"
else
  printf '%s' "$METRICS"
fi

[[ "$ORTHANC_HEALTH" == "healthy" && "$POSTGRES_HEALTH" == "healthy" ]] || exit 1
[[ "$DISK_USED" -lt "${ALERT_DISK_PERCENT:-70}" ]] || exit 1
[[ "$CONFIG_MODE" -le 600 ]] || exit 1
