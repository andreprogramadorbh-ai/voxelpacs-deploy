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
 * Identidade de navegador do VOXEL PACS.
 * Mantém o título e o favicon institucionais mesmo após atualizações internas
 * do OHIF, sem interferir em serviços, modos, DICOMweb ou renderização.
 */
(function enforceVoxelPacsBrowserIdentity() {
  const applicationTitle = 'VOXEL PACS';
  const faviconDataUri = 'data:image/png;base64,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';

  function applyIdentity() {
    if (document.title !== applicationTitle) {
      document.title = applicationTitle;
    }

    document.querySelectorAll(
      'link[rel~="icon"], link[rel="shortcut icon"], link[rel="apple-touch-icon"]'
    ).forEach(link => {
      link.setAttribute('href', faviconDataUri);
      link.setAttribute('type', 'image/png');
    });

    if (!document.querySelector('link[rel="icon"]')) {
      const link = document.createElement('link');
      link.rel = 'icon';
      link.type = 'image/png';
      link.href = faviconDataUri;
      document.head.appendChild(link);
    }
  }

  applyIdentity();
  const observer = new MutationObserver(applyIdentity);
  observer.observe(document.head, { childList: true, subtree: true, characterData: true });
})();

/**
 * Enquanto o adapter de medições estiver desativado, remove qualquer
 * fragmento de credencial legado antes da inicialização do viewer. O fragmento
 * não é enviado ao servidor, e a remoção preserva eventuais âncoras restantes.
 */
(function removeDisabledMeasurementTokenFromUrl() {
  const hash = window.location.hash.startsWith('#') ? window.location.hash.slice(1) : '';
  const values = new URLSearchParams(hash);

  if (!values.has('voxel_measurement_token')) {
    return;
  }

  values.delete('voxel_measurement_token');
  const remainingHash = values.toString();
  const cleanUrl = `${window.location.pathname}${window.location.search}${remainingHash ? `#${remainingHash}` : ''}`;
  window.history.replaceState({}, document.title, cleanUrl);
})();

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
