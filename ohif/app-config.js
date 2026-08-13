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
  // Consumido exclusivamente pela extensão @voxel/extension-measurement-adapter.
  // A autorização é um bearer token efêmero no fragmento da URL, não uma credencial fixa.
  voxelMeasurementAdapter: {
    endpoint: 'https://server.voxelpacs.com.br/api/viewer/measurements',
    debounceMs: 600,
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


/**
 * VOXEL VIEW — Personalização de marca do menu de perfil
 *
 * O OHIF v3.12.5 cria a opção About de forma incondicional no menu de
 * perfil. A versão em container não fornece uma chave de configuração para
 * removê-la. Esta guarda atua somente no DOM de menus Radix UI, preserva
 * Preferências e todos os controles clínicos, e impede a abertura visual do
 * modal que exibe informações do fornecedor.
 *
 * Não altera os arquivos minificados do OHIF nem remove avisos de licença
 * do software distribuído.
 */
(function installVoxelViewBrandingGuard() {
  const ABOUT_LABELS = new Set(['about', 'sobre', 'quem somos']);
  const HIDDEN_CLASS = 'voxel-view-hide-vendor-about';

  function normalise(value) {
    return (value || '')
      .replace(/\s+/g, ' ')
      .trim()
      .toLocaleLowerCase('pt-BR');
  }

  function isAboutLabel(value) {
    return ABOUT_LABELS.has(normalise(value));
  }

  function hideAboutOption() {
    const candidates = document.querySelectorAll(
      '[role="menuitem"], [role="menuitemcheckbox"], [role="menuitemradio"], [data-radix-collection-item], [data-radix-popper-content-wrapper] button'
    );

    candidates.forEach(candidate => {
      const label = candidate.getAttribute('aria-label') || candidate.textContent;
      const inMenu = candidate.closest('[role="menu"], [data-radix-popper-content-wrapper]');

      if (!inMenu || !isAboutLabel(label)) {
        return;
      }

      const menuItem = candidate.closest('[role="menuitem"], button, li') || candidate;
      menuItem.classList.add(HIDDEN_CLASS);
      menuItem.setAttribute('aria-hidden', 'true');
      menuItem.setAttribute('tabindex', '-1');
    });
  }

  function installStyle() {
    if (document.getElementById('voxel-view-branding-guard-style')) {
      return;
    }

    const style = document.createElement('style');
    style.id = 'voxel-view-branding-guard-style';
    style.textContent = `.${HIDDEN_CLASS} { display: none !important; }`;
    document.head.appendChild(style);
  }

  function start() {
    installStyle();
    hideAboutOption();

    let scheduled = false;
    const observer = new MutationObserver(() => {
      if (scheduled) {
        return;
      }

      scheduled = true;
      window.requestAnimationFrame(() => {
        scheduled = false;
        hideAboutOption();
      });
    });

    observer.observe(document.body, { childList: true, subtree: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  } else {
    start();
  }
})();
