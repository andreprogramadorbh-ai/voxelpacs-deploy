#!/usr/bin/env python3
"""VOXEL PACS DICOM Gateway.

The gateway accepts only C-ECHO and C-STORE for explicitly enabled tenant
routes. It never stores DICOM objects and its audit trail excludes patient
attributes and DICOM UIDs.
"""
from __future__ import annotations

import ipaddress
import json
import logging
import signal
import ssl
import sys
import threading
from dataclasses import dataclass
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

import yaml
from pynetdicom import AE, AllStoragePresentationContexts, VerificationPresentationContexts, evt

LOG = logging.getLogger("voxelpacs.gateway")
SUPPORTED_SERVICES = frozenset({"C_ECHO", "C_STORE"})
SUPPORTED_PROFILES = frozenset({"vpn_mtls", "vpn_only", "site_router"})


@dataclass(frozen=True)
class Listener:
    key: str
    bind_address: str
    port: int
    ae_title: str
    maximum_associations: int
    acse_timeout_seconds: int
    dimse_timeout_seconds: int
    network_timeout_seconds: int
    allowed_profiles: frozenset[str]
    tls: dict[str, Any]


@dataclass(frozen=True)
class TenantRoute:
    key: str
    profile: str
    listener: str
    called_ae: str
    source_calling_aets: frozenset[str]
    source_networks: tuple[ipaddress.IPv4Network | ipaddress.IPv6Network, ...]
    allowed_services: frozenset[str]
    backend_host: str
    backend_port: int
    backend_called_ae: str
    backend_calling_ae: str


def normalized_ae(value: Any) -> str:
    if isinstance(value, bytes):
        return value.decode("ascii", errors="ignore").strip().upper()
    return str(value or "").strip().upper()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


