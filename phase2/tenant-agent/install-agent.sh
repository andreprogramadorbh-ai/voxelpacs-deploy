#!/usr/bin/env bash
# Instala o agente operacional VOXEL PACS no host híbrido ou gateway.
# Uso exclusivo root. A chave HMAC é copiada de um arquivo root-only e nunca exibida.
set -euo pipefail

usage() {
  cat <<'EOF'
Uso: install-agent.sh --role <hybrid|gateway> --bind-host <IPv4> --api-source-ip <IPv4> --hmac-key-file <arquivo> [--port 8813]
EOF
}

ROLE=""
BIND_HOST=""
API_SOURCE_IP=""
HMAC_KEY_FILE=""
PORT="8813"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="${2:-}"; shift 2 ;;
    --bind-host) BIND_HOST="${2:-}"; shift 2 ;;
    --api-source-ip) API_SOURCE_IP="${2:-}"; shift 2 ;;
    --hmac-key-file) HMAC_KEY_FILE="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

[[ $(id -u) -eq 0 ]] || { echo 'Execute como root.' >&2; exit 1; }
[[ "$ROLE" =~ ^(hybrid|gateway)$ ]] || { echo 'Perfil inválido.' >&2; exit 2; }
for ip in "$BIND_HOST" "$API_SOURCE_IP"; do
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo 'IPv4 inválido.' >&2; exit 2; }
done
[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1024 && PORT <= 65535 )) || { echo 'Porta inválida.' >&2; exit 2; }
[[ -f "$HMAC_KEY_FILE" ]] || { echo 'Arquivo de chave não encontrado.' >&2; exit 2; }
[[ $(wc -c < "$HMAC_KEY_FILE") -ge 32 ]] || { echo 'Chave de serviço curta demais.' >&2; exit 2; }

SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INSTALL_DIR=/usr/local/lib/voxelpacs/tenant-agent
ETC_DIR=/etc/voxelpacs-tenant-agent
STATE_DIR=/var/lib/voxelpacs-tenant-agent/nonces
LOG_DIR=/var/log/voxelpacs
TLS_DIR=/etc/voxelpacs-tenant-agent/tls
UNIT=/etc/systemd/system/voxelpacs-tenant-agent.service

for required in "$TLS_DIR/server.crt" "$TLS_DIR/server.key" "$TLS_DIR/ca.crt"; do
  [[ -f "$required" ]] || { echo "Material mTLS interno ausente: $required" >&2; exit 1; }
done

install -d -m 0700 -o root -g root "$INSTALL_DIR" "$ETC_DIR" "$STATE_DIR" "$LOG_DIR" "$TLS_DIR"
install -m 0700 -o root -g root "$SOURCE_DIR/agent.py" "$INSTALL_DIR/agent.py"
install -m 0644 -o root -g root "$SOURCE_DIR/voxelpacs-tenant-agent.service" "$UNIT"
install -m 0600 -o root -g root "$HMAC_KEY_FILE" "$ETC_DIR/hmac.key"

cat > "$ETC_DIR/agent.env" <<EOF
AGENT_ROLE=${ROLE}
BIND_HOST=${BIND_HOST}
BIND_PORT=${PORT}
API_SOURCE_IP=${API_SOURCE_IP}
AUTH_SECRET_FILE=${ETC_DIR}/hmac.key
NONCE_DIR=${STATE_DIR}
AUDIT_LOG=${LOG_DIR}/tenant-agent.jsonl
TLS_CERT_FILE=${TLS_DIR}/server.crt
TLS_KEY_FILE=${TLS_DIR}/server.key
TLS_CLIENT_CA_FILE=${TLS_DIR}/ca.crt
WG_CLIENT_NETWORK=10.200.10.0/24
API_PRIVATE_IP=10.0.0.2
GATEWAY_PRIVATE_IP=10.0.0.4
HOST_PRIVATE_IP=10.0.0.3
HYBRID_PRIVATE_IP=10.0.0.3
EOF
if [[ "$ROLE" == hybrid ]]; then
  cat >> "$ETC_DIR/agent.env" <<'EOF'
BOOTSTRAP_SCRIPT=/opt/voxelpacs/phase2/hybrid/bootstrap-tenant.sh
BACKUP_SCRIPT=/opt/voxelpacs/phase2/operations/backup/backup-tenant.sh
EOF
else
  GATEWAY_AUDIT_LOG=$(awk -F: '/^[[:space:]]*log_file:/{gsub(/[[:space:]"'"'"'"'"'"']/, "", $2); print $2; exit}' /etc/voxelpacs-gateway/tenants.yaml)
  [[ "$GATEWAY_AUDIT_LOG" =~ ^/var/log/voxelpacs-gateway/ ]] || { echo 'Caminho de auditoria do gateway inválido.' >&2; exit 1; }
  cat >> "$ETC_DIR/agent.env" <<EOF
WG_INTERFACE=wg0
WG_CONFIG=/etc/wireguard/wg0.conf
GATEWAY_POLICY=/etc/voxelpacs-gateway/tenants.yaml
GATEWAY_APP=/opt/voxelpacs/gateway/app/gateway.py
GATEWAY_COMPOSE=/opt/voxelpacs/gateway/docker-compose.yml
GATEWAY_ENV_FILE=/etc/voxelpacs-gateway/gateway.env
GATEWAY_COMPOSE_PROJECT=voxelpacs-gateway
GATEWAY_AUDIT_LOG=${GATEWAY_AUDIT_LOG}
EOF
fi
chmod 0600 "$ETC_DIR/agent.env"

# O agente nunca fica disponível na Internet: somente a API privada pode alcançá-lo.
ufw allow in on enp7s0 from "$API_SOURCE_IP" to "$BIND_HOST" port "$PORT" proto tcp comment "VOXEL tenant agent API private" >/dev/null
systemctl daemon-reload
systemctl enable --now voxelpacs-tenant-agent.service
systemctl is-active --quiet voxelpacs-tenant-agent.service
printf 'TENANT_AGENT_INSTALL_OK role=%s bind=%s:%s source=%s\n' "$ROLE" "$BIND_HOST" "$PORT" "$API_SOURCE_IP"
