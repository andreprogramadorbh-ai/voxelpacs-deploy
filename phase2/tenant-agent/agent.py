#!/usr/bin/env python3
"""Agente operacional restrito do VOXEL PACS.

Recebe ordens autenticadas exclusivamente da API privada e executa uma allowlist
estreita de operações em hosts autorizados. Não recebe, lê ou registra atributos
DICOM, UIDs, credenciais de Orthanc, chaves privadas WireGuard ou objetos clínicos.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import ipaddress
import json
import os
import re
import ssl
import subprocess
import tempfile
import time
import uuid
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

import yaml

AE_RE = re.compile(r"^[A-Z0-9_-]{1,16}$")
SLUG_RE = re.compile(r"^[a-z][a-z0-9-]{1,30}$")
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f-]{27,36}$")
ALLOWED_ACTIONS = frozenset({"provision_cell", "configure_wireguard_echo", "register_control_plane", "enable_cstore", "suspend_route", "check_echo"})


def require_role(expected: str) -> None:
    if env("AGENT_ROLE") != expected:
        raise AgentError("Ação encaminhada ao host operacional incorreto.")


class AgentError(RuntimeError):
    """Erro seguro, apto a ser exibido ao operador sem vazar segredos."""


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def utc_ts() -> int:
    return int(time.time())


def audit(event: str, **fields: Any) -> None:
    allowed = {"operation_id", "tenant", "action", "status", "step", "code", "profile", "route_key"}
    payload = {"ts": utc_ts(), "event": event, **{k: str(v)[:120] for k, v in fields.items() if k in allowed}}
    log_path = Path(env("AUDIT_LOG", "/var/log/voxelpacs/tenant-agent.jsonl"))
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, separators=(",", ":")) + "\n")


def public_error(exc: Exception) -> tuple[str, str]:
    if isinstance(exc, AgentError):
        return (str(exc), "operation_rejected")
    if isinstance(exc, subprocess.TimeoutExpired):
        return ("A operação excedeu o tempo técnico esperado.", "operation_timeout")
    return ("A operação não foi concluída. Consulte o diagnóstico técnico seguro.", "operation_failed")


def run(command: list[str], timeout: int = 180) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout, check=False)
    if result.returncode != 0:
        raise AgentError("Falha na etapa operacional solicitada.")
    return result


def require_root() -> None:
    if os.geteuid() != 0:
        raise RuntimeError("O agente deve executar como root.")


def require_slug(value: Any) -> str:
    value = str(value or "").strip()
    if not SLUG_RE.fullmatch(value):
        raise AgentError("Identificador técnico do tenant inválido.")
    return value


def require_ae(value: Any, label: str) -> str:
    value = str(value or "").strip().upper()
    if not AE_RE.fullmatch(value):
        raise AgentError(f"{label} inválido.")
    return value


def require_port(value: Any) -> int:
    try:
        port = int(value)
    except (TypeError, ValueError) as exc:
        raise AgentError("Porta privada inválida.") from exc
    if not 1024 <= port <= 65535:
        raise AgentError("Porta privada fora da faixa permitida.")
    return port


def require_vpn_ip(value: Any) -> str:
    try:
        address = ipaddress.ip_address(str(value))
    except ValueError as exc:
        raise AgentError("Endereço WireGuard inválido.") from exc
    allowed = ipaddress.ip_network(env("WG_CLIENT_NETWORK", "10.200.10.0/24"), strict=False)
    if address not in allowed or address in {allowed.network_address, allowed.broadcast_address}:
        raise AgentError("Endereço WireGuard fora da faixa permitida.")
    return str(address)


def require_public_key(value: Any) -> str:
    value = str(value or "").strip()
    try:
        raw = base64.b64decode(value, validate=True)
    except Exception as exc:
        raise AgentError("Chave pública WireGuard inválida.") from exc
    if len(raw) != 32:
        raise AgentError("Chave pública WireGuard inválida.")
    return value


def safe_uuid(value: Any) -> str:
    value = str(value or "").strip().lower()
    if not UUID_RE.fullmatch(value):
        raise AgentError("Identificador de operação inválido.")
    return value


def write_backup_contract(tenant: str) -> None:
    contracts = Path("/etc/voxelpacs-backup/tenants")
    contracts.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = contracts / f"{tenant}.env"
    if path.exists():
        return
    content = "\n".join([
        f"BACKUP_NAMESPACE={tenant}",
        "BACKUP_ENABLED=false",
        "RETENTION_DAYS=30",
        "RETENTION_PRUNE_APPROVED=false",
        "",
    ])
    path.write_text(content, encoding="utf-8")
    path.chmod(0o600)


def install_backup_units() -> None:
    service = Path("/etc/systemd/system/voxelpacs-backup@.service")
    timer = Path("/etc/systemd/system/voxelpacs-backup@.timer")
    backup = env("BACKUP_SCRIPT", "/opt/voxelpacs/phase2/operations/backup/backup-tenant.sh")
    if not Path(backup).is_file():
        raise AgentError("Script de backup por tenant não está instalado no host híbrido.")
    if not service.exists():
        service.write_text("[Unit]\nDescription=VOXEL PACS backup tenant %i\nAfter=docker.service\n\n[Service]\nType=oneshot\nUser=root\nExecStart=" + backup + " --tenant %i\n", encoding="utf-8")
        service.chmod(0o644)
    if not timer.exists():
        timer.write_text("[Unit]\nDescription=VOXEL PACS backup schedule tenant %i\n\n[Timer]\nOnCalendar=*-*-* 02:15:00\nRandomizedDelaySec=45m\nPersistent=true\nUnit=voxelpacs-backup@%i.service\n\n[Install]\nWantedBy=timers.target\n", encoding="utf-8")
        timer.chmod(0o644)
    run(["/bin/systemctl", "daemon-reload"], timeout=30)


def provision_cell(payload: dict[str, Any]) -> dict[str, Any]:
    require_role("hybrid")
    tenant = require_slug(payload.get("tenant"))
    if payload.get("profile") != "vpn_only":
        raise AgentError("A automação atual aceita somente o perfil vpn_only.")
    backend_ae = require_ae(payload.get("backend_ae"), "AE do backend")
    called_ae = require_ae(payload.get("called_ae"), "Called AE")
    dicom_port = require_port(payload.get("dicom_port"))
    dicomweb_port = require_port(payload.get("dicomweb_port"))
    if dicom_port == dicomweb_port:
        raise AgentError("As portas DICOM e DICOMweb devem ser distintas.")
    bootstrap = env("BOOTSTRAP_SCRIPT", "/opt/voxelpacs/phase2/hybrid/bootstrap-tenant.sh")
    if not Path(bootstrap).is_file():
        raise AgentError("Bootstrap de célula tenant não instalado no host híbrido.")
    result = run([
        bootstrap, "--tenant", tenant, "--profile", "vpn_only",
        "--dicom-port", str(dicom_port), "--dicomweb-port", str(dicomweb_port),
        "--backend-ae", backend_ae, "--gateway-called-ae", called_ae,
        "--gateway-private-ip", env("GATEWAY_PRIVATE_IP", "10.0.0.4"),
        "--api-private-ip", env("API_PRIVATE_IP", "10.0.0.2"),
        "--host-private-ip", env("HOST_PRIVATE_IP", "10.0.0.3"), "--start",
    ], timeout=300)
    # O bootstrap não pode ser usado como mecanismo de retorno de segredo.
    if "TENANT_BOOTSTRAP_COMPLETE" not in result.stdout:
        raise AgentError("Bootstrap não confirmou a criação da célula.")
    write_backup_contract(tenant)
    install_backup_units()
    run(["/bin/systemctl", "disable", "--now", f"voxelpacs-backup@{tenant}.timer"], timeout=30)
    # A credencial recém-criada é devolvida somente pela conexão mTLS autenticada
    # para ser cifrada pela API. Nunca entra em auditoria nem na resposta web.
    tenant_env: dict[str, str] = {}
    for line in Path(f"/etc/voxelpacs/tenants/{tenant}/tenant.env").read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            tenant_env[key] = value
    username = tenant_env.get("ORTHANC_USER", "")
    password = tenant_env.get("ORTHANC_PASSWORD", "")
    if not username or not password:
        raise AgentError("A credencial de DICOMweb da célula não foi criada.")
    return {
        "tenant": tenant,
        "status": "cell_ready",
        "backup_timer": "installed_disabled",
        "dicomweb_credential": {"username": username, "password": password},
    }


def policy_path() -> Path:
    path = Path(env("GATEWAY_POLICY", "/etc/voxelpacs-gateway/tenants.yaml"))
    if not path.is_file():
        raise AgentError("Política ativa do gateway não encontrada.")
    return path


def validate_policy(temp_path: Path) -> None:
    compose = env("GATEWAY_COMPOSE", "/opt/voxelpacs/gateway/docker-compose.yml")
    if not Path(compose).is_file():
        raise AgentError("Manifesto do gateway não encontrado.")
    # O container monta /tmp e contém dependências Python do gateway. A validação
    # não publica portas porque `docker compose run` não as expõe por padrão.
    run([
        "/usr/bin/docker", "compose", "--env-file", env("GATEWAY_ENV_FILE", "/etc/voxelpacs-gateway/gateway.env"),
        "-p", env("GATEWAY_COMPOSE_PROJECT", "voxelpacs-gateway"),
        "-f", compose, "run", "--rm", "--no-deps", "--entrypoint", "python",
        "dicom-gateway", "/app/gateway.py", f"/tmp/{temp_path.name}", "--validate",
    ], timeout=60)


def gateway_public_key() -> str:
    result = run(["/usr/bin/wg", "show", env("WG_INTERFACE", "wg0"), "public-key"], timeout=10)
    value = result.stdout.strip()
    return require_public_key(value)


def upsert_peer(peer_key: str, vpn_ip: str) -> None:
    interface = env("WG_INTERFACE", "wg0")
    conf = Path(env("WG_CONFIG", "/etc/wireguard/wg0.conf"))
    if not conf.is_file():
        raise AgentError("Configuração WireGuard não encontrada.")
    # O peer é aplicado no kernel e depois persistido no arquivo. Nunca se grava
    # chave privada; apenas a chave pública recebida e o IP /32 reservado.
    run(["/usr/bin/wg", "set", interface, "peer", peer_key, "allowed-ips", f"{vpn_ip}/32"], timeout=20)
    text = conf.read_text(encoding="utf-8")
    marker = f"# voxelpacs-tenant-agent peer {vpn_ip}"
    if marker not in text:
        with conf.open("a", encoding="utf-8") as handle:
            handle.write("\n" + marker + "\n[Peer]\nPublicKey = " + peer_key + "\nAllowedIPs = " + vpn_ip + "/32\n")
        conf.chmod(0o600)


def write_route(payload: dict[str, Any], allow_store: bool = False, enabled: bool = True) -> None:
    tenant = require_slug(payload.get("tenant"))
    route_key = require_slug(payload.get("route_key"))
    calling_ae = require_ae(payload.get("calling_ae"), "Calling AE")
    called_ae = require_ae(payload.get("called_ae"), "Called AE")
    backend_ae = require_ae(payload.get("backend_ae"), "AE do backend")
    vpn_ip = require_vpn_ip(payload.get("vpn_client_ip"))
    dicom_port = require_port(payload.get("dicom_port"))
    path = policy_path()
    document = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(document, dict) or not isinstance(document.get("tenants"), list):
        raise AgentError("Política do gateway inválida.")
    entries = document["tenants"]
    entry = next((item for item in entries if isinstance(item, dict) and item.get("key") == route_key), None)
    if entry is None:
        entry = {"key": route_key}
        entries.append(entry)
    for item in entries:
        if item is not entry and isinstance(item, dict) and item.get("called_ae") == called_ae:
            raise AgentError("Called AE já está reservado para outra rota.")
    entry.update({
        "key": route_key,
        "enabled": bool(enabled),
        "profile": "vpn_only",
        "listener": "vpn-plain",
        "called_ae": called_ae,
        "source_calling_aets": [calling_ae],
        "source_cidrs": [f"{vpn_ip}/32"],
        "allowed_services": ["C_ECHO", "C_STORE"] if allow_store else ["C_ECHO"],
        "backend": {
            "host": env("HYBRID_PRIVATE_IP", "10.0.0.3"),
            "port": dicom_port,
            "called_ae": backend_ae,
            "calling_ae": called_ae,
        },
    })
    with tempfile.NamedTemporaryFile("w", delete=False, encoding="utf-8", dir="/tmp", prefix="tenants.", suffix=".yaml") as handle:
        temp_path = Path(handle.name)
        yaml.safe_dump(document, handle, allow_unicode=False, sort_keys=False)
    try:
        os.chown(temp_path, 0, int(env("GATEWAY_RUNTIME_GID", "10001")))
        os.chmod(temp_path, 0o640)
        validate_policy(temp_path)
        os.replace(temp_path, path)
        run([
            "/usr/bin/docker", "compose", "--env-file", env("GATEWAY_ENV_FILE", "/etc/voxelpacs-gateway/gateway.env"),
            "-p", env("GATEWAY_COMPOSE_PROJECT", "voxelpacs-gateway"),
            "-f", env("GATEWAY_COMPOSE", "/opt/voxelpacs/gateway/docker-compose.yml"),
            "up", "-d", "--no-deps", "dicom-gateway",
        ], timeout=100)
    finally:
        temp_path.unlink(missing_ok=True)


def api_db_schema() -> str:
    schema = env("API_DB_SCHEMA", "public")
    if not re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]{0,62}", schema):
        raise AgentError("Schema administrativo inválido.")
    return schema


def sql_literal(value: Any) -> str:
    if value is None:
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


def api_db_register(payload: dict[str, Any]) -> dict[str, Any]:
    """Registra a célula após ambos agentes concluírem o provisionamento.

    Este é o único ponto de escrita administrativa fora do papel da aplicação.
    A senha é recebida já cifrada pelo Crypto PHP; não há material plaintext no
    banco, na resposta, no journal ou na auditoria do agente.
    """
    require_role("api")
    operation_id = safe_uuid(payload.get("operation_id"))
    tenant_id = int(payload.get("tenant_id") or 0)
    user_id = int(payload.get("user_id") or 0)
    if tenant_id <= 0 or user_id <= 0:
        raise AgentError("Identidade administrativa inválida.")
    tenant = require_slug(payload.get("tenant"))
    route_key = require_slug(payload.get("route_key"))
    display_name = str(payload.get("display_name") or "").strip()
    if not display_name or len(display_name) > 160:
        raise AgentError("Nome do servidor inválido.")
    backend_ae = require_ae(payload.get("backend_ae"), "AE do backend")
    dicom_port = require_port(payload.get("dicom_port"))
    dicomweb_port = require_port(payload.get("dicomweb_port"))
    gateway_key = require_public_key(payload.get("gateway_public_key"))
    username = str(payload.get("dicomweb_username") or "").strip()
    password_ciphertext = str(payload.get("dicomweb_password_ciphertext") or "").strip()
    if not re.fullmatch(r"[a-z][a-z0-9_]{1,62}", username) or len(password_ciphertext) < 24:
        raise AgentError("Credencial interna cifrada inválida.")
    private_url = f"http://10.0.0.3:{dicomweb_port}"
    schema = api_db_schema()
    sql = f"""
