// =============================================================================
// VOXEL PACS — app-config.js
// Gerado automaticamente por scripts/install-ohif.sh
// NÃO edite este arquivo manualmente — será regenerado pelo install.sh
//
// ARQUITETURA:
//   - Caminhos relativos apenas (/dicom-web, /wado)
//   - Nenhum IP, porta ou domínio externo
//   - Nginx faz proxy reverso: /dicom-web → Orthanc remoto
// =============================================================================
window.config = {
  routerBasename: '/',
  showStudyList: true,
  servers: {
    dicomWeb: [
      {
        name: 'VOXEL PACS',
        // Caminhos relativos — roteados pelo Nginx para o Orthanc remoto
        qidoRoot:    '/dicom-web',
        wadoRoot:    '/dicom-web',
        wadoUriRoot: '/wado',
        qidoSupportsIncludeField: true,
        imageRendering:     'wadors',
        thumbnailRendering: 'wadors',
        enableStudyLazyLoad: true,
        supportsFuzzyMatching: true,
      },
    ],
  },
  whiteLabeling: {
    createLogoComponentFn: function (React) {
      return React.createElement('a', { href: '/', className: 'text-white' },
        React.createElement('img', {
          src: '/assets/logo/logo-voxel-pacs.png',
          alt: 'VOXEL PACS',
          style: { height: '30px' }
        })
      );
    },
  },
};
