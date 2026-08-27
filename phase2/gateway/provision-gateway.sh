#!/usr/bin/env bash
# Executar como root em gateway-dicom-01, após copiar /root/phase2-gateway.
set -euo pipefail

SOURCE=/root/phase2-gateway
TARGET=/opt/voxelpacs/gateway
GATEWAY_PRIVATE_IP=10.0.0.4
ADMIN_USER=voxelpacs-admin
ADMIN_PUBLIC_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAASVirz0b4wLusi0Bcrt9hd3Q3KuVwsAotQlwKrEtOI voxelpacs-hml'

bash "${SOURCE}/bootstrap-gateway.sh"
install -d -m 0750 -o root -g root "${TARGET}"
cp -a "${SOURCE}/." "${TARGET}/"
rm -rf "${TARGET}/__pycache__"
find "${TARGET}" -type f -name '*.pyc' -delete
chmod 0750 "${TARGET}/bootstrap-gateway.sh" "${TARGET}/provision-gateway.sh"

install -d -m 0755 -o root -g root /etc/voxelpacs-gateway
install -d -m 0750 -o root -g root /var/log/voxelpacs-gateway
cp "${TARGET}/config/tenants.example.yaml" /etc/voxelpacs-gateway/tenants.yaml
# O arquivo contém somente política de rede e AEs; chaves/certificados ficam em diretórios root-only.
chmod 0644 /etc/voxelpacs-gateway/tenants.yaml
cat > /etc/voxelpacs-gateway/gateway.env <<EOF
GATEWAY_PRIVATE_IP=${GATEWAY_PRIVATE_IP}
EOF
chmod 0600 /etc/voxelpacs-gateway/gateway.env

# Gera somente a chave do gateway. O peer WireGuard do Cliente A ainda não existe.
umask 077
if [ ! -f /etc/wireguard/gateway.key ]; then
  wg genkey | tee /etc/wireguard/gateway.key | wg pubkey > /etc/wireguard/gateway.pub
fi
GATEWAY_WG_PRIVATE_KEY="$(cat /etc/wireguard/gateway.key)"
sed "s|__GATEWAY_WIREGUARD_PRIVATE_KEY__|${GATEWAY_WG_PRIVATE_KEY}|" \
  "${TARGET}/wireguard/wg0-cliente-a.template.conf" > /etc/wireguard/wg0.conf.pending
chmod 0600 /etc/wireguard/gateway.key /etc/wireguard/gateway.pub /etc/wireguard/wg0.conf.pending

# Conta administrativa individual do responsável e SSH somente por chave.
id "${ADMIN_USER}" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash --groups sudo "${ADMIN_USER}"
install -d -m 0700 -o "${ADMIN_USER}" -g "${ADMIN_USER}" "/home/${ADMIN_USER}/.ssh"
printf '%s\n' "${ADMIN_PUBLIC_KEY}" > "/home/${ADMIN_USER}/.ssh/authorized_keys"
chown "${ADMIN_USER}:${ADMIN_USER}" "/home/${ADMIN_USER}/.ssh/authorized_keys"
chmod 0600 "/home/${ADMIN_USER}/.ssh/authorized_keys"
cat > /etc/ssh/sshd_config.d/90-voxelpacs-gateway.conf <<'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
X11Forwarding no
AllowTcpForwarding no
EOF
sshd -t
systemctl reload ssh

# Inicializa o gateway com zero rotas habilitadas; UFW não libera DICOM nem WireGuard nesta etapa.
systemctl enable --now voxelpacs-dicom-gateway
systemctl is-active --quiet voxelpacs-dicom-gateway
for attempt in $(seq 1 18); do
  STATUS="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' voxelpacs-dicom-gateway 2>/dev/null || true)"
  [ "$STATUS" = "healthy" ] && break
  sleep 5
done
[ "${STATUS:-}" = "healthy" ]

echo 'GATEWAY_PROVISIONED_NO_TENANT_ROUTE'
