#!/usr/bin/env bash
set -euo pipefail

ROOT=/opt/voxelpacs/phase2/hybrid/viewer/cliente-a
ORTHANC_DIR=/opt/voxelpacs/phase2/hybrid/compose/cliente-a
ORTHANC_JSON=/etc/voxelpacs/tenants/cliente-a/orthanc.json
CREDENTIALS_JSON=/etc/voxelpacs/tenants/cliente-a/credentials.json
BASIC_FILE=/etc/voxelpacs/tenants/cliente-a/viewer-proxy.basic
PASSWORD_FILE=/tmp/cliente-a-api-service.password
CONFIGURATOR="$ROOT/configure-proxy-credential.py"
NGINX_TEMPLATE="$ROOT/nginx.conf.template"
NGINX_DEST=/etc/nginx/sites-available/cliente-a-view.conf
NGINX_LINK=/etc/nginx/sites-enabled/cliente-a-view.conf
ACME_TEMP=/etc/nginx/conf.d/cliente-a-viewer-acme.conf

for file in "$ORTHANC_JSON" "$CREDENTIALS_JSON" "$PASSWORD_FILE" "$CONFIGURATOR" "$NGINX_TEMPLATE" "$ROOT/docker-compose.yml" "$ROOT/app-config.js"; do
    [ -f "$file" ] || { echo "arquivo obrigatório ausente: $file" >&2; exit 2; }
done

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
ROLLBACK=/root/voxelpacs-runtime-backups/cliente-a-viewer-$STAMP
install -d -m 0700 "$ROLLBACK"
cp -a "$ORTHANC_JSON" "$ROLLBACK/orthanc.json"
cp -a "$CREDENTIALS_JSON" "$ROLLBACK/credentials.json"
[ -f "$NGINX_DEST" ] && cp -a "$NGINX_DEST" "$ROLLBACK/cliente-a-view.conf" || true
[ -f "$ACME_TEMP" ] && cp -a "$ACME_TEMP" "$ROLLBACK/cliente-a-viewer-acme.conf" || true

python3 -m json.tool "$ORTHANC_JSON" >/dev/null
python3 -m json.tool "$CREDENTIALS_JSON" >/dev/null
python3 "$CONFIGURATOR" "$CREDENTIALS_JSON" "$BASIC_FILE" "$PASSWORD_FILE"
# O configurador preserva UID, GID e modo do arquivo de credenciais existente.
# O proprietário numérico atual corresponde ao usuário orthanc dentro do container.
chmod 0600 "$BASIC_FILE"
chown root:root "$BASIC_FILE"

if ! (cd "$ORTHANC_DIR" && docker compose restart orthanc && docker inspect -f '{{.State.Health.Status}}' voxelpacs-cliente-a-orthanc | grep -qx healthy); then
    cp -a "$ROLLBACK/orthanc.json" "$ORTHANC_JSON"
    cp -a "$ROLLBACK/credentials.json" "$CREDENTIALS_JSON"
    (cd "$ORTHANC_DIR" && docker compose restart orthanc) || true
    echo "reinício Orthanc A falhou; configuração restaurada" >&2
    exit 1
fi

# O container OHIF não contém dados clínicos; ele só aponta ao proxy autenticado.
(cd "$ROOT" && docker compose up -d --pull always)
if ! docker inspect -f '{{.State.Status}}' voxelpacs-cliente-a-ohif | grep -qx running; then
    echo "viewer Cliente A não iniciou" >&2
    exit 1
fi

basic=$(cat "$BASIC_FILE")
sed "s|__ORTHANC_CLIENT_A_API_BASIC__|$basic|g" "$NGINX_TEMPLATE" > "$NGINX_DEST.tmp"
chmod 0644 "$NGINX_DEST.tmp"
ln -sfn "$NGINX_DEST.tmp" "$NGINX_LINK"
if ! nginx -t; then
    rm -f "$NGINX_LINK" "$NGINX_DEST.tmp"
    [ -f "$ROLLBACK/cliente-a-view.conf" ] && cp -a "$ROLLBACK/cliente-a-view.conf" "$NGINX_DEST" || true
    [ -f "$ROLLBACK/cliente-a-view.conf" ] && ln -sfn "$NGINX_DEST" "$NGINX_LINK" || true
    echo "configuração Nginx inválida; origem anterior preservada" >&2
    exit 1
fi
mv "$NGINX_DEST.tmp" "$NGINX_DEST"
ln -sfn "$NGINX_DEST" "$NGINX_LINK"
rm -f "$ACME_TEMP"
nginx -t
systemctl reload nginx

printf 'CLIENT_A_VIEWER_DEPLOYED rollback_dir=%s\n' "$ROLLBACK"
