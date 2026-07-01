#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — deploy.sh
# Alias para install.sh — ponto de entrada alternativo para o deploy
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[VOXEL] Iniciando deploy via deploy.sh → install.sh"
bash install.sh "$@"
