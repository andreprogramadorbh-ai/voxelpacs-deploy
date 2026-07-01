#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/install.sh
# Instalação completa: Docker, Nginx, OHIF, SSL, Proxy Orthanc
# Ubuntu 24.04 | Docker Compose V1 e V2 | Idempotente
#
# REGRA NGINX:
#   - NUNCA sobrescreve /etc/nginx/nginx.conf
#   - VirtualHost criado em /etc/nginx/sites-available/voxelpacs.conf
#   - Ativado via symlink em /etc/nginx/sites-enabled/
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

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
[ -f ".env" ] || error ".env não encontrado. Execute: cp .env.example .env && nano .env"
source .env

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

# ── Detectar SO ───────────────────────────────────────────────────────────────
section "Detectando sistema operacional"
OS_ID=$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
OS_VERSION=$(grep '^VERSION_ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "0")
ok "Sistema: ${OS_ID} ${OS_VERSION}"
if [[ "$OS_ID" != "ubuntu" ]]; then
    warn "Sistema não é Ubuntu. Compatibilidade não garantida."
    read -rp "Continuar mesmo assim? (s/N): " CONFIRM
    [[ "$CONFIRM" =~ ^[sS]$ ]] || error "Instalação cancelada."
fi

# ── Docker ────────────────────────────────────────────────────────────────────
section "Verificando Docker"
if command -v docker &>/dev/null; then
    ok "Docker já instalado: $(docker --version)"
else
    log "Docker não encontrado. Instalando..."
    bash scripts/install-docker.sh
    ok "Docker instalado: $(docker --version)"
fi

# ── Docker Compose ────────────────────────────────────────────────────────────
section "Detectando Docker Compose"
if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
    ok "Docker Compose V1: $(docker-compose --version)"
elif docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
    ok "Docker Compose V2: $(docker compose version)"
else
    log "Docker Compose não encontrado. Tentando instalar..."
    if apt-get install -y docker-compose-plugin 2>/dev/null; then
        COMPOSE="docker compose"
        ok "Docker Compose V2 instalado."
    else
        pip3 install docker-compose --quiet 2>/dev/null || true
        if command -v docker-compose >/dev/null 2>&1; then
            COMPOSE="docker-compose"
            ok "Docker Compose V1 instalado via pip."
        else
            error "Não foi possível instalar o Docker Compose."
        fi
    fi
fi
export COMPOSE

# ── Nginx ─────────────────────────────────────────────────────────────────────
section "Instalando Nginx"
bash scripts/install-nginx.sh

# ── Verificar integridade do nginx.conf (nunca sobrescrever) ──────────────────
section "Validando nginx.conf do Ubuntu"
NGINX_CONF="/etc/nginx/nginx.conf"
if [ ! -f "$NGINX_CONF" ]; then
    error "Arquivo ${NGINX_CONF} não encontrado. Reinstale o Nginx: apt-get install --reinstall nginx"
fi
# Garantir que os includes obrigatórios existam no nginx.conf
if ! grep -q "include /etc/nginx/sites-enabled" "$NGINX_CONF"; then
    warn "nginx.conf não contém 'include /etc/nginx/sites-enabled/*'. Adicionando..."
    # Adiciona o include dentro do bloco http, antes do fechamento
    sed -i '/^http {/a\\tinclude /etc/nginx/conf.d/*.conf;\n\tinclude /etc/nginx/sites-enabled/*;' "$NGINX_CONF"
    ok "Includes adicionados ao nginx.conf."
else
    ok "nginx.conf contém os includes necessários."
fi
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

# ── Certbot ───────────────────────────────────────────────────────────────────
section "Instalando Certbot"
bash scripts/install-certbot.sh

# ── Firewall ──────────────────────────────────────────────────────────────────
section "Configurando Firewall"
bash scripts/firewall.sh

# ── Diretórios ────────────────────────────────────────────────────────────────
section "Criando diretórios"
mkdir -p ssl backups config/nginx/sites /var/www/certbot
ok "Diretórios criados."

# ── OHIF app-config.js ────────────────────────────────────────────────────────
section "Gerando configuração OHIF (app-config.js)"
bash scripts/install-ohif.sh

# ── VirtualHost Nginx em sites-available/ ────────────────────────────────────
section "Gerando VirtualHost Nginx"
OHIF_PORT_VAL="${OHIF_PORT:-3000}"
ORTHANC_B64=$(echo -n "${ORTHANC_USERNAME}:${ORTHANC_PASSWORD}" | base64 -w0)
ORTHANC_PROTO="${ORTHANC_PROTOCOL:-http}"
VHOST_FILE="/etc/nginx/sites-available/voxelpacs.conf"

# Criar VirtualHost em sites-available (NUNCA em nginx.conf)
cat > "$VHOST_FILE" << NGINXCONF
# =============================================================================
# VOXEL PACS — VirtualHost
# Gerado automaticamente por scripts/install.sh
# Domínio: ${DOMAIN}
# NÃO edite este arquivo manualmente — será regenerado pelo install.sh
# =============================================================================

server {
    listen 80;
    server_name ${DOMAIN};

    # Desafio ACME para Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Redireciona HTTP → HTTPS
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
    ssl_prefer_server_ciphers on;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;

    # OHIF Viewer
    location / {
        proxy_pass         http://127.0.0.1:${OHIF_PORT_VAL};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 300s;
    }

    # Proxy DICOMweb → Orthanc (evita CORS no navegador)
    location /dicom-web/ {
        proxy_pass         ${ORTHANC_PROTO}://${ORTHANC_HOST}:${ORTHANC_PORT}/dicom-web/;
        proxy_set_header   Authorization "Basic ${ORTHANC_B64}";
        proxy_set_header   Host \$host;
        proxy_read_timeout 300s;
        add_header         Access-Control-Allow-Origin "*" always;
        add_header         Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header         Access-Control-Allow-Headers "Authorization, Content-Type" always;
        if (\$request_method = OPTIONS) { return 204; }
    }

    # Proxy WADO → Orthanc
    location /wado {
        proxy_pass         ${ORTHANC_PROTO}://${ORTHANC_HOST}:${ORTHANC_PORT}/wado;
        proxy_set_header   Authorization "Basic ${ORTHANC_B64}";
        proxy_set_header   Host \$host;
        proxy_read_timeout 300s;
    }

    # Health check interno
    location /health {
        return 200 "OK";
        add_header Content-Type text/plain;
    }
}
NGINXCONF

ok "VirtualHost criado em: ${VHOST_FILE}"

# Ativar via symlink (padrão Ubuntu)
ln -sf "$VHOST_FILE" /etc/nginx/sites-enabled/voxelpacs.conf
ok "Symlink criado: /etc/nginx/sites-enabled/voxelpacs.conf → ${VHOST_FILE}"

# Remover site default do Ubuntu (se existir)
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Validar configuração do Nginx
if nginx -t 2>/dev/null; then
    ok "nginx -t: configuração válida."
    systemctl reload nginx
    ok "Nginx recarregado."
else
    error "nginx -t falhou! Verifique a configuração em ${VHOST_FILE}"
fi

# ── Validar server_name no Nginx (nginx -T) ───────────────────────────────────
section "Validando server_name no Nginx"
if nginx -T 2>/dev/null | grep -q "server_name ${DOMAIN}"; then
    ok "server_name '${DOMAIN}' encontrado na configuração ativa do Nginx."
else
    error "server_name '${DOMAIN}' NÃO encontrado em 'nginx -T'.
       Verifique se o VirtualHost foi criado corretamente em:
         ${VHOST_FILE}
       E se o symlink existe em:
         /etc/nginx/sites-enabled/voxelpacs.conf
       Execute manualmente: nginx -T | grep server_name"
fi

# ── Containers Docker ─────────────────────────────────────────────────────────
section "Iniciando containers Docker"
cd docker
$COMPOSE pull
$COMPOSE up -d --build
cd "$PROJECT_DIR"
ok "Containers iniciados."

# ── Aguardar OHIF ─────────────────────────────────────────────────────────────
section "Validando containers"
sleep 8
for i in $(seq 1 15); do
    STATUS=$(docker inspect --format='{{.State.Status}}' voxelpacs-ohif 2>/dev/null || echo "unknown")
    if [[ "$STATUS" == "running" ]]; then ok "Container OHIF: running"; break; fi
    warn "Aguardando OHIF... (${i}/15) Status: ${STATUS}"; sleep 10
done

# ── SSL Let's Encrypt ─────────────────────────────────────────────────────────
if [[ "${GENERATE_SSL:-yes}" == "yes" ]]; then
    section "Gerando certificado SSL"
    bash scripts/generate-ssl.sh
    nginx -t && systemctl reload nginx
    ok "SSL configurado para: ${DOMAIN}"
fi

# ── Validar serviços ──────────────────────────────────────────────────────────
section "Validando serviços"
ORTHANC_URL="${ORTHANC_PROTO}://${ORTHANC_HOST}:${ORTHANC_PORT}"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "${ORTHANC_USERNAME}:${ORTHANC_PASSWORD}" "${ORTHANC_URL}/system" --max-time 10 2>/dev/null || echo "000")
[[ "$HTTP_CODE" == "200" ]] && ok "Orthanc: ${ORTHANC_URL}" || warn "Orthanc HTTP ${HTTP_CODE} — verifique credenciais"

