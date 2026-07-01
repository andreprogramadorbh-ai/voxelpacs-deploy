#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — install.sh
# Instalação completa do ambiente OHIF + Nginx em Ubuntu 24.04
# =============================================================================
set -euo pipefail

# ── Cores ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[VOXEL]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${NC}"; echo -e "${BOLD}${CYAN}  $*${NC}"; echo -e "${BOLD}${BLUE}══════════════════════════════════════════${NC}\n"; }

# ── Banner ───────────────────────────────────────────────────────────────────
echo -e "${BOLD}${BLUE}"
cat << 'EOF'
 __   ______  _  __ _____ _       ____  ___   ____ ____
 \ \ / / __ \| |/ /| ____| |     |  _ \|   \ / ___/ ___|
  \ V /| |  | | ' / |  _| | |     | |_) | |\ | |   \___ \
   \_/ | |__| | . \ | |___| |___  |  __/| | \| |___ ___) |
        \____/|_|\_\|_____|_____| |_|   |_|  |\____|____/
EOF
echo -e "${NC}${BOLD}  Deploy Profissional — OHIF Viewer + Nginx${NC}\n"

# ── Verificar .env ────────────────────────────────────────────────────────────
section "Verificando configurações"
if [ ! -f ".env" ]; then
    error ".env não encontrado. Execute: cp .env.example .env && nano .env"
fi
source .env

# Validar variáveis obrigatórias
VARS_OK=true
for VAR in DOMAIN CERTBOT_EMAIL ORTHANC_HOST ORTHANC_PORT ORTHANC_USERNAME ORTHANC_PASSWORD; do
    VAL=$(eval echo "\$$VAR")
    if [ -z "$VAL" ]; then
        echo -e "${RED}[ERROR]${NC} Variável ${BOLD}${VAR}${NC} não configurada."
        echo -e "        Edite o arquivo .env e preencha: ${YELLOW}${VAR}=valor${NC}"
        VARS_OK=false
    fi
done

if [ "$VARS_OK" = false ]; then
    echo ""
    error "Corrija as variáveis acima no arquivo .env antes de continuar."
fi

log "Configurações carregadas. Domínio: ${DOMAIN}"

# ── Verificar Ubuntu 24 ───────────────────────────────────────────────────────
section "Verificando sistema operacional"
OS_VERSION=$(lsb_release -rs 2>/dev/null || echo "0")
if [[ "$OS_VERSION" != "24.04" ]]; then
    warn "Sistema detectado: Ubuntu ${OS_VERSION}. Recomendado: Ubuntu 24.04."
    read -rp "Continuar mesmo assim? (s/N): " CONFIRM
    [[ "$CONFIRM" =~ ^[sS]$ ]] || error "Instalação cancelada."
fi
log "Ubuntu ${OS_VERSION} detectado."

# ── Instalar Docker ───────────────────────────────────────────────────────────
section "Instalando Docker"
if command -v docker &>/dev/null; then
    log "Docker já instalado: $(docker --version)"
else
    bash ./scripts/install-docker.sh
fi

# ── Instalar Docker Compose Plugin ───────────────────────────────────────────
if ! docker compose version &>/dev/null; then
    log "Instalando Docker Compose Plugin..."
    apt-get install -y docker-compose-plugin
fi
log "Docker Compose: $(docker compose version)"

# ── Criar diretórios e volumes ────────────────────────────────────────────────
section "Criando diretórios"
mkdir -p /var/www/certbot
mkdir -p /etc/letsencrypt
log "Diretórios criados."

# ── Ajustar config Nginx com domínio do .env ─────────────────────────────────
section "Configurando Nginx"
sed -i "s/view\.voxelpacs\.com\.br/${DOMAIN}/g" config/nginx/default.conf
sed -i "s/view\.voxelpacs\.com\.br/${DOMAIN}/g" config/nginx/ssl.conf
log "Nginx configurado para: ${DOMAIN}"

# ── Ajustar app-config.js do OHIF ────────────────────────────────────────────
section "Configurando OHIF"
cat > config/ohif/app-config.js << APPCONFIG
window.config = {
  routerBasename: '/',
  showStudyList: true,
  servers: {
    dicomWeb: [
      {
        name: 'Orthanc',
        wadoUriRoot: '${ORTHANC_PROTOCOL}://${ORTHANC_HOST}:${ORTHANC_PORT}/wado',
        qidoRoot: '${ORTHANC_PROTOCOL}://${ORTHANC_HOST}:${ORTHANC_PORT}/dicom-web',
        wadoRoot: '${ORTHANC_PROTOCOL}://${ORTHANC_HOST}:${ORTHANC_PORT}/dicom-web',
        qidoSupportsIncludeField: true,
        imageRendering: 'wadors',
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
APPCONFIG
log "OHIF app-config.js gerado com Orthanc: ${ORTHANC_PROTOCOL}://${ORTHANC_HOST}:${ORTHANC_PORT}"

# ── Baixar imagens Docker ─────────────────────────────────────────────────────
section "Baixando imagens Docker"
docker compose pull
log "Imagens baixadas."

# ── Subir containers ──────────────────────────────────────────────────────────
section "Subindo containers"
docker compose up -d --build
log "Containers iniciados."

# ── Aguardar containers ficarem saudáveis ─────────────────────────────────────
section "Validando funcionamento"
sleep 5
MAX_RETRIES=12
for i in $(seq 1 $MAX_RETRIES); do
    OHIF_STATUS=$(docker inspect --format='{{.State.Health.Status}}' voxelpacs-ohif 2>/dev/null || echo "starting")
    NGINX_STATUS=$(docker inspect --format='{{.State.Health.Status}}' voxelpacs-nginx 2>/dev/null || echo "starting")
    if [[ "$OHIF_STATUS" == "healthy" && "$NGINX_STATUS" == "healthy" ]]; then
        log "Todos os containers estão saudáveis."
        break
    fi
    warn "Aguardando containers... (${i}/${MAX_RETRIES}) OHIF: ${OHIF_STATUS} | Nginx: ${NGINX_STATUS}"
    sleep 10
done

# ── Gerar SSL ─────────────────────────────────────────────────────────────────
if [[ "${GENERATE_SSL:-yes}" == "yes" ]]; then
    section "Gerando certificado SSL"
    bash ./scripts/generate-ssl.sh
fi

# ── Resultado final ───────────────────────────────────────────────────────────
section "Instalação concluída!"
echo -e "${GREEN}${BOLD}"
echo "  ✅ VOXEL PACS instalado com sucesso!"
echo ""
echo "  🌐 OHIF Viewer:    https://${DOMAIN}"
echo "  🔗 Orthanc remoto: ${ORTHANC_PROTOCOL}://${ORTHANC_HOST}:${ORTHANC_PORT}"
echo ""
echo "  📋 Comandos úteis:"
echo "     ./healthcheck.sh     — verificar saúde do sistema"
echo "     ./update.sh          — atualizar para nova versão"
echo "     ./backup.sh          — fazer backup"
echo -e "${NC}"
