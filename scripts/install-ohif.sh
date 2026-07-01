#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/install-ohif.sh
#
# Gera config/ohif/app-config.js dinamicamente a partir do .env
# DEVE ser executado ANTES de subir o Docker Compose
#
# Uso:
#   bash scripts/install-ohif.sh
#   (chamado automaticamente por scripts/install.sh)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()    { echo -e "${GREEN}  ✔${NC} $*"; }
warn()  { echo -e "${YELLOW}  ⚠${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Carregar .env ─────────────────────────────────────────────────────────────
[ -f ".env" ] || error ".env não encontrado. Execute: cp .env.example .env && nano .env"
source .env

# ── Validar variáveis obrigatórias ────────────────────────────────────────────
for VAR in DOMAIN ORTHANC_HOST ORTHANC_PORT; do
    VAL=$(eval echo "\$$VAR")
    [ -z "$VAL" ] && error "Variável ${VAR} não configurada no .env"
done

# ── Valores com fallback ──────────────────────────────────────────────────────
OHIF_NAME_VAL="${OHIF_NAME:-VOXEL PACS}"
QIDO_ROOT_VAL="${QIDO_ROOT:-/dicom-web}"
WADO_ROOT_VAL="${WADO_ROOT:-/dicom-web}"
WADO_URI_ROOT_VAL="${WADO_URI_ROOT:-/wado}"
DOMAIN_VAL="${DOMAIN}"

# ── Criar diretórios necessários ──────────────────────────────────────────────
mkdir -p config/ohif/logo docker

# ── Gerar app-config.js em config/ohif/ ──────────────────────────────────────
# Este é o arquivo montado como volume no container OHIF (docker-compose.yml)
APP_CONFIG_PATH="config/ohif/app-config.js"

cat > "$APP_CONFIG_PATH" << APPCONFIG
// =============================================================================
// VOXEL PACS — app-config.js
// Gerado automaticamente por scripts/install-ohif.sh
// NÃO edite este arquivo manualmente — será regenerado pelo install.sh
// Domínio: ${DOMAIN_VAL}
// =============================================================================
window.config = {
  routerBasename: '/',
  showStudyList: true,
  servers: {
    dicomWeb: [
      {
        name: '${OHIF_NAME_VAL}',
        wadoUriRoot: 'https://${DOMAIN_VAL}${WADO_URI_ROOT_VAL}',
        qidoRoot:    'https://${DOMAIN_VAL}${QIDO_ROOT_VAL}',
        wadoRoot:    'https://${DOMAIN_VAL}${WADO_ROOT_VAL}',
        qidoSupportsIncludeField: true,
        imageRendering:     'wadors',
        thumbnailRendering: 'wadors',
        enableStudyLazyLoad: true,
        supportsFuzzyMatching: true,
      },
    ],
  },
  whiteLabeling: {
    createLogoComponentFn: function (React) {
      return React.createElement('a', { href: '/', className: 'text-white' },
        React.createElement('img', {
          src: '/assets/logo/logo-voxel-pacs.png',
          alt: '${OHIF_NAME_VAL}',
          style: { height: '30px' }
        })
      );
    },
  },
};
APPCONFIG

ok "app-config.js gerado em: ${APP_CONFIG_PATH}"
ok "  → OHIF: ${OHIF_NAME_VAL}"
ok "  → QIDO: https://${DOMAIN_VAL}${QIDO_ROOT_VAL}"
ok "  → WADO: https://${DOMAIN_VAL}${WADO_ROOT_VAL}"
ok "  → WADO URI: https://${DOMAIN_VAL}${WADO_URI_ROOT_VAL}"

# ── Verificar se o arquivo foi criado corretamente ────────────────────────────
if [ ! -f "$APP_CONFIG_PATH" ]; then
    error "Falha ao gerar ${APP_CONFIG_PATH}. Verifique permissões de escrita."
fi

if ! grep -q "window.config" "$APP_CONFIG_PATH"; then
    error "app-config.js gerado parece inválido. Verifique o conteúdo em: ${APP_CONFIG_PATH}"
fi

ok "app-config.js validado. Pronto para subir o Docker Compose."
