#!/usr/bin/env bash
# Provisiona uma célula Orthanc/PostgreSQL isolada no host híbrido.
# Por padrão, NÃO inicia containers e NÃO habilita rota no gateway.
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  bootstrap-tenant.sh --tenant <slug> --profile <vpn_mtls|vpn_only|site_router> \
    --dicom-port <porta> --dicomweb-port <porta> --backend-ae <AE> \
    --gateway-called-ae <AE> --gateway-private-ip <IPv4> --api-private-ip <IPv4> \
    --host-private-ip <IPv4> [--start]

Exemplo de homologação (não execute sem revisar o contrato do tenant):
  bootstrap-tenant.sh --tenant cliente-b --profile vpn_only --dicom-port 4245 \
    --dicomweb-port 8045 --backend-ae VOXEL_B_PACS --gateway-called-ae VOXEL_GW_B \
    --gateway-private-ip 10.0.0.4 --api-private-ip 10.0.0.2 --host-private-ip 10.0.0.3
EOF
}

TENANT=""
PROFILE=""
DICOM_PORT=""
DICOMWEB_PORT=""
BACKEND_AE=""
GATEWAY_CALLED_AE=""
GATEWAY_PRIVATE_IP=""
API_PRIVATE_IP=""
HOST_PRIVATE_IP=""
START=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant) TENANT="${2:-}"; shift 2 ;;
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --dicom-port) DICOM_PORT="${2:-}"; shift 2 ;;
    --dicomweb-port) DICOMWEB_PORT="${2:-}"; shift 2 ;;
    --backend-ae) BACKEND_AE="${2:-}"; shift 2 ;;
    --gateway-called-ae) GATEWAY_CALLED_AE="${2:-}"; shift 2 ;;
    --gateway-private-ip) GATEWAY_PRIVATE_IP="${2:-}"; shift 2 ;;
    --api-private-ip) API_PRIVATE_IP="${2:-}"; shift 2 ;;
    --host-private-ip) HOST_PRIVATE_IP="${2:-}"; shift 2 ;;
    --start) START=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Argumento inválido: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ $(id -u) -ne 0 ]]; then
  echo "Execute como root" >&2
  exit 1
fi

[[ "$TENANT" =~ ^[a-z][a-z0-9-]{1,30}$ ]] || { echo "Tenant inválido" >&2; exit 2; }
[[ "$PROFILE" =~ ^(vpn_mtls|vpn_only|site_router)$ ]] || { echo "Perfil inválido" >&2; exit 2; }
for AE in "$BACKEND_AE" "$GATEWAY_CALLED_AE"; do
  [[ "$AE" =~ ^[A-Z0-9_]{1,16}$ ]] || { echo "AE Title inválido: $AE" >&2; exit 2; }
done
for PORT in "$DICOM_PORT" "$DICOMWEB_PORT"; do
  [[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1024 && PORT <= 65535 )) || { echo "Porta inválida: $PORT" >&2; exit 2; }
