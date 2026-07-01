#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — install.sh
# Instalação completa: Docker, Nginx, OHIF, SSL, Orthanc proxy
# Ubuntu 24.04 | Docker Compose V1 e V2
# =============================================================================
set -euo pipefail

# ── Cores ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[VOXEL]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
ok()      { echo -e "${GREEN}  ✔${NC} $*"; }
section() {
    echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $*${NC}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════${NC}\n"
}

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${BLUE}"
cat << 'BANNER'
 __   ______  _  __ _____ _       ____  ___   ____ ____
 \ \ / / __ \| |/ /| ____| |     |  _ \|   \ / ___/ ___|
  \ V /| |  | | ' / |  _| | |     | |_) | |\ | |   \___ \
   \_/ | |__| | . \ | |___| |___  |  __/| | \| |___ ___) |
        \____/|_|\_\|_____|_____| |_|   |_|  |\____|____/
BANNER
echo -e "${NC}${BOLD}  Deploy Profissional — OHIF Viewer + Nginx + SSL${NC}\n"

# ── Verificar .env ────────────────────────────────────────────────────────────
section "Verificando configurações"
if [ ! -f ".env" ]; then
    error ".env não encontrado. Execute: cp .env.example .env && nano .env"
fi
# shellcheck source=.env
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
[ "$VARS_OK" = false ] && { echo ""; error "Corrija as variáveis acima no .env antes de continuar."; }
ok "Configurações carregadas. Domínio: ${DOMAIN}"

# ── Detectar sistema operacional ──────────────────────────────────────────────
section "Detectando sistema operacional"
OS_ID=$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
OS_VERSION=$(grep '^VERSION_ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "0")
ok "Sistema: ${OS_ID} ${OS_VERSION}"
if [[ "$OS_ID" != "ubuntu" ]]; then
    warn "Sistema não é Ubuntu. Compatibilidade não garantida."
    read -rp "Continuar mesmo assim? (s/N): " CONFIRM
    [[ "$CONFIRM" =~ ^[sS]$ ]] || error "Instalação cancelada."
fi

# ── Detectar/Instalar Docker ──────────────────────────────────────────────────
section "Detectando Docker"
if command -v docker &>/dev/null; then
    ok "Docker já instalado: $(docker --version)"
else
    log "Docker não encontrado. Instalando..."
    bash ./scripts/install-docker.sh
    ok "Docker instalado: $(docker --version)"
fi

# ── Detectar Docker Compose (V1 ou V2) ───────────────────────────────────────
section "Detectando Docker Compose"
if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
    ok "Docker Compose V1 detectado: $(docker-compose --version)"
elif docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
    ok "Docker Compose V2 detectado: $(docker compose version)"
else
    log "Docker Compose não encontrado. Tentando instalar..."
    # Tenta plugin V2 (Ubuntu 22+/24)
    if apt-get install -y docker-compose-plugin 2>/dev/null; then
        COMPOSE="docker compose"
        ok "Docker Compose V2 instalado: $(docker compose version)"
    else
        # Fallback: instala V1 via pip
        pip3 install docker-compose --quiet 2>/dev/null || true
        if command -v docker-compose >/dev/null 2>&1; then
            COMPOSE="docker-compose"
            ok "Docker Compose V1 instalado via pip: $(docker-compose --version)"
        else
            error "Não foi possível instalar o Docker Compose. Instale manualmente e tente novamente."
        fi
    fi
fi
export COMPOSE

# ── Instalar Nginx e Certbot ──────────────────────────────────────────────────
section "Instalando Nginx e Certbot"
apt-get update -qq
apt-get install -y -qq nginx certbot python3-certbot-nginx
ok "Nginx instalado: $(nginx -v 2>&1)"
ok "Certbot instalado: $(certbot --version)"

# ── Criar diretórios necessários ──────────────────────────────────────────────
section "Criando estrutura de diretórios"
mkdir -p ssl backups config/nginx/sites
ok "Diretórios criados."

# ── Gerar configuração Nginx ──────────────────────────────────────────────────
section "Gerando configuração Nginx"
OHIF_PORT_VAL="${OHIF_PORT:-3000}"

cat > config/nginx/sites/voxelpacs.conf << NGINXCONF
# VOXEL PACS — Nginx gerado automaticamente por install.sh
# Domínio: ${DOMAIN}

server {
    listen 80;
    server_name ${DOMAIN};

    # Desafio ACME para Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Redireciona HTTP → HTTPS após SSL gerado
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    # OHIF Viewer
    location / {
        proxy_pass         http://127.0.0.1:${OHIF_PORT_VAL};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    # Proxy DICOMweb → Orthanc (evita CORS no navegador)
    location /dicom-web/ {
        proxy_pass         ${ORTHANC_PROTOCOL}://${ORTHANC_HOST}:${ORTHANC_PORT}/dicom-web/;
        proxy_set_header   Authorization "Basic $(echo -n "${ORTHANC_USERNAME}:${ORTHANC_PASSWORD}" | base64)";
        proxy_set_header   Host \$host;
        add_header         Access-Control-Allow-Origin "*" always;
        add_header         Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header         Access-Control-Allow-Headers "Authorization, Content-Type" always;
    }

    location /wado {
        proxy_pass         ${ORTHANC_PROTOCOL}://${ORTHANC_HOST}:${ORTHANC_PORT}/wado;
        proxy_set_header   Authorization "Basic $(echo -n "${ORTHANC_USERNAME}:${ORTHANC_PASSWORD}" | base64)";
        proxy_set_header   Host \$host;
    }
}
NGINXCONF

# Ativar site no Nginx
mkdir -p /var/www/certbot
ln -sf "$(pwd)/config/nginx/sites/voxelpacs.conf" /etc/nginx/sites-enabled/voxelpacs.conf
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
nginx -t && systemctl reload nginx
ok "Nginx configurado para: ${DOMAIN}"

# ── Gerar app-config.js do OHIF ───────────────────────────────────────────────
section "Gerando configuração OHIF"
OHIF_NAME_VAL="${OHIF_NAME:-VOXEL PACS}"
QIDO_ROOT_VAL="${QIDO_ROOT:-/dicom-web}"
WADO_ROOT_VAL="${WADO_ROOT:-/dicom-web}"
WADO_URI_ROOT_VAL="${WADO_URI_ROOT:-/wado}"

cat > config/ohif/app-config.js << APPCONFIG
window.config = {
  routerBasename: '/',
  showStudyList: true,
  servers: {
    dicomWeb: [
      {
        name: '${OHIF_NAME_VAL}',
        wadoUriRoot: 'https://${DOMAIN}${WADO_URI_ROOT_VAL}',
        qidoRoot:    'https://${DOMAIN}${QIDO_ROOT_VAL}',
        wadoRoot:    'https://${DOMAIN}${WADO_ROOT_VAL}',
        qidoSupportsIncludeField: true,
        imageRendering:    'wadors',
        thumbnailRendering:'wadors',
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
          alt: '${OHIF_NAME_VAL}',
          style: { height: '30px' }
        })
      );
    },
  },
};
APPCONFIG
ok "app-config.js gerado. DICOMweb via: https://${DOMAIN}${QIDO_ROOT_VAL}"

