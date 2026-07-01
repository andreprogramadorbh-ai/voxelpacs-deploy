#!/usr/bin/env bash
# VOXEL PACS — Gera app-config.js do OHIF automaticamente a partir do .env
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"
[ -f ".env" ] && source .env

OHIF_NAME_VAL="${OHIF_NAME:-VOXEL PACS}"
QIDO_ROOT_VAL="${QIDO_ROOT:-/dicom-web}"
WADO_ROOT_VAL="${WADO_ROOT:-/dicom-web}"
WADO_URI_ROOT_VAL="${WADO_URI_ROOT:-/wado}"
DOMAIN_VAL="${DOMAIN:-localhost}"

mkdir -p config/ohif docker

cat > config/ohif/app-config.js << APPCONFIG
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
        imageRendering:    'wadors',
        thumbnailRendering:'wadors',
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

# Copiar para docker/ também
cp config/ohif/app-config.js docker/app-config.js
echo "  ✔ app-config.js gerado para: https://${DOMAIN_VAL}${QIDO_ROOT_VAL}"