done
[[ "$DICOM_PORT" != "$DICOMWEB_PORT" ]] || { echo "As portas DICOM e DICOMweb devem ser distintas" >&2; exit 2; }
for IP in "$GATEWAY_PRIVATE_IP" "$API_PRIVATE_IP" "$HOST_PRIVATE_IP"; do
  [[ "$IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "IPv4 inválido: $IP" >&2; exit 2; }
done
command -v docker >/dev/null || { echo "Docker não encontrado" >&2; exit 1; }
docker compose version >/dev/null || { echo "Docker Compose V2 é obrigatório" >&2; exit 1; }

ROOT=/opt/voxelpacs/phase2/hybrid
TEMPLATE="${ROOT}/template"
BASE="${ROOT}/tenants/${TENANT}"
CONFIG="/etc/voxelpacs/tenants/${TENANT}"
DATA="/var/lib/orthanc/tenants/${TENANT}"
ENV_FILE="${CONFIG}/tenant.env"

[[ -d "$TEMPLATE" ]] || { echo "Template ausente em ${TEMPLATE}" >&2; exit 1; }
[[ ! -e "$BASE" && ! -e "$CONFIG" && ! -e "$DATA" ]] || {
  echo "Recusado: já existe estado para ${TENANT}; não sobrescreva uma célula existente" >&2
  exit 1
}
[[ "$DATA" != "/var/lib/orthanc/db-v6" ]] || { echo "Diretório de teste não pode ser reutilizado" >&2; exit 1; }
if ss -ltnH | awk '{print $4}' | grep -Eq "(^|:)(\[?${HOST_PRIVATE_IP}\]?|0\.0\.0\.0):(${DICOM_PORT}|${DICOMWEB_PORT})$"; then
  echo "Recusado: uma porta solicitada já está em escuta" >&2
  exit 1
fi

umask 077
install -d -m 0750 -o root -g root "$BASE" "$CONFIG" "$DATA/dicom" "$DATA/postgres"
install -m 0644 "$TEMPLATE/docker-compose.yml" "$BASE/docker-compose.yml"
install -m 0644 "$TEMPLATE/Dockerfile" "$BASE/Dockerfile"

TENANT_SQL=${TENANT//-/__}
POSTGRES_DB="orthanc_${TENANT_SQL}"
POSTGRES_USER="orthanc_${TENANT_SQL}"
ORTHANC_USER="${TENANT//-/}_api"
GATEWAY_CALLING_AE="$GATEWAY_CALLED_AE"
ORTHANC_NAME="VOXEL_${TENANT//-/_}"

cat > "$ENV_FILE" <<EOF
COMPOSE_PROJECT=voxelpacs-${TENANT}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=$(openssl rand -base64 36 | tr -d '\n')
ORTHANC_USER=${ORTHANC_USER}
ORTHANC_PASSWORD=$(openssl rand -base64 36 | tr -d '\n')
TENANT_DATA_ROOT=${DATA}
TENANT_CONFIG_ROOT=${CONFIG}
HOST_PRIVATE_IP=${HOST_PRIVATE_IP}
DICOM_PORT=${DICOM_PORT}
DICOMWEB_PORT=${DICOMWEB_PORT}
POSTGRES_MAX_CONNECTIONS=30
POSTGRES_SHARED_BUFFERS=128MB
POSTGRES_CPU_LIMIT=0.50
POSTGRES_MEMORY_LIMIT=512M
ORTHANC_CPU_LIMIT=1.00
ORTHANC_MEMORY_LIMIT=1024M
TZ=America/Sao_Paulo
EOF
chmod 0600 "$ENV_FILE"

sed \
  -e "s|__ORTHANC_NAME__|${ORTHANC_NAME}|g" \
  -e "s|__BACKEND_AE__|${BACKEND_AE}|g" \
  -e "s|__GATEWAY_CALLING_AE__|${GATEWAY_CALLING_AE}|g" \
  -e "s|__GATEWAY_PRIVATE_IP__|${GATEWAY_PRIVATE_IP}|g" \
  "$TEMPLATE/orthanc.json.template" > "$CONFIG/orthanc.json"

# A célula usa PostgreSQL apenas como índice; DICOM permanece no diretório próprio do tenant.
. "$ENV_FILE"
cat > "$CONFIG/postgresql.json" <<EOF
{
  "PostgreSQL": {
    "EnableIndex": true,
    "EnableStorage": false,
    "Host": "postgres",
    "Port": 5432,
    "Database": "${POSTGRES_DB}",
    "Username": "${POSTGRES_USER}",
    "Password": "${POSTGRES_PASSWORD}",
    "Lock": true,
    "IndexConnectionsCount": 8,
    "UseDynamicConnectionPool": true,
    "TransactionMode": "ReadCommitted",
    "ApplicationName": "voxelpacs-${TENANT}"
  }
}
EOF
cat > "$CONFIG/credentials.json" <<EOF
{
  "RegisteredUsers": {
    "${ORTHANC_USER}": "${ORTHANC_PASSWORD}"
  }
}
EOF
chown 999:999 "$CONFIG/orthanc.json" "$CONFIG/postgresql.json" "$CONFIG/credentials.json"
chmod 0400 "$CONFIG/orthanc.json" "$CONFIG/postgresql.json" "$CONFIG/credentials.json"

# Valida composição antes de alterar firewall ou iniciar containers.
docker compose --env-file "$ENV_FILE" -f "$BASE/docker-compose.yml" config -q

ufw allow in on enp7s0 from "$GATEWAY_PRIVATE_IP" to "$HOST_PRIVATE_IP" port "$DICOM_PORT" proto tcp comment "VOXEL ${TENANT} gateway DICOM"
ufw allow in on enp7s0 from "$API_PRIVATE_IP" to "$HOST_PRIVATE_IP" port "$DICOMWEB_PORT" proto tcp comment "VOXEL ${TENANT} API DICOMweb"

if [[ "$START" == true ]]; then
  docker compose --env-file "$ENV_FILE" -p "voxelpacs-${TENANT}" -f "$BASE/docker-compose.yml" up -d
  echo "Célula ${TENANT} iniciada, sem rota de gateway habilitada."
else
  echo "Célula ${TENANT} preparada, mas não iniciada."
fi
cat <<EOF
TENANT_BOOTSTRAP_COMPLETE
profile=${PROFILE}
backend_ae=${BACKEND_AE}
gateway_called_ae=${GATEWAY_CALLED_AE}
dicom_private=${HOST_PRIVATE_IP}:${DICOM_PORT}
dicomweb_private=${HOST_PRIVATE_IP}:${DICOMWEB_PORT}
gateway_route=disabled
backup=not-configured
EOF