# ── Subir containers Docker ───────────────────────────────────────────────────
section "Iniciando containers Docker"
$COMPOSE pull
$COMPOSE up -d --build
ok "Containers iniciados."

# ── Aguardar containers ficarem saudáveis ─────────────────────────────────────
section "Validando containers"
sleep 5
MAX_RETRIES=12
for i in $(seq 1 $MAX_RETRIES); do
    OHIF_STATUS=$(docker inspect --format='{{.State.Status}}' voxelpacs-ohif 2>/dev/null || echo "unknown")
    if [[ "$OHIF_STATUS" == "running" ]]; then
        ok "Container OHIF: running"
        break
    fi
    warn "Aguardando OHIF... (${i}/${MAX_RETRIES}) Status: ${OHIF_STATUS}"
    sleep 10
done

# ── Gerar SSL Let's Encrypt ───────────────────────────────────────────────────
if [[ "${GENERATE_SSL:-yes}" == "yes" ]]; then
    section "Gerando certificado SSL"
    bash ./scripts/generate-ssl.sh
    # Recarregar Nginx com SSL ativo
    nginx -t && systemctl reload nginx
    ok "SSL configurado para: ${DOMAIN}"
fi

# ── Validar conexão com Orthanc ───────────────────────────────────────────────
section "Validando conexão com Orthanc"
ORTHANC_URL="${ORTHANC_PROTOCOL}://${ORTHANC_HOST}:${ORTHANC_PORT}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ORTHANC_USERNAME}:${ORTHANC_PASSWORD}" \
    "${ORTHANC_URL}/system" --max-time 10 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
    ok "Orthanc acessível: ${ORTHANC_URL}"
else
    warn "Orthanc retornou HTTP ${HTTP_CODE}. Verifique ORTHANC_HOST, ORTHANC_PORT e credenciais no .env."
fi

# ── Validar DICOMweb ──────────────────────────────────────────────────────────
DICOM_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ORTHANC_USERNAME}:${ORTHANC_PASSWORD}" \
    "${ORTHANC_URL}/dicom-web/studies" --max-time 10 2>/dev/null || echo "000")
if [[ "$DICOM_CODE" == "200" ]]; then
    ok "DICOMweb acessível: ${ORTHANC_URL}/dicom-web/studies"
else
    warn "DICOMweb retornou HTTP ${DICOM_CODE}. Verifique se o plugin DICOMweb está ativo no Orthanc."
fi

# ── Validar OHIF ──────────────────────────────────────────────────────────────
OHIF_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://127.0.0.1:${OHIF_PORT_VAL}" --max-time 10 2>/dev/null || echo "000")
if [[ "$OHIF_CODE" == "200" ]]; then
    ok "OHIF Viewer acessível: http://127.0.0.1:${OHIF_PORT_VAL}"
else
    warn "OHIF retornou HTTP ${OHIF_CODE}. Verifique os logs: $COMPOSE logs ohif"
fi

# ── Resultado final ───────────────────────────────────────────────────────────
section "Instalação concluída!"
echo -e "${GREEN}${BOLD}"
echo "  ✅ VOXEL PACS instalado com sucesso!"
echo ""
echo "  🌐 OHIF Viewer:    https://${DOMAIN}"
echo "  🔗 Orthanc remoto: ${ORTHANC_URL}"
echo ""
echo "  📋 Comandos úteis:"
echo "     bash healthcheck.sh   — verificar saúde do sistema"
echo "     bash update.sh        — atualizar para nova versão"
echo "     bash backup.sh        — fazer backup"
echo "     bash rollback.sh      — reverter para versão anterior"
echo -e "${NC}"
