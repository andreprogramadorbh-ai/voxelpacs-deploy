# =============================================================================
# VOXEL PACS — docker/Dockerfile
# Imagem customizada do OHIF com logo e configurações
# =============================================================================
FROM ohif/app:latest

LABEL maintainer="VOXEL PACS <suporte@voxelpacs.com.br>"
LABEL description="OHIF Viewer customizado para VOXEL PACS"

# Copiar app-config.js gerado pelo install.sh
COPY app-config.js /usr/share/nginx/html/app-config.js

# Expor porta padrão do OHIF
EXPOSE 80
