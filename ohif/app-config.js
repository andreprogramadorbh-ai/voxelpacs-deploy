/**
 * VOXEL PACS — OHIF Viewer Configuration
 * Versão: OHIF v3.12.5
 * Formato: dataSources (OHIF v3)
 */
window.config = {
  routerBasename: '/',
  extensions: [],
  modes: [],
  showStudyList: true,
  maxNumberOfWebWorkers: 3,
  defaultDataSourceName: 'voxelpacs',
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
        requestOptions: { auth: 'vivere_admin:Inlaudo259087@' },
        enableStudyLazyLoad: true,
        qidoSupportsIncludeField: true,
        imageRendering: 'wadors',
        thumbnailRendering: 'wadors',
        omitQuotationForMultipartRequest: true,
        bulkDataURI: { enabled: true, relativeResolution: 'series' }
      }
    }
  ],
  whiteLabeling: {
    createLogoComponentFn: function(React) {
      return React.createElement(
        'a',
        { href: 'https://view.voxelpacs.com.br', target: '_blank', rel: 'noopener noreferrer' },
        React.createElement('img', { src: '/assets/logo/logo-voxel-pacs.png', alt: 'VOXEL PACS', style: { height: '28px' } })
      );
    }
  }
};