BEGIN;
SET LOCAL search_path TO {schema}, public;
WITH operation AS (
    SELECT id FROM bi_pacs_tenant_provisioning
    WHERE operation_id={sql_literal(operation_id)} AND tenant_id={tenant_id} AND status='provisioning'
    FOR UPDATE
), server AS (
    INSERT INTO bi_pacs_servidor (nome,url,usuario,senha,timeout,ativo,dicom_aet,dicom_port,status_ping,observacoes,updated_at)
    SELECT {sql_literal(display_name)},{sql_literal(private_url)},{sql_literal(username)},{sql_literal(password_ciphertext)},30,1,{sql_literal(backend_ae)},{dicom_port},'pendente','Célula exclusiva VPN-only; sincronização automática desabilitada até homologação.',NOW()
    FROM operation RETURNING id
), cell AS (
    INSERT INTO bi_tenant_orthanc_cells (tenant_id,servidor_id,profile,gateway_route_key,status)
    SELECT {tenant_id}, server.id, 'vpn_only', {sql_literal(route_key)}, 'provisioned' FROM server
    RETURNING id
), pivot AS (
    INSERT INTO bi_negocio_servidor_pacs (tenant_id,servidor_id,ativo,criado_por)
    SELECT {tenant_id}, server.id, 1, {user_id} FROM server
    ON CONFLICT (tenant_id,servidor_id) DO UPDATE SET ativo=1
)
UPDATE bi_pacs_tenant_provisioning p
SET servidor_id=server.id, cell_id=cell.id, gateway_public_key={sql_literal(gateway_key)}, status='echo_ready', current_step='awaiting_echo', confirmed_by={user_id}, confirmed_at=NOW(), echo_ready_at=NOW(), updated_at=NOW()
FROM operation, server, cell
WHERE p.id=operation.id
RETURNING server.id AS server_id, cell.id AS cell_id;
COMMIT;
"""
    database = env("API_DB_NAME", "voxelpacs_homolog")
    result = run(["/usr/bin/sudo", "-u", "postgres", "/usr/bin/psql", "-X", "-v", "ON_ERROR_STOP=1", "-tA", "-F", "|", "-d", database, "-c", sql], timeout=45)
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip() and "|" in line]
    if not lines:
        raise AgentError("Registro administrativo não retornou identificadores.")
    server_id, cell_id = lines[-1].split("|", 1)
    if not server_id.isdigit() or not cell_id.isdigit():
        raise AgentError("Registro administrativo retornou identificadores inválidos.")
    return {"status": "echo_ready", "server_id": int(server_id), "cell_id": int(cell_id), "tenant": tenant}


def configure_wireguard_echo(payload: dict[str, Any]) -> dict[str, Any]:
    require_role("gateway")
    peer_key = require_public_key(payload.get("wireguard_public_key"))
    vpn_ip = require_vpn_ip(payload.get("vpn_client_ip"))
    upsert_peer(peer_key, vpn_ip)
    write_route(payload, allow_store=False, enabled=True)
    return {"status": "echo_ready", "gateway_public_key": gateway_public_key(), "vpn_client_ip": vpn_ip}


def enable_cstore(payload: dict[str, Any]) -> dict[str, Any]:
    require_role("gateway")
    write_route(payload, allow_store=True, enabled=True)
    return {"status": "active", "dicom_services": "C_ECHO,C_STORE"}


def suspend_route(payload: dict[str, Any]) -> dict[str, Any]:
    require_role("gateway")
    write_route(payload, allow_store=False, enabled=False)
    return {"status": "suspended"}


def audit_tail(log_path: Path, max_bytes: int = 1_048_576) -> list[str]:
    """Lê apenas o final limitado da auditoria, sem retornar linhas ao cliente."""
    with log_path.open("rb") as handle:
        handle.seek(0, os.SEEK_END)
        size = handle.tell()
        handle.seek(max(0, size - max_bytes), os.SEEK_SET)
        data = handle.read()
    return data.decode("utf-8", errors="ignore").splitlines()[-5000:]


def check_echo(payload: dict[str, Any]) -> dict[str, Any]:
    require_role("gateway")
    tenant = require_slug(payload.get("tenant"))
    route_key = require_slug(payload.get("route_key"))
    calling_ae = require_ae(payload.get("calling_ae"), "Calling AE")
    called_ae = require_ae(payload.get("called_ae"), "Called AE")
    vpn_ip = require_vpn_ip(payload.get("vpn_client_ip"))
    since = int(payload.get("since", 0))
    log_path = Path(env("GATEWAY_AUDIT_LOG", "/var/log/voxelpacs-gateway/audit.jsonl"))
    if not log_path.is_file():
        return {"status": "pending", "diagnostic_code": "ECHO_AUDIT_UNAVAILABLE", "message": "A auditoria técnica do gateway ainda não está disponível."}
    cutoff = max(0, utc_ts() - 7 * 86400, since)
    for line in reversed(audit_tail(log_path)):
        try:
            row = json.loads(line)
            recorded_at = datetime.fromisoformat(str(row.get("timestamp", "")).replace("Z", "+00:00"))
            if recorded_at.tzinfo is None:
                recorded_at = recorded_at.replace(tzinfo=timezone.utc)
            if int(recorded_at.timestamp()) < cutoff:
                continue
            if row.get("tenant") == route_key and row.get("service") == "C_ECHO" and row.get("outcome") == "accepted" and row.get("source_ip") == vpn_ip and row.get("calling_ae") == calling_ae and row.get("called_ae") == called_ae:
                return {"status": "echo_validated", "diagnostic_code": "ECHO_ACCEPTED", "message": "C-ECHO validado pelo gateway."}
        except (ValueError, TypeError, json.JSONDecodeError):
            continue
    return {"status": "pending", "diagnostic_code": "ECHO_AUDIT_NO_MATCH", "message": "Nenhum C-ECHO aceito corresponde ainda ao peer, Calling AE e Called AE cadastrados. Verifique o túnel, os AE Titles e o horário do teste."}


def perform(action: str, payload: dict[str, Any]) -> dict[str, Any]:
    if action == "provision_cell":
        return provision_cell(payload)
    if action == "configure_wireguard_echo":
        return configure_wireguard_echo(payload)
    if action == "register_control_plane":
        return api_db_register(payload)
    if action == "enable_cstore":
        return enable_cstore(payload)
    if action == "suspend_route":
        return suspend_route(payload)
    if action == "check_echo":
        return check_echo(payload)
    raise AgentError("Ação não permitida.")


class Handler(BaseHTTPRequestHandler):
    server_version = "VOXELTenantAgent/1.0"

    def log_message(self, _format: str, *_args: object) -> None:
        return

    def respond(self, code: int, payload: dict[str, Any]) -> None:
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:  # noqa: N802
        if self.path != "/healthz" or self.client_address[0] != env("API_SOURCE_IP", "10.0.0.2"):
            self.respond(HTTPStatus.NOT_FOUND, {"ok": False})
            return
        self.respond(HTTPStatus.OK, {"ok": True, "role": env("AGENT_ROLE")})

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/v1/operations" or self.client_address[0] != env("API_SOURCE_IP", "10.0.0.2"):
            self.respond(HTTPStatus.NOT_FOUND, {"ok": False})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length < 2 or length > 16384:
                raise AgentError("Tamanho de requisição inválido.")
            body = self.rfile.read(length)
            stamp = int(self.headers.get("X-Voxel-Timestamp", "0"))
            nonce = self.headers.get("X-Voxel-Nonce", "")
            signature = self.headers.get("X-Voxel-Signature", "")
            if abs(utc_ts() - stamp) > 120 or not re.fullmatch(r"[0-9a-f]{32,64}", nonce):
                raise AgentError("Ordem expirada ou inválida.")
            secret = Path(env("AUTH_SECRET_FILE", "/etc/voxelpacs-tenant-agent/hmac.key")).read_bytes().strip()
            signed = f"{stamp}.{nonce}.".encode() + body
            expected = hmac.new(secret, signed, hashlib.sha256).hexdigest()
            if not hmac.compare_digest(expected, signature):
                raise AgentError("Assinatura da ordem inválida.")
            nonce_dir = Path(env("NONCE_DIR", "/var/lib/voxelpacs-tenant-agent/nonces"))
            nonce_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
            nonce_file = nonce_dir / hashlib.sha256(nonce.encode()).hexdigest()
            if nonce_file.exists():
                raise AgentError("Ordem já foi processada.")
            nonce_file.touch(mode=0o600, exist_ok=False)
            request = json.loads(body.decode("utf-8"))
            action = str(request.get("action", ""))
            operation_id = safe_uuid(request.get("operation_id"))
            payload = request.get("payload")
            if action not in ALLOWED_ACTIONS or not isinstance(payload, dict):
                raise AgentError("Ordem não permitida.")
            tenant = require_slug(payload.get("tenant"))
            audit("operation_started", operation_id=operation_id, tenant=tenant, action=action, status="started")
            result = perform(action, payload)
            audit("operation_finished", operation_id=operation_id, tenant=tenant, action=action, status="ok")
            self.respond(HTTPStatus.OK, {"ok": True, "operation_id": operation_id, "result": result})
        except Exception as exc:  # resposta deliberadamente sem stdout/stderr ou segredo
            message, code = public_error(exc)
            audit("operation_finished", action="rejected", status="failed", code=code)
            self.respond(HTTPStatus.BAD_REQUEST, {"ok": False, "code": code, "message": message})


def main() -> None:
    require_root()
    role = env("AGENT_ROLE")
    if role not in {"hybrid", "gateway"}:
        raise RuntimeError("AGENT_ROLE inválido.")
    host = env("BIND_HOST")
    port = int(env("BIND_PORT", "8813"))
    if not host or not 1 <= port <= 65535:
        raise RuntimeError("Endereço de bind inválido.")
    certificate = Path(env("TLS_CERT_FILE"))
    private_key = Path(env("TLS_KEY_FILE"))
    client_ca = Path(env("TLS_CLIENT_CA_FILE"))
    if not certificate.is_file() or not private_key.is_file() or not client_ca.is_file():
        raise RuntimeError("Material mTLS interno ausente.")
    context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.verify_mode = ssl.CERT_REQUIRED
    context.load_cert_chain(str(certificate), str(private_key))
    context.load_verify_locations(cafile=str(client_ca))
    server = ThreadingHTTPServer((host, port), Handler)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