class Gateway:
    def __init__(self, config_path: Path, prepare_audit_path: bool = True) -> None:
        self.config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
        if not isinstance(self.config, dict):
            raise ValueError("A configuração do gateway deve ser um objeto YAML")
        self.audit_path = Path(self.config["audit"]["log_file"])
        if prepare_audit_path:
            self.audit_path.parent.mkdir(parents=True, exist_ok=True)
        self._audit_lock = threading.Lock()
        self.listeners = self._load_listeners()
        self.routes = self._load_routes(self.config.get("tenants", []))
        self._validate_policy()
        self.aes = {listener.key: self._build_ae(listener) for listener in self.listeners.values()}

    def _load_listeners(self) -> dict[str, Listener]:
        rows = self.config.get("listeners")
        if rows is None:
            # Compatibilidade com o modelo de listener único anterior.
            rows = [{"key": "default", **self.config["server"], "allowed_profiles": list(SUPPORTED_PROFILES)}]
        listeners: dict[str, Listener] = {}
        for row in rows:
            key = str(row["key"])
            if key in listeners:
                raise ValueError(f"Listener duplicado: {key}")
            profiles = frozenset(str(item) for item in row.get("allowed_profiles", []))
            listeners[key] = Listener(
                key=key,
                bind_address=str(row.get("bind_address", "0.0.0.0")),
                port=int(row.get("port", 4242)),
                ae_title=normalized_ae(row["ae_title"]),
                maximum_associations=int(row.get("maximum_associations", 16)),
                acse_timeout_seconds=int(row.get("acse_timeout_seconds", 15)),
                dimse_timeout_seconds=int(row.get("dimse_timeout_seconds", 60)),
                network_timeout_seconds=int(row.get("network_timeout_seconds", 30)),
                allowed_profiles=profiles,
                tls=dict(row.get("tls", {})),
            )
        if not listeners:
            raise ValueError("Ao menos um listener deve ser configurado")
        return listeners

    def _load_routes(self, rows: list[dict[str, Any]]) -> list[TenantRoute]:
        routes: list[TenantRoute] = []
        for row in rows:
            if not row.get("enabled", False):
                continue
            source_networks = tuple(ipaddress.ip_network(cidr, strict=False) for cidr in row["source_cidrs"])
            backend = row["backend"]
            routes.append(
                TenantRoute(
                    key=str(row["key"]),
                    profile=str(row.get("profile", "vpn_only")),
                    listener=str(row.get("listener", "default")),
                    called_ae=normalized_ae(row["called_ae"]),
                    source_calling_aets=frozenset(normalized_ae(ae) for ae in row["source_calling_aets"]),
                    source_networks=source_networks,
                    allowed_services=frozenset(str(v) for v in row["allowed_services"]),
                    backend_host=str(backend["host"]),
                    backend_port=int(backend["port"]),
                    backend_called_ae=normalized_ae(backend["called_ae"]),
                    backend_calling_ae=normalized_ae(backend["calling_ae"]),
                )
            )
        return routes

    def _validate_policy(self) -> None:
        configured_ports: set[tuple[str, int]] = set()
        for listener in self.listeners.values():
            if not self._valid_ae(listener.ae_title):
                raise ValueError(f"AE Title inválido no listener {listener.key}")
            if not listener.allowed_profiles or not listener.allowed_profiles <= SUPPORTED_PROFILES:
                raise ValueError(f"Perfis inválidos no listener {listener.key}")
            pair = (listener.bind_address, listener.port)
            if pair in configured_ports:
                raise ValueError(f"Endereço/porta duplicado: {listener.bind_address}:{listener.port}")
            configured_ports.add(pair)
            tls_enabled = bool(listener.tls.get("enabled", False))
            if tls_enabled:
                for key in ("certificate_file", "private_key_file", "trusted_ca_file"):
                    if not listener.tls.get(key):
                        raise ValueError(f"TLS habilitado sem {key} no listener {listener.key}")
        seen_tenants: set[str] = set()
        for route in self.routes:
            if route.key in seen_tenants:
                raise ValueError(f"Tenant duplicado: {route.key}")
            seen_tenants.add(route.key)
            if route.profile not in SUPPORTED_PROFILES:
                raise ValueError(f"Perfil inválido para {route.key}")
            listener = self.listeners.get(route.listener)
            if listener is None:
                raise ValueError(f"Listener inexistente para {route.key}: {route.listener}")
            if route.profile not in listener.allowed_profiles:
                raise ValueError(f"Perfil {route.profile} não permitido no listener {route.listener}")
            if route.profile == "vpn_mtls" and not listener.tls.get("enabled", False):
                raise ValueError(f"Tenant mTLS {route.key} requer listener TLS")
            if route.profile != "vpn_mtls" and listener.tls.get("enabled", False):
                raise ValueError(f"Tenant sem mTLS não pode usar listener TLS: {route.key}")
            if not self._valid_ae(route.called_ae) or not route.source_calling_aets or not route.source_networks:
                raise ValueError(f"Identidade de origem incompleta para {route.key}")
            if not self._valid_ae(route.backend_called_ae) or not self._valid_ae(route.backend_calling_ae):
                raise ValueError(f"AE Title de backend inválido para {route.key}")
            if any(not self._valid_ae(item) for item in route.source_calling_aets):
                raise ValueError(f"Calling AE inválido para {route.key}")
            if not route.allowed_services or not route.allowed_services <= SUPPORTED_SERVICES:
                raise ValueError(f"Serviços inválidos para {route.key}")
            if not route.backend_host or not route.backend_called_ae or route.backend_port < 1:
                raise ValueError(f"Backend inválido para {route.key}")

    @staticmethod
    def _valid_ae(value: str) -> bool:
        return bool(value) and len(value) <= 16 and all(char.isupper() or char.isdigit() or char in "_-" for char in value)

    def _build_ae(self, listener: Listener) -> AE:
        ae = AE(ae_title=listener.ae_title)
        # Os Called AE Titles pertencem às rotas de tenant, não a um único processo global.
        ae.require_called_aet = False
        ae.maximum_associations = listener.maximum_associations
        ae.acse_timeout = listener.acse_timeout_seconds
        ae.dimse_timeout = listener.dimse_timeout_seconds
        ae.network_timeout = listener.network_timeout_seconds
        for context in VerificationPresentationContexts + AllStoragePresentationContexts:
            ae.add_supported_context(context.abstract_syntax, context.transfer_syntax)
        return ae

    @staticmethod
    def _request_details(event: Any) -> tuple[str, str, str]:
        requestor = event.assoc.requestor
        acceptor = event.assoc.acceptor
        # Em EVT_REQUESTED os atributos ServiceUser ainda podem não estar
        # preenchidos; o A-ASSOCIATE-RQ recebido já contém ambos os AE Titles.
        primitive = getattr(requestor, "primitive", None)
        calling_ae = normalized_ae(getattr(requestor, "ae_title", ""))
        called_ae = normalized_ae(getattr(acceptor, "ae_title", ""))
        if primitive is not None:
            calling_ae = normalized_ae(getattr(primitive, "calling_ae_title", calling_ae)) or calling_ae
            called_ae = normalized_ae(getattr(primitive, "called_ae_title", called_ae)) or called_ae
        return (str(requestor.address), calling_ae, called_ae)

    def _route_for(self, event: Any, service: str | None, listener_key: str) -> TenantRoute | None:
        source_ip, calling_ae, called_ae = self._request_details(event)
        try:
            address = ipaddress.ip_address(source_ip)
        except ValueError:
            return None
        for route in self.routes:
            if (
                route.listener == listener_key
                and route.called_ae == called_ae
                and calling_ae in route.source_calling_aets
                and any(address in network for network in route.source_networks)
                and (service is None or service in route.allowed_services)
            ):
                return route
        return None

    def _audit(self, outcome: str, service: str, event: Any, listener_key: str, route: TenantRoute | None = None, detail: str = "") -> None:
        source_ip, calling_ae, called_ae = self._request_details(event)
        row = {
            "timestamp": utc_now(),
            "event": "dicom-association",
            "listener": listener_key,
            "profile": route.profile if route else None,
            "service": service,
            "outcome": outcome,
            "source_ip": source_ip,
            "calling_ae": calling_ae,
            "called_ae": called_ae,
            "tenant": route.key if route else None,
            "detail": detail[:120],
        }
        with self._audit_lock:
            with self.audit_path.open("a", encoding="utf-8") as fh:
                fh.write(json.dumps(row, separators=(",", ":")) + "\n")
        LOG.info(
            "listener=%s service=%s outcome=%s tenant=%s source=%s calling=%s called=%s",
            listener_key,
            service,
            outcome,
            row["tenant"],
            source_ip,
            calling_ae,
            called_ae,
        )

    def handle_requested(self, event: Any, listener_key: str) -> None:
        """Reject unknown identities during association negotiation, before DIMSE."""
        route = self._route_for(event, None, listener_key)
        if route is not None:
            return
        self._audit("rejected", "ASSOCIATION", event, listener_key, detail="policy-mismatch")
        # Permanent rejection by service user: do not reveal tenant or network policy details.
        event.assoc.acse.send_reject(0x01, 0x01, 0x03)

    def handle_echo(self, event: Any, listener_key: str) -> int:
        route = self._route_for(event, "C_ECHO", listener_key)
        if route is None:
            self._audit("rejected", "C_ECHO", event, listener_key, detail="policy-mismatch")
            return 0x0122
        self._audit("accepted", "C_ECHO", event, listener_key, route)
        return 0x0000

    def handle_store(self, event: Any, listener_key: str) -> int:
        route = self._route_for(event, "C_STORE", listener_key)
        if route is None:
            self._audit("rejected", "C_STORE", event, listener_key, detail="policy-mismatch")
            return 0xC000
        listener = self.listeners[listener_key]
        try:
            upstream = AE(ae_title=route.backend_calling_ae)
            upstream.acse_timeout = listener.acse_timeout_seconds
            upstream.dimse_timeout = listener.dimse_timeout_seconds
            upstream.network_timeout = listener.network_timeout_seconds
            upstream.add_requested_context(event.context.abstract_syntax, event.context.transfer_syntax)
            association = upstream.associate(route.backend_host, route.backend_port, ae_title=route.backend_called_ae)
            if not association.is_established:
                self._audit("rejected", "C_STORE", event, listener_key, route, "backend-association-failed")
                return 0xA700
            try:
                dataset = event.dataset
                dataset.file_meta = event.file_meta
                status = association.send_c_store(dataset)
            finally:
                association.release()
            if status and int(status.Status) == 0x0000:
                self._audit("forwarded", "C_STORE", event, listener_key, route)
                return 0x0000
            self._audit("rejected", "C_STORE", event, listener_key, route, "backend-store-failed")
            return int(getattr(status, "Status", 0xC000))
        except Exception as exc:  # Deliberately avoid dataset values in logs.
            self._audit("rejected", "C_STORE", event, listener_key, route, type(exc).__name__)
            LOG.exception("C-STORE forwarding failed for tenant=%s", route.key)
            return 0xA700

    def handle_accepted(self, event: Any, listener_key: str) -> None:
        source_ip, calling_ae, called_ae = self._request_details(event)
        LOG.info("listener=%s association-open source=%s calling=%s called=%s", listener_key, source_ip, calling_ae, called_ae)

    @staticmethod
    def tls_context(listener: Listener) -> ssl.SSLContext | None:
        if not listener.tls.get("enabled", False):
            return None
        context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.verify_mode = ssl.CERT_REQUIRED
        context.load_cert_chain(listener.tls["certificate_file"], listener.tls["private_key_file"])
        context.load_verify_locations(listener.tls["trusted_ca_file"])
        return context

    def serve(self) -> None:
        servers = []
        for listener_key, listener in self.listeners.items():
            handlers = [
                (evt.EVT_REQUESTED, self.handle_requested, [listener_key]),
                (evt.EVT_C_ECHO, self.handle_echo, [listener_key]),
                (evt.EVT_C_STORE, self.handle_store, [listener_key]),
                (evt.EVT_ACCEPTED, self.handle_accepted, [listener_key]),
            ]
            LOG.info("starting gateway listener=%s address=%s port=%s configured_routes=%s", listener_key, listener.bind_address, listener.port, sum(route.listener == listener_key for route in self.routes))
            servers.append(self.aes[listener_key].start_server((listener.bind_address, listener.port), block=False, evt_handlers=handlers, ssl_context=self.tls_context(listener)))
        try:
            while True:
                signal.pause()
        finally:
            for server in servers:
                server.shutdown()


