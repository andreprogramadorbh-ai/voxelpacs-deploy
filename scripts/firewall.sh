#!/usr/bin/env bash
# VOXEL PACS — Configura UFW: abre 22, 80, 443. Bloqueia 8042 e 3000 externamente.
set -euo pipefail
if ! command -v ufw &>/dev/null; then
    apt-get install -y -qq ufw
fi
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp   comment 'SSH'
ufw allow 80/tcp   comment 'HTTP'
ufw allow 443/tcp  comment 'HTTPS'
ufw deny 8042/tcp  comment 'Orthanc - apenas interno'
ufw deny 3000/tcp  comment 'OHIF - apenas interno'
ufw --force enable
echo "  ✔ Firewall configurado. Portas abertas: 22, 80, 443"
ufw status
