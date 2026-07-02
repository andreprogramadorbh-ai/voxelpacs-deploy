#!/usr/bin/env bash
# =============================================================================
# VOXEL PACS — scripts/install.sh
# Instalação completa da plataforma VOXEL PACS v1.0
#
# Arquitetura:
#   Internet → Nginx → OHIF + API VOXEL PACS → PostgreSQL + Orthanc → Storage DICOM
#
# Containers Docker:
#   postgres        — banco de dados (índices Orthanc + dados API)
#   orthanc         — servidor DICOM + DICOMweb (osimis/orthanc:24.11.3)
#   ohif            — visualizador DICOM (ohif/app:v3.12.5)
#   voxelpacs-api   — API REST (auth, tokens, RBAC, auditoria)
#
# Nginx no host:
#   Proxy reverso para todos os containers
#   SSL via Let's Encrypt
#   Rotas: /, /dicom-web/, /wado, /api/, /open/{token}
#   Endpoints: /health, /ready, /live
#
# Uso:
#   bash scripts/install.sh
#   (ou: bash deploy.sh)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# ── Cores e funções de output ─────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
ok()      { echo -e "${GREEN}  ✔${NC} $*"; }
warn()    { echo -e "${YELLOW}  ⚠${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
log()     { echo -e "${BLUE}  →${NC} $*"; }
section() { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}"; }

# ── Verificar root ────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Execute como root: sudo bash scripts/install.sh"

# ── Carregar .env ─────────────────────────────────────────────────────────────
section "Carregando configuração"
[ -f ".env" ] || error ".env não encontrado. Execute: cp .env.example .env && nano .env"
source .env
ok ".env carregado"

# ── Validar variáveis obrigatórias ────────────────────────────────────────────
section "Validando configuração"
ERRORS=0
for VAR in DOMAIN CERTBOT_EMAIL ORTHANC_USERNAME ORTHANC_PASSWORD \
           POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD; do
    VAL=$(eval echo "\${${VAR}:-}")
    if [ -z "$VAL" ]; then
        echo -e "${RED}[ERROR]${NC} Variável ${BOLD}${VAR}${NC} não configurada."
        echo "        Edite o arquivo .env e preencha: ${VAR}=valor"
        ERRORS=$((ERRORS + 1))
    fi
done
[ $ERRORS -gt 0 ] && error "Corrija as ${ERRORS} variável(is) acima no .env antes de continuar."
ok "Todas as variáveis obrigatórias configuradas"

# ── Criar diretórios necessários ──────────────────────────────────────────────
section "Criando estrutura de diretórios"
mkdir -p \
    orthanc \
    nginx \
    ohif/logo \
    postgres/data \
    storage/dicom \
    api \
    backups \
    logs
ok "Estrutura de diretórios criada em: ${PROJECT_DIR}"

# ── Instalar Docker ───────────────────────────────────────────────────────────
section "Verificando Docker"
if ! command -v docker &>/dev/null; then
    log "Instalando Docker..."
    bash scripts/install-docker.sh
    ok "Docker instalado"
else
    ok "Docker já instalado: $(docker --version)"
fi

# Detectar Docker Compose V1 ou V2
if docker compose version &>/dev/null 2>&1; then
    COMPOSE="docker compose"
    ok "Docker Compose V2: $(docker compose version --short)"
elif command -v docker-compose &>/dev/null; then
    COMPOSE="docker-compose"
    ok "Docker Compose V1: $(docker-compose --version)"
else
    log "Instalando Docker Compose plugin..."
    apt-get install -y docker-compose-plugin 2>/dev/null || \
        pip3 install docker-compose 2>/dev/null || \
        error "Não foi possível instalar Docker Compose"
    COMPOSE="docker compose"
fi

# ── Instalar Nginx ────────────────────────────────────────────────────────────
section "Verificando Nginx"
if ! command -v nginx &>/dev/null; then
    log "Instalando Nginx..."
    bash scripts/install-nginx.sh
    ok "Nginx instalado"
else
    ok "Nginx já instalado: $(nginx -v 2>&1)"
fi

# Verificar includes no nginx.conf (nunca sobrescrever o nginx.conf do Ubuntu)
if ! grep -q "sites-enabled" /etc/nginx/nginx.conf 2>/dev/null; then
    warn "nginx.conf sem include sites-enabled — adicionando..."
    echo -e "\ninclude /etc/nginx/sites-enabled/*;" >> /etc/nginx/nginx.conf
    ok "include adicionado ao nginx.conf"
fi

# ── Gerar app-config.js OHIF v3 ───────────────────────────────────────────────
section "Gerando configuração OHIF"
bash scripts/install-ohif.sh
ok "app-config.js gerado em formato OHIF v3 (dataSources)"

# ── Gerar configurações modulares do Orthanc ──────────────────────────────────
section "Gerando configurações Orthanc"
ORTHANC_B64=$(echo -n "${ORTHANC_USERNAME}:${ORTHANC_PASSWORD}" | base64 -w0)

# credentials.json — gerado dinamicamente (nunca versionar com senha real)
cat > orthanc/credentials.json << CREDEOF
{
  "AuthenticationEnabled": true,
  "RegisteredUsers": {
    "${ORTHANC_USERNAME}": "${ORTHANC_PASSWORD}"
  }
}
CREDEOF
ok "orthanc/credentials.json gerado"

# dicomweb.json — substitui placeholder do domínio
sed "s/DOMAIN_PLACEHOLDER/${DOMAIN}/g" orthanc/dicomweb.json > /tmp/dicomweb.json
cp /tmp/dicomweb.json orthanc/dicomweb.json
ok "orthanc/dicomweb.json configurado para: ${DOMAIN}"

# postgresql.json — substitui placeholders do banco
sed -e "s/POSTGRES_DB_PLACEHOLDER/${POSTGRES_DB}/g" \
    -e "s/POSTGRES_USER_PLACEHOLDER/${POSTGRES_USER}/g" \
    -e "s/POSTGRES_PASSWORD_PLACEHOLDER/${POSTGRES_PASSWORD}/g" \
    orthanc/postgresql.json > /tmp/postgresql.json
cp /tmp/postgresql.json orthanc/postgresql.json
ok "orthanc/postgresql.json configurado"

# ── Gerar VirtualHost Nginx ───────────────────────────────────────────────────
section "Gerando VirtualHost Nginx"
OHIF_PORT_VAL="${OHIF_PORT:-3000}"
VHOST_FILE="/etc/nginx/sites-available/voxelpacs.conf"

# Gerar a partir do template nginx/voxelpacs.conf
sed -e "s/DOMAIN_PLACEHOLDER/${DOMAIN}/g" \
    -e "s/ORTHANC_B64_PLACEHOLDER/${ORTHANC_B64}/g" \
    -e "s/OHIF_PORT_PLACEHOLDER/${OHIF_PORT_VAL}/g" \
    nginx/voxelpacs.conf > "$VHOST_FILE"

ok "VirtualHost criado em: ${VHOST_FILE}"

# Ativar via symlink (padrão Ubuntu)
ln -sf "$VHOST_FILE" /etc/nginx/sites-enabled/voxelpacs.conf
ok "Symlink: /etc/nginx/sites-enabled/voxelpacs.conf"

# Remover site default do Ubuntu
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Validar configuração
nginx -t 2>/dev/null || error "nginx -t falhou! Verifique: ${VHOST_FILE}"
ok "nginx -t: configuração válida"
systemctl reload nginx
ok "Nginx recarregado"

# Validar server_name
nginx -T 2>/dev/null | grep -q "server_name ${DOMAIN}" || \
    error "server_name '${DOMAIN}' não encontrado em nginx -T. Verifique: ${VHOST_FILE}"
ok "server_name '${DOMAIN}' confirmado no Nginx"

# ── Configurar Firewall ───────────────────────────────────────────────────────
section "Configurando Firewall"
bash scripts/firewall.sh
ok "Firewall configurado (22/80/443 abertos; 8042/4242/3000/8080 bloqueados externamente)"

# ── Subir containers Docker ───────────────────────────────────────────────────
section "Subindo containers Docker"

# Validar que app-config.js existe e é válido
[ -f "ohif/app-config.js" ] || error "ohif/app-config.js não encontrado. Execute: bash scripts/install-ohif.sh"
grep -q "dataSources" ohif/app-config.js || error "ohif/app-config.js inválido: sem dataSources (formato OHIF v3)"
ok "ohif/app-config.js validado"

# Validar docker-compose.yml
[ -f "docker/docker-compose.yml" ] || error "docker/docker-compose.yml não encontrado"

cd docker
log "Baixando imagens..."
$COMPOSE pull 2>/dev/null || warn "Algumas imagens não puderam ser baixadas (verifique a API)"
log "Subindo containers..."
$COMPOSE up -d --build --remove-orphans
cd "$PROJECT_DIR"
ok "Containers iniciados"

# Aguardar containers estabilizarem
log "Aguardando containers estabilizarem (30s)..."
sleep 30

# ── SSL Let's Encrypt ─────────────────────────────────────────────────────────
if [[ "${GENERATE_SSL:-yes}" == "yes" ]]; then
    section "Gerando certificado SSL"
    bash scripts/generate-ssl.sh
    nginx -t && systemctl reload nginx
    ok "SSL configurado para: ${DOMAIN}"
fi

# ── Healthcheck automático (critério de aceite) ───────────────────────────────
section "Healthcheck — validando stack completa"
log "Aguardando 10s adicionais para serviços estabilizarem..."
sleep 10

if bash scripts/healthcheck.sh; then
    HEALTH_EXIT=0
else
    HEALTH_EXIT=$?
fi

# ── Resultado final ───────────────────────────────────────────────────────────
section "Instalação concluída!"
echo -e "${GREEN}${BOLD}"
echo "  ✅ VOXEL PACS v1.0 instalado com sucesso!"
echo "  🌐 OHIF Viewer:      https://${DOMAIN}"
echo "  🔗 API VOXEL PACS:   https://${DOMAIN}/api"
echo "  🏥 Orthanc:          http://127.0.0.1:8042 (apenas local)"
echo "  🗄️  PostgreSQL:       127.0.0.1:5432 (apenas Docker network)"
echo ""
echo "  📋 Comandos úteis:"
echo "     bash scripts/healthcheck.sh   — verificar saúde"
echo "     bash scripts/update.sh        — atualizar"
echo "     bash scripts/backup.sh        — backup"
echo "     bash scripts/restore.sh       — restaurar"
echo "     bash scripts/rollback.sh      — reverter versão"
echo -e "${NC}"

exit ${HEALTH_EXIT}
