window.config = {
  routerBasename: '/',
  showStudyList: false,
  maxNumberOfWebWorkers: 2,
  extensions: [],
  modes: [],
  dataSources: [
    {
      namespace: '@ohif/extension-default.dataSourcesModule.dicomweb',
      sourceName: 'dicomweb',
      configuration: {
        name: 'VOXEL PACS — Cliente A',
        qidoRoot: 'https://cliente-a.view.voxelpacs.com.br/dicom-web',
        wadoRoot: 'https://cliente-a.view.voxelpacs.com.br/dicom-web',
        qidoSupportsIncludeField: true,
        supportsFuzzyMatching: false,
        imageRendering: 'wadors',
        thumbnailRendering: 'wadors',
        enableStudyLazyLoad: true,
      },
    },
  ],
};
