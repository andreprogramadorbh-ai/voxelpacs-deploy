/**
 * VOXEL PACS — OHIF Viewer v3 — Configuração de Produção
 * =========================================================
 * Fix Content-Type + Accept Header (v3):
 *   - Proxy Python v3 (porta 8043):
 *     1. Remove aspas do type= no Content-Type multipart do Orthanc
 *     2. Reescreve Accept header para apenas 1 valor (Orthanc 1.16 não suporta múltiplos)
 *     3. Injeta Authorization Basic automaticamente
 *   - acceptHeader: apenas transfer-syntax=1.2.840.10008.1.2.1
 *   - omitQuotationForMultipartRequest: true
 */
window.config = {
  routerBasename: '/',
  extensions: [],
  modes: [],
  defaultDataSourceName: 'voxelpacs',
  investigationalUseDialog: { option: 'never' },
  showStudyList: false,
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
  acceptHeader: [
    'multipart/related; type=application/octet-stream; transfer-syntax=1.2.840.10008.1.2.1',
  ],
  omitQuotationForMultipartRequest: true,
  dataSources: [
    {
      namespace: '@ohif/extension-default.dataSourcesModule.dicomweb',
      sourceName: 'voxelpacs',
      configuration: {
        friendlyName: 'Voxel View',
        name: 'voxelpacs',
        qidoRoot:    'https://dicom.voxelpacs.com.br/dicom-web',
        wadoRoot:    'https://dicom.voxelpacs.com.br/dicom-web',
        wadoUriRoot: 'https://dicom.voxelpacs.com.br/wado',
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
          style: { display: 'flex', alignItems: 'center', gap: '8px', textDecoration: 'none' },
        },
        React.createElement('span', {
          style: {
            color: '#ffffff',
            fontWeight: '700',
            fontSize: '16px',
            letterSpacing: '0.5px',
            fontFamily: '-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif',
          },
        }, 'VOXEL VIEW')
      );
    },
  },
  customizationService: [
    { 'ohif.appTitle': { value: 'Voxel View' } },
  ],
};
