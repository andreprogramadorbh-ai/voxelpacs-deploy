#!/usr/bin/env bash
# VOXEL PACS — Instala Certbot (idempotente)
set -euo pipefail
if command -v certbot &>/dev/null; then
    echo "  ✔ Certbot já instalado: $(certbot --version)"
else
    apt-get update -qq
    apt-get install -y -qq certbot python3-certbot-nginx
    echo "  ✔ Certbot instalado: $(certbot --version)"
fi
