from pathlib import Path

config_path = Path('/home/ubuntu/voxelpacs-deploy-git/ohif/app-config.js')
favicon_b64 = Path('/tmp/voxel_pacs_favicon_32.b64').read_text(encoding='utf-8').strip()
marker = '/**\n * Enquanto o adapter de medições estiver desativado'

identity_script = f'''/**
 * Identidade de navegador do VOXEL PACS.
 * Mantém o título e o favicon institucionais mesmo após atualizações internas
 * do OHIF, sem interferir em serviços, modos, DICOMweb ou renderização.
 */
(function enforceVoxelPacsBrowserIdentity() {{
  const applicationTitle = 'VOXEL PACS';
  const faviconDataUri = 'data:image/png;base64,{favicon_b64}';

  function applyIdentity() {{
    if (document.title !== applicationTitle) {{
      document.title = applicationTitle;
    }}

    document.querySelectorAll(
      'link[rel~="icon"], link[rel="shortcut icon"], link[rel="apple-touch-icon"]'
    ).forEach(link => {{
      link.setAttribute('href', faviconDataUri);
      link.setAttribute('type', 'image/png');
    }});

    if (!document.querySelector('link[rel="icon"]')) {{
      const link = document.createElement('link');
      link.rel = 'icon';
      link.type = 'image/png';
      link.href = faviconDataUri;
      document.head.appendChild(link);
    }}
  }}

  applyIdentity();
  const observer = new MutationObserver(applyIdentity);
  observer.observe(document.head, {{ childList: true, subtree: true, characterData: true }});
}})();

'''

config = config_path.read_text(encoding='utf-8')
if 'enforceVoxelPacsBrowserIdentity' not in config:
    if marker not in config:
        raise SystemExit('Marcador de inserção não encontrado no app-config.js')
    config = config.replace(marker, identity_script + marker, 1)
    config_path.write_text(config, encoding='utf-8')
