/**
 * VOXEL PACS — OHIF Viewer v3 — Configuração de Produção
 * =========================================================
 * Servidor DICOM : https://dicom.voxelpacs.com.br  (Nginx → Orthanc)
 * Viewer         : https://view.voxelpacs.com.br
 * ERP            : https://server.voxelpacs.com.br
 *
 * Autenticação: o Nginx em dicom.voxelpacs.com.br injeta o header
 * "Authorization: Basic ..." via proxy_set_header antes de encaminhar
 * ao Orthanc. O OHIF NÃO deve enviar credenciais — o browser bloquearia
 * o header Authorization em requisições CORS cross-origin.
 *
 * Cornerstone3D: habilitado via @ohif/extension-cornerstone (padrão no OHIF v3)
 * para renderização volumétrica MPR/3D de séries CT/MR.
 */
window.config = {
  // ── Roteamento ─────────────────────────────────────────────────────────────
  routerBasename: '/',

  // ── Extensions e Modes: vazios = OHIF carrega os defaults ──────────────────
  // Inclui automaticamente: @ohif/extension-cornerstone (Cornerstone3D),
  // @ohif/extension-measurement-tracking, @ohif/extension-dicom-seg, etc.
  extensions: [],
  modes: [],

  // ── Fonte de dados padrão ──────────────────────────────────────────────────
  defaultDataSourceName: 'voxelpacs',

  // ── Banner "uso experimental" ──────────────────────────────────────────────
  // 'never' = nunca exibe o aviso de uso experimental
  investigationalUseDialog: { option: 'never' },

  // ── Configurações gerais ───────────────────────────────────────────────────
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

  // ── Data Source: DICOMweb → Nginx → Orthanc ────────────────────────────────
  dataSources: [
    {
      namespace: '@ohif/extension-default.dataSourcesModule.dicomweb',
      sourceName: 'voxelpacs',
      configuration: {
        friendlyName: 'VOXEL PACS',
        name: 'voxelpacs',

        // Endpoints DICOMweb via Nginx (sem credenciais — Nginx injeta auth)
        qidoRoot:    'https://dicom.voxelpacs.com.br/dicom-web',
        wadoRoot:    'https://dicom.voxelpacs.com.br/dicom-web',
        wadoUriRoot: 'https://dicom.voxelpacs.com.br/wado',

        // SEM requestOptions.auth — o Nginx proxy já autentica com o Orthanc
        // Enviar credentials do browser causaria conflito de header e bloqueio CORS
        requestOptions: {},

        // Otimizações de performance
        enableStudyLazyLoad: true,
        qidoSupportsIncludeField: true,
        supportsReject: false,
        supportsFuzzyMatching: true,
        supportsWildcard: true,
        imageRendering: 'wadors',
        thumbnailRendering: 'wadors',
        omitQuotationForMultipartRequest: true,

        // BulkData URI para carregamento eficiente de pixel data
        bulkDataURI: {
          enabled: true,
          relativeResolution: 'series',
        },
      },
    },
  ],

  // ── White Labeling: Branding VOXEL PACS ────────────────────────────────────
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
              fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
            },
          },
          'VOXEL PACS'
        )
      );
    },
  },

  // ── Customization Service ──────────────────────────────────────────────────
  customizationService: [
    {
      'ohif.appTitle': { value: 'VOXEL PACS — Viewer DICOM' },
    },
  ],
};
