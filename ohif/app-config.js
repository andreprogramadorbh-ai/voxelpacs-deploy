/**
 * VOXEL PACS — OHIF Viewer v3 — Configuração de Produção
 * =========================================================
 * Arquitetura:
 *   view.voxelpacs.com.br  → OHIF SPA (container Docker)
 *   dicom.voxelpacs.com.br → Proxy Python 8043 → Orthanc 1.12.2 + DICOMweb 1.16
 *
 * Segurança LGPD:
 *   - showStudyList: false — desabilita a lista de exames no viewer
 *   - Acesso apenas via token gerado pelo sistema PHP (server.voxelpacs.com.br)
 *   - Nginx redireciona / para server.voxelpacs.com.br/estudos
 *
 * Fix Content-Type:
 *   - Proxy Python remove aspas do type= no Content-Type multipart do Orthanc
 *   - omitQuotationForMultipartRequest: true para compatibilidade Cornerstone3D
 */
window.config = {
  routerBasename: '/',
  extensions: [],
  modes: [],
  defaultDataSourceName: 'voxelpacs',
  investigationalUseDialog: { option: 'never' },
  // LGPD: desabilitar Study List — acesso apenas via token do sistema PHP
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
        // Usar wadors para recuperar imagens via WADO-RS
        imageRendering: 'wadors',
        thumbnailRendering: 'wadors',
        // Orthanc DICOMweb 1.16 + Proxy Fix:
        // O proxy Python (porta 8043) já remove as aspas do Content-Type multipart.
        // Esta flag instrui o OHIF a também não enviar aspas no Accept header.
        omitQuotationForMultipartRequest: true,
        // Aceitar imagens não comprimidas (Explicit VR Little Endian)
        // Garante decodificação pelo Cornerstone3D mesmo sem TransferSyntax nos metadados
        acceptHeader: [
          'multipart/related; type=application/octet-stream; transfer-syntax=1.2.840.10008.1.2.1',
          'multipart/related; type=application/octet-stream; transfer-syntax=*',
          'multipart/related; type=application/octet-stream',
        ],
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