DICOM_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "${ORTHANC_USERNAME}:${ORTHANC_PASSWORD}" "${ORTHANC_URL}/dicom-web/studies" --max-time 10 2>/dev/null || echo "000")
[[ "$DICOM_CODE" == "200" ]] && ok "DICOMweb: OK" || warn "DICOMweb HTTP ${DICOM_CODE} — verifique plugin DICOMweb no Orthanc"

OHIF_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${OHIF_PORT_VAL}" --max-time 10 2>/dev/null || echo "000")
[[ "$OHIF_CODE" == "200" ]] && ok "OHIF: http://127.0.0.1:${OHIF_PORT_VAL}" || warn "OHIF HTTP ${OHIF_CODE} — verifique: $COMPOSE logs ohif"

HTTPS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://${DOMAIN}" --max-time 15 2>/dev/null || echo "000")
[[ "$HTTPS_CODE" == "200" ]] && ok "HTTPS: https://${DOMAIN}" || warn "HTTPS HTTP ${HTTPS_CODE} — verifique DNS e SSL"

# ── Resultado final ───────────────────────────────────────────────────────────
section "Instalação concluída!"
echo -e "${GREEN}${BOLD}"
echo "  ✅ VOXEL PACS instalado com sucesso!"
echo "  🌐 OHIF Viewer:    https://${DOMAIN}"
echo "  🔗 Orthanc remoto: ${ORTHANC_URL}"
echo ""
echo "  📋 Comandos úteis:"
echo "     bash scripts/healthcheck.sh   — verificar saúde"
echo "     bash scripts/update.sh        — atualizar"
echo "     bash scripts/backup.sh        — backup"
echo "     bash scripts/rollback.sh      — reverter versão"
echo -e "${NC}"
