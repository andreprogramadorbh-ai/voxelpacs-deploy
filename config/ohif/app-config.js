/**
 * VOXEL PACS — OHIF Viewer v3 — Configuração de Produção
 * =========================================================
 * Servidor DICOM : https://view.voxelpacs.com.br/dicom-web  (Nginx → Orthanc)
 * Viewer         : https://view.voxelpacs.com.br
 * ERP            : https://server.voxelpacs.com.br
 *
 * Autenticação: o Nginx em view.voxelpacs.com.br injeta o header
 * Authorization: Basic ... via proxy_set_header antes de encaminhar ao Orthanc.
 * O OHIF NÃO deve enviar credenciais — o browser bloquearia o header
 * Authorization em requisições CORS cross-origin (causa da tela preta).
 *
 * Cornerstone3D: habilitado via @ohif/extension-cornerstone (padrão OHIF v3)
 * extensions e modes vazios = OHIF carrega todos os defaults incluindo Cornerstone3D.
 */
window.config = {
  routerBasename: '/',

  // extensions e modes VAZIOS = OHIF carrega os defaults (inclui Cornerstone3D)
  // NÃO preencher — evita o erro appConfig.extensions is not iterable
  extensions: [],
  modes: [],

  defaultDataSourceName: 'voxelpacs',

  // Remove o banner de uso experimental
  investigationalUseDialog: { option: 'never' },

  showStudyList: true,
  maxNumberOfWebWorkers: 4,
  showLoadingIndicator: true,
  supportsWildcard: true,
  autoPlayCine: false,
  showPatientInfo: 'visible',
  useNorm16Texture: false,
  useSharedArrayBuffer: 'AUTO',

  maxNumRequests: {
    interaction: 100,
    thumbnail: 5,
    prefetch: 25,
  },

  dataSources: [
    {
      namespace: '@ohif/extension-default.dataSourcesModule.dicomweb',
      sourceName: 'voxelpacs',
      configuration: {
        friendlyName: 'VOXEL PACS',
        name: 'voxelpacs',

        // DICOMweb via Nginx proxy em view.voxelpacs.com.br
        // O Nginx injeta proxy_set_header Authorization automaticamente
        // NÃO enviar requestOptions.auth — o browser bloqueia Authorization em CORS
        qidoRoot:    'https://view.voxelpacs.com.br/dicom-web',
        wadoRoot:    'https://view.voxelpacs.com.br/dicom-web',
        wadoUriRoot: 'https://view.voxelpacs.com.br/wado',

        // SEM auth — Nginx injeta a autenticação via proxy_set_header
        requestOptions: {},

        enableStudyLazyLoad: true,
        qidoSupportsIncludeField: true,
        supportsReject: false,
        supportsFuzzyMatching: true,
        supportsWildcard: true,
        imageRendering: 'wadors',
        thumbnailRendering: 'wadors',
        omitQuotationForMultipartRequest: true,

        bulkDataURI: {
          enabled: true,
          relativeResolution: 'series',
        },
      },
    },
  ],

  whiteLabeling: {
    createLogoComponentFn: function (React) {
      return React.createElement(
        'a',
        {
          href: 'https://server.voxelpacs.com.br/estudos',
          title: 'Voltar para a Worklist',
          style: {
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            textDecoration: 'none',
          },
        },
        React.createElement('img', {
          src: '/assets/logo/logo-voxel-pacs.png',
          alt: 'VOXEL PACS',
          style: { height: '30px', objectFit: 'contain' },
          onError: function (e) { e.target.style.display = 'none'; },
        }),
        React.createElement(
          'span',
          {
            style: {
              color: '#ffffff',
              fontWeight: '700',
              fontSize: '16px',
              letterSpacing: '0.5px',
              fontFamily: '-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif',
            },
          },
          'VOXEL PACS'
        )
      );
    },
  },

  customizationService: [
    {
      'ohif.appTitle': { value: 'VOXEL PACS — Viewer DICOM' },
    },
  ],
};
