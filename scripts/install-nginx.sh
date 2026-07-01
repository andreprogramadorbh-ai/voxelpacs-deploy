#!/usr/bin/env bash
# VOXEL PACS — Instala Nginx (idempotente)
set -euo pipefail
if command -v nginx &>/dev/null; then
    echo "  ✔ Nginx já instalado: $(nginx -v 2>&1)"
else
    apt-get update -qq
    apt-get install -y -qq nginx
    systemctl enable nginx
    systemctl start nginx
    echo "  ✔ Nginx instalado: $(nginx -v 2>&1)"
fi
