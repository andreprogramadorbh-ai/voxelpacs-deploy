window.config = {
  routerBasename: '/',
  showStudyList: true,
  servers: {
    dicomWeb: [
      {
        name: 'Orthanc',
        wadoUriRoot: `${window.ORTHANC_PROTOCOL || 'https'}://${window.ORTHANC_HOST || 'dicom.voxelpacs.com.br'}:${window.ORTHANC_PORT || '8042'}/wado`,
        qidoRoot: `${window.ORTHANC_PROTOCOL || 'https'}://${window.ORTHANC_HOST || 'dicom.voxelpacs.com.br'}:${window.ORTHANC_PORT || '8042'}/dicom-web`,
        wadoRoot: `${window.ORTHANC_PROTOCOL || 'https'}://${window.ORTHANC_HOST || 'dicom.voxelpacs.com.br'}:${window.ORTHANC_PORT || '8042'}/dicom-web`,
        qidoSupportsIncludeField: true,
        imageRendering: 'wadors',
        thumbnailRendering: 'wadors',
        enableStudyLazyLoad: true,
        supportsFuzzyMatching: true,
      },
    ],
  },
  // Logo customization
  whiteLabeling: {
    createLogoComponentFn: function (React) {
      return React.createElement('a', {
        target: '_self',
        rel: 'noopener noreferrer',
        className: 'text-white',
        href: '/',
      }, React.createElement('img', {
        src: '/assets/logo/logo-voxel-pacs.png',
        alt: 'VOXEL PACS',
        style: { height: '30px' }
      }));
    },
  },
};
