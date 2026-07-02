/**
 * VOXEL PACS — OHIF Viewer v3 — Configuração de Produção
 * =========================================================
 * Arquitetura:
 *   view.voxelpacs.com.br  → OHIF SPA (container Docker porta 3000)
 *   dicom.voxelpacs.com.br → Orthanc DICOMweb (Nginx injeta Authorization Basic)
 *
 * CORS: dicom.conf permite Access-Control-Allow-Origin: view.voxelpacs.com.br
 * Auth: Nginx injeta proxy_set_header Authorization automaticamente
 *       O OHIF NÃO envia credenciais (browser bloquearia em CORS cross-origin)
 */
window.config = {
  routerBasename: '/',

  // extensions e modes VAZIOS = OHIF carrega os defaults (inclui Cornerstone3D)
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

        // DICOMweb via dicom.voxelpacs.com.br (Nginx → Orthanc)
        // O Nginx injeta Authorization Basic automaticamente
        // O OHIF NÃO envia auth — browser bloquearia em CORS cross-origin
        qidoRoot:    'https://dicom.voxelpacs.com.br/dicom-web',
        wadoRoot:    'https://dicom.voxelpacs.com.br/dicom-web',
        wadoUriRoot: 'https://dicom.voxelpacs.com.br/wado',

        // SEM auth — Nginx injeta via proxy_set_header Authorization
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
