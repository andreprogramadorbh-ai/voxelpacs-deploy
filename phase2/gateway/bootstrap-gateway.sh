#!/usr/bin/env bash
# Executar como root apenas na VM gateway-dicom-01 recém-criada.
# Este bootstrap não abre a porta DICOM e não cria peers WireGuard de produção.
set -euo pipefail

umask 077
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg ufw wireguard-tools docker.io docker-compose-v2
systemctl enable --now docker

install -d -m 0750 -o root -g root /opt/voxelpacs/gateway
install -d -m 0755 -o root -g root /etc/voxelpacs-gateway
install -d -m 0750 -o root -g root /etc/voxelpacs-gateway/tls
install -d -m 0750 -o root -g root /var/log/voxelpacs-gateway
install -d -m 0700 -o root -g root /etc/wireguard

# Firewall fechado por padrão. A porta WireGuard só será liberada ao cadastrar o peer A.
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH administracao'
ufw --force enable

# Serviço de composição; a rota de tenant permanece disabled no arquivo inicial.
cat > /etc/systemd/system/voxelpacs-dicom-gateway.service <<'EOF'
[Unit]
Description=VOXEL PACS DICOM Gateway
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/voxelpacs/gateway
EnvironmentFile=-/etc/voxelpacs-gateway/gateway.env
ExecStart=/usr/bin/docker compose --project-name voxelpacs-gateway up -d --build --remove-orphans
ExecStop=/usr/bin/docker compose --project-name voxelpacs-gateway down
TimeoutStartSec=180

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

echo 'BOOTSTRAP_GATEWAY_OK'
