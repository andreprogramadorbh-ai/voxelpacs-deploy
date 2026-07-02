#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/install-ohif.sh
#
# Gera config/ohif/app-config.js compatível com OHIF v3 (ohif/app:v3.12.5)
# DEVE ser executado ANTES de subir o Docker Compose
#
# FORMATO OHIF v3:
#   - Usa `dataSources` com `namespace` e `configuration`
#   - NÃO usa `servers: { dicomWeb: [...] }` (formato v2 — causa erro:
#     "appConfig.extensions is not iterable")
#   - extensions: [] e modes: [] = OHIF carrega os defaults da imagem
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
DOMAIN_VAL="${DOMAIN}"
QIDO_ROOT_VAL="${QIDO_ROOT:-/dicom-web}"
WADO_ROOT_VAL="${WADO_ROOT:-/dicom-web}"
WADO_URI_ROOT_VAL="${WADO_URI_ROOT:-/wado}"

# Construir URLs absolutas para o proxy Nginx
QIDO_URL="https://${DOMAIN_VAL}${QIDO_ROOT_VAL}"
WADO_URL="https://${DOMAIN_VAL}${WADO_ROOT_VAL}"
WADO_URI_URL="https://${DOMAIN_VAL}${WADO_URI_ROOT_VAL}"

# ── Criar diretórios necessários ──────────────────────────────────────────────
mkdir -p config/ohif/logo

# ── Gerar app-config.js em config/ohif/ ──────────────────────────────────────
# FORMATO OHIF v3 — dataSources com namespace
# NÃO usar servers.dicomWeb (v2) — causa "appConfig.extensions is not iterable"
APP_CONFIG_PATH="config/ohif/app-config.js"

cat > "$APP_CONFIG_PATH" << APPCONFIG
// =============================================================================
// VOXEL PACS — app-config.js
// Compatível com: ohif/app:v3.12.5 (OHIF Viewer v3)
// Gerado por:     scripts/install-ohif.sh em $(date '+%Y-%m-%d %H:%M:%S')
//
// IMPORTANTE: Formato OHIF v3 com dataSources.
// O formato antigo servers.dicomWeb (v2) causa:
//   "appConfig.extensions is not iterable"
//
// Arquitetura:
//   OHIF → https://${DOMAIN_VAL} → Nginx proxy → Orthanc remoto
// =============================================================================

/** @type {AppTypes.Config} */
window.config = {
  routerBasename: '/',

  // extensions: [] e modes: [] = OHIF carrega os defaults embutidos na imagem
  // NÃO preencher manualmente para evitar erros de compatibilidade
  extensions: [],
  modes: [],

  showStudyList: true,
  showLoadingIndicator: true,
  showCPUFallbackMessage: true,
  showWarningMessageForCrossOrigin: false,
  showErrorDetails: 'dev',
  groupEnabledModesFirst: true,
  maxNumberOfWebWorkers: 3,

  // ---------------------------------------------------------------------------
  // Data Source — OHIF v3
  // Substitui o formato servers.dicomWeb da v2
  // ---------------------------------------------------------------------------
  defaultDataSourceName: 'voxelpacs',

  dataSources: [
    {
      namespace: '@ohif/extension-default.dataSourcesModule.dicomweb',
      sourceName: 'voxelpacs',
      configuration: {
        friendlyName: '${OHIF_NAME_VAL}',
        name: 'voxelpacs',

        // QIDO-RS: busca de estudos, séries e instâncias
        qidoRoot: '${QIDO_URL}',

        // WADO-RS: recuperação de imagens e metadados (multipart)
        wadoRoot: '${WADO_URL}',

        // WADO-URI: recuperação de imagens (single part)
        wadoUriRoot: '${WADO_URI_URL}',

        // Capacidades do Orthanc
        qidoSupportsIncludeField: true,
        supportsReject: true,
        supportsStow: false,
        supportsFuzzyMatching: true,
        supportsWildcard: true,

        // Renderização
        imageRendering: 'wadors',
        thumbnailRendering: 'wadors',

        // Performance
        enableStudyLazyLoad: true,
        omitQuotationForMultipartRequest: true,

        // BulkData — necessário para Orthanc com proxy reverso
        bulkDataURI: {
          enabled: true,
          relativeResolution: 'series',
        },
      },
    },
  ],

  // ---------------------------------------------------------------------------
  // Identidade visual VOXEL PACS
  // ---------------------------------------------------------------------------
  whiteLabeling: {
    createLogoComponentFn: function (React) {
      return React.createElement(
        'a',
        {
          href: '/',
          target: '_self',
          rel: 'noopener noreferrer',
          style: { display: 'flex', alignItems: 'center' },
        },
        React.createElement('img', {
          src: '/assets/logo/logo-voxel-pacs.png',
          alt: '${OHIF_NAME_VAL}',
          style: { height: '30px', objectFit: 'contain' },
        })
      );
    },
  },
};
APPCONFIG

ok "app-config.js gerado em: ${APP_CONFIG_PATH}"
ok "  → Formato:     OHIF v3 (dataSources)"
ok "  → OHIF:        ${OHIF_NAME_VAL}"
ok "  → qidoRoot:    ${QIDO_URL}"
ok "  → wadoRoot:    ${WADO_URL}"
ok "  → wadoUriRoot: ${WADO_URI_URL}"

# ── Validações ────────────────────────────────────────────────────────────────
[ ! -f "$APP_CONFIG_PATH" ] && \
    error "Falha ao gerar ${APP_CONFIG_PATH}. Verifique permissões de escrita."

grep -q "window.config" "$APP_CONFIG_PATH" || \
    error "app-config.js inválido: sem window.config"

grep -q "dataSources" "$APP_CONFIG_PATH" || \
    error "app-config.js inválido: sem dataSources (formato OHIF v3 obrigatório)"

grep -q "servers" "$APP_CONFIG_PATH" && \
    warn "ATENÇÃO: app-config.js contém 'servers' (formato v2 depreciado). Verifique o arquivo."

ok "app-config.js validado. Pronto para subir o Docker Compose."
