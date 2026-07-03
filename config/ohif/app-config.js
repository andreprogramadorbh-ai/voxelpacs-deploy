/**
 * VOXEL PACS — OHIF Viewer v3 — Configuração de Produção
 * =========================================================
 * Arquitetura:
 *   view.voxelpacs.com.br  → OHIF SPA (container Docker)
 *   dicom.voxelpacs.com.br → Orthanc 1.12.2 + DICOMweb 1.16 (Nginx injeta auth)
 *
 * Problema resolvido: Orthanc DICOMweb 1.16 não inclui TransferSyntaxUID (00020010)
 * nos metadados JSON. Solução: usar acceptHeader para pedir imagens não comprimidas.
 */
window.config = {
  routerBasename: '/',
  extensions: [],
  modes: [],
  defaultDataSourceName: 'voxelpacs',
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
        // Orthanc DICOMweb 1.16: omitir aspas no multipart para compatibilidade
        omitQuotationForMultipartRequest: true,
        // Aceitar imagens não comprimidas (Explicit VR Little Endian)
        // Isso garante que o Cornerstone3D consiga decodificar mesmo sem TransferSyntax nos metadados
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
        }, 'VOXEL PACS')
      );
    },
  },
  customizationService: [
    { 'ohif.appTitle': { value: 'VOXEL PACS — Viewer DICOM' } },
  ],
};
