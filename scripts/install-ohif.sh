#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/install-ohif.sh
#
# Gera config/ohif/app-config.js dinamicamente a partir do .env
# DEVE ser executado ANTES de subir o Docker Compose
#
# ARQUITETURA DO app-config.js:
#   - Usa APENAS caminhos relativos: /dicom-web e /wado
#   - NENHUM IP, porta ou domínio externo
#   - O Nginx no host faz o proxy reverso para o Orthanc remoto
#   - O OHIF nunca acessa o Orthanc diretamente
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
for VAR in DOMAIN; do
    VAL=$(eval echo "\$$VAR")
    [ -z "$VAL" ] && error "Variável ${VAR} não configurada no .env"
done

# ── Valores com fallback ──────────────────────────────────────────────────────
OHIF_NAME_VAL="${OHIF_NAME:-VOXEL PACS}"
QIDO_ROOT_VAL="${QIDO_ROOT:-/dicom-web}"
WADO_ROOT_VAL="${WADO_ROOT:-/dicom-web}"
WADO_URI_ROOT_VAL="${WADO_URI_ROOT:-/wado}"

# ── Criar diretórios necessários ──────────────────────────────────────────────
mkdir -p config/ohif/logo

# ── Gerar app-config.js em config/ohif/ ──────────────────────────────────────
# REGRA FUNDAMENTAL:
#   - Usar APENAS caminhos relativos (qidoRoot, wadoRoot, wadoUriRoot)
#   - NUNCA incluir IP, porta ou domínio externo
#   - O Nginx faz proxy: /dicom-web → Orthanc remoto
#   - O OHIF nunca acessa o Orthanc diretamente
APP_CONFIG_PATH="config/ohif/app-config.js"

cat > "$APP_CONFIG_PATH" << APPCONFIG
// =============================================================================
// VOXEL PACS — app-config.js
// Gerado automaticamente por scripts/install-ohif.sh
// NÃO edite este arquivo manualmente — será regenerado pelo install.sh
//
// ARQUITETURA:
//   - Caminhos relativos apenas (/dicom-web, /wado)
//   - Nenhum IP, porta ou domínio externo
//   - Nginx faz proxy reverso: /dicom-web → Orthanc remoto
// =============================================================================
window.config = {
  routerBasename: '/',
  showStudyList: true,
  servers: {
    dicomWeb: [
      {
        name: '${OHIF_NAME_VAL}',
        // Caminhos relativos — roteados pelo Nginx para o Orthanc remoto
        qidoRoot:    '${QIDO_ROOT_VAL}',
        wadoRoot:    '${WADO_ROOT_VAL}',
        wadoUriRoot: '${WADO_URI_ROOT_VAL}',
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
ok "  → qidoRoot:    ${QIDO_ROOT_VAL}  (relativo — via proxy Nginx)"
ok "  → wadoRoot:    ${WADO_ROOT_VAL}  (relativo — via proxy Nginx)"
ok "  → wadoUriRoot: ${WADO_URI_ROOT_VAL}  (relativo — via proxy Nginx)"

# ── Validar que o arquivo foi gerado corretamente ─────────────────────────────
if [ ! -f "$APP_CONFIG_PATH" ]; then
    error "Falha ao gerar ${APP_CONFIG_PATH}. Verifique permissões de escrita."
fi

if ! grep -q "window.config" "$APP_CONFIG_PATH"; then
    error "app-config.js gerado parece inválido (sem window.config)."
fi

# ── Validar que NÃO há IP, porta ou domínio externo no app-config.js ──────────
if grep -qE "https?://|:[0-9]{4,5}" "$APP_CONFIG_PATH"; then
    warn "ATENÇÃO: app-config.js pode conter URLs absolutas!"
    warn "Verifique o conteúdo: cat ${APP_CONFIG_PATH}"
    warn "O OHIF deve usar APENAS caminhos relativos (/dicom-web, /wado)."
fi

ok "app-config.js validado. Pronto para subir o Docker Compose."