class HealthHandler(BaseHTTPRequestHandler):
    gateway: Gateway

    def do_GET(self) -> None:  # noqa: N802
        if self.path != "/healthz":
            self.send_response(404)
            self.end_headers()
            return
        payload = json.dumps({"status": "ok", "routes": len(self.gateway.routes), "listeners": len(self.gateway.listeners), "timestamp": utc_now()}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, _format: str, *_args: object) -> None:
        return


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    if len(sys.argv) not in (2, 3) or (len(sys.argv) == 3 and sys.argv[2] != "--validate"):
        print("usage: gateway.py /etc/voxelpacs-gateway/tenants.yaml [--validate]", file=sys.stderr)
        return 2
    validation_only = len(sys.argv) == 3
    gateway = Gateway(Path(sys.argv[1]), prepare_audit_path=not validation_only)
    if validation_only:
        # Valida schema, rotas habilitadas e material TLS sem abrir sockets.
        # Não lê nem processa objetos DICOM.
        for listener in gateway.listeners.values():
            Gateway.tls_context(listener)
        print(f"GATEWAY_CONFIG_VALID listeners={len(gateway.listeners)} enabled_routes={len(gateway.routes)}")
        return 0
    HealthHandler.gateway = gateway
    health = ThreadingHTTPServer(("127.0.0.1", 8081), HealthHandler)
    threading.Thread(target=health.serve_forever, daemon=True).start()

    def stop(_signal: int, _frame: Any) -> None:
        health.shutdown()
        for ae in gateway.aes.values():
            ae.shutdown()
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    gateway.serve()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
