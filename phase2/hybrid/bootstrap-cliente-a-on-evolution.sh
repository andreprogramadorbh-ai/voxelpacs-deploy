#!/usr/bin/env bash
# Bootstrap da célula Cliente A no host híbrido evolution-api.
# Não altera o Orthanc de teste existente, não aceita emissor externo e não migra estudos.
set -euo pipefail

TENANT=cliente-a
HOST_PRIVATE_IP=10.0.0.3
GATEWAY_PRIVATE_IP=10.0.0.4
API_PRIVATE_IP=10.0.0.2
DICOM_PORT=4244
DICOMWEB_PORT=8044
BASE=/opt/voxelpacs/phase2/hybrid/compose/${TENANT}
CONFIG=/etc/voxelpacs/tenants/${TENANT}
DATA=/var/lib/orthanc/tenants/${TENANT}
ENV_FILE=${CONFIG}/tenant.env

if [[ $(id -u) -ne 0 ]]; then
  echo "Execute como root" >&2
  exit 1
fi

# A salvaguarda impede uso do diretório do Orthanc de teste como volume do tenant.
test -d /var/lib/orthanc/db-v6
install -d -m 0750 -o root -g root "${CONFIG}" "${DATA}/dicom" "${DATA}/postgres"
install -d -m 0750 -o root -g root /var/backups/voxelpacs/phase2

if [[ ! -f "${ENV_FILE}" ]]; then
  umask 077
  cat > "${ENV_FILE}" <<EOF
POSTGRES_DB=orthanc_cliente_a
POSTGRES_USER=orthanc_cliente_a
POSTGRES_PASSWORD=$(openssl rand -base64 36 | tr -d '\n')
ORTHANC_USER=tenant_a_api
ORTHANC_PASSWORD=$(openssl rand -base64 36 | tr -d '\n')
TENANT_DATA_ROOT=${DATA}
TENANT_CONFIG_ROOT=${CONFIG}
HOST_PRIVATE_IP=${HOST_PRIVATE_IP}
DICOM_PORT=${DICOM_PORT}
DICOMWEB_PORT=${DICOMWEB_PORT}
EOF
  chmod 0600 "${ENV_FILE}"
fi

# Configurações são copiadas uma única vez; segredos são extraídos exclusivamente do env root-only.
cp --update=none "${BASE}/orthanc.json.template" "${CONFIG}/orthanc.json"
cat > "${CONFIG}/postgresql.json" <<'EOF'
{
  "PostgreSQL": {
    "EnableIndex": true,
    "EnableStorage": false,
    "Host": "postgres",
    "Port": 5432,
    "Database": "orthanc_cliente_a",
    "Username": "orthanc_cliente_a",
    "Password": "__POSTGRES_PASSWORD__"
  }
}
EOF
# A imagem processa os arquivos de configuração no diretório; substituição ocorre apenas localmente.
. "${ENV_FILE}"
sed -i "s|__POSTGRES_PASSWORD__|${POSTGRES_PASSWORD//|/\\|}|" "${CONFIG}/postgresql.json"
cat > "${CONFIG}/credentials.json" <<EOF
{
  "RegisteredUsers": {
    "${ORTHANC_USER}": "${ORTHANC_PASSWORD}"
  }
}
EOF
# O processo da imagem oficial roda como UID/GID 999. Ele recebe somente leitura
# dos arquivos montados; o diretório e tenant.env continuam restritos ao root.
chown 999:999 "${CONFIG}/credentials.json" "${CONFIG}/postgresql.json" "${CONFIG}/orthanc.json"
chmod 0400 "${CONFIG}/credentials.json" "${CONFIG}/postgresql.json" "${CONFIG}/orthanc.json"

# Permite somente gateway->DICOM e API->DICOMweb na rede privada.
ufw allow in on enp7s0 from "${GATEWAY_PRIVATE_IP}" to "${HOST_PRIVATE_IP}" port "${DICOM_PORT}" proto tcp comment 'VOXEL Cliente A gateway DICOM'
ufw allow in on enp7s0 from "${API_PRIVATE_IP}" to "${HOST_PRIVATE_IP}" port "${DICOMWEB_PORT}" proto tcp comment 'VOXEL Cliente A API DICOMweb'

cd "${BASE}"
set -a; . "${ENV_FILE}"; set +a
docker-compose --env-file "${ENV_FILE}" -p voxelpacs-cliente-a up -d

echo "CLIENTE_A_BOOTSTRAPPED"
echo "DICOM privado: ${HOST_PRIVATE_IP}:${DICOM_PORT} (somente gateway)"
echo "DICOMweb privado: ${HOST_PRIVATE_IP}:${DICOMWEB_PORT} (somente API)"
