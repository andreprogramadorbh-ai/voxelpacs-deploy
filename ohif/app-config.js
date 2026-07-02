// =============================================================================
// VOXEL PACS — app-config.js
// Compatível com: ohif/app:v3.12.5 (OHIF Viewer v3)
// Gerado por:     scripts/install-ohif.sh
//
// IMPORTANTE: Este arquivo usa o formato OHIF v3 com `dataSources`.
// O formato antigo `servers: { dicomWeb: [...] }` é da v2 e causa o erro:
//   "appConfig.extensions is not iterable"
//
// Arquitetura:
//   OHIF → Nginx proxy → Orthanc remoto
//   Todas as URLs apontam para https://view.voxelpacs.com.br
//   O Nginx faz proxy de /dicom-web e /wado para o Orthanc remoto
// =============================================================================

/** @type {AppTypes.Config} */
window.config = {
  // ---------------------------------------------------------------------------
  // Roteamento
  // ---------------------------------------------------------------------------
  routerBasename: '/',

  // ---------------------------------------------------------------------------
  // Extensions e Modes
  // Deixar arrays vazios = OHIF carrega os defaults embutidos na imagem.
  // NÃO preencher manualmente para evitar "appConfig.extensions is not iterable"
  // ---------------------------------------------------------------------------
  extensions: [],
  modes: [],

  // ---------------------------------------------------------------------------
  // Interface
  // ---------------------------------------------------------------------------
  showStudyList: true,
  showLoadingIndicator: true,
  showCPUFallbackMessage: true,
  showWarningMessageForCrossOrigin: false,
  showErrorDetails: 'dev',
  groupEnabledModesFirst: true,
  maxNumberOfWebWorkers: 3,

  // ---------------------------------------------------------------------------
  // Data Source — OHIF v3 (substitui o formato servers.dicomWeb da v2)
  // ---------------------------------------------------------------------------
  defaultDataSourceName: 'voxelpacs',

  dataSources: [
    {
      // Namespace obrigatório para DICOMweb no OHIF v3
      namespace: '@ohif/extension-default.dataSourcesModule.dicomweb',
      sourceName: 'voxelpacs',
      configuration: {
        friendlyName: 'VOXEL PACS',
        name: 'voxelpacs',

        // QIDO-RS: busca de estudos, séries e instâncias
        qidoRoot: 'https://view.voxelpacs.com.br/dicom-web',

        // WADO-RS: recuperação de imagens e metadados (multipart)
        wadoRoot: 'https://view.voxelpacs.com.br/dicom-web',

        // WADO-URI: recuperação de imagens (single part, compatibilidade)
        wadoUriRoot: 'https://view.voxelpacs.com.br/wado',

        // Capacidades do servidor Orthanc
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
          alt: 'VOXEL PACS',
          style: { height: '30px', objectFit: 'contain' },
        })
      );
    },
  },
};
