#!/usr/bin/env python3
"""VOXEL Report Delivery Worker.

Consome jobs exclusivamente pela API autenticada do servidor VOXEL PACS. Por
padrão roda em modo DRY_RUN e nunca abre conexão com PACS, SFTP ou HTTPS de
clientes. A ativação de qualquer destino exige homologação explícita.
"""

from __future__ import annotations

import json
import logging
import os
import socket
import time
from typing import Any

import requests

API_BASE_URL = os.environ.get("DELIVERY_HUB_API_URL", "https://server.voxelpacs.com.br").rstrip("/")
WORKER_TOKEN = os.environ.get("VOXEL_REPORT_DELIVERY_WORKER_TOKEN", "")
WORKER_ID = os.environ.get("DELIVERY_HUB_WORKER_ID", f"delivery-worker:{socket.gethostname()}")
POLL_SECONDS = max(1, int(os.environ.get("DELIVERY_HUB_POLL_SECONDS", "5")))
DRY_RUN = os.environ.get("DELIVERY_HUB_DRY_RUN", "true").lower() in {"1", "true", "yes"}

logging.basicConfig(
    level=os.environ.get("DELIVERY_HUB_LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
LOGGER = logging.getLogger("voxel.report_delivery")


class DeliveryWorker:
    def __init__(self) -> None:
        if len(WORKER_TOKEN) < 32:
            raise RuntimeError("VOXEL_REPORT_DELIVERY_WORKER_TOKEN deve ter ao menos 32 caracteres.")
        self.session = requests.Session()
        self.session.headers.update(
            {
                "Authorization": f"Bearer {WORKER_TOKEN}",
                "X-Voxel-Worker-Id": WORKER_ID,
                "Accept": "application/json",
                "Content-Type": "application/json",
                "User-Agent": "VOXEL-Report-Delivery-Worker/1.0",
            }
        )

    def request(self, method: str, path: str, **kwargs: Any) -> dict[str, Any]:
        response = self.session.request(method, f"{API_BASE_URL}{path}", timeout=30, **kwargs)
        response.raise_for_status()
        payload = response.json()
        if not payload.get("success"):
            raise RuntimeError(payload.get("message", "A API do Delivery Hub retornou falha."))
        return payload

    def lease(self) -> dict[str, Any] | None:
        # O corpo JSON explícito mantém compatibilidade com a política ModSecurity
        # da hospedagem compartilhada, que rejeita POST vazio neste endpoint.
        return self.request("POST", "/api/report-delivery/lease", json={}).get("job")

    def complete(self, job_id: int, reference: str, metadata: dict[str, Any]) -> None:
        self.request(
            "POST",
            f"/api/report-delivery/jobs/{job_id}/complete",
            json={"remote_reference": reference, "metadata": metadata},
        )

    def fail(self, job_id: int, error: str, metadata: dict[str, Any]) -> None:
        self.request("POST", f"/api/report-delivery/jobs/{job_id}/fail", json={"error": error, "metadata": metadata})

    def process(self, job: dict[str, Any]) -> tuple[str, dict[str, Any]]:
        transport = job.get("transport", "")
        destination = job.get("destination_name", "destino")
        if DRY_RUN:
            return (
                f"dry-run:{transport}:{job['id']}",
                {
                    "mode": "dry_run",
                    "transport": transport,
                    "destination": destination,
                    "report_id": job.get("report_id"),
                    "report_version": job.get("report_version"),
                },
            )

        if transport == "https_webhook":
            return self.send_https_webhook(job)

        raise RuntimeError(
            f"Conector '{transport}' não foi ativado. Mantenha DELIVERY_HUB_DRY_RUN=true "
            "até homologar o artefato e o protocolo do cliente."
        )

    def send_https_webhook(self, job: dict[str, Any]) -> tuple[str, dict[str, Any]]:
        config = json.loads(job.get("configuration_json") or "{}")
        endpoint = config.get("url")
        if not isinstance(endpoint, str) or not endpoint.startswith("https://"):
            raise RuntimeError("Destino HTTPS exige configuration_json.url usando HTTPS.")

        secret = json.loads(job.get("configuration_secret") or "{}")
        headers = {
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": "VOXEL-Report-Delivery-Worker/1.0",
            "X-Voxel-Delivery-Id": str(job["id"]),
        }
        if isinstance(secret.get("bearer_token"), str) and secret["bearer_token"]:
            headers["Authorization"] = f"Bearer {secret['bearer_token']}"

        body = {
            "event": job.get("event_type"),
            "delivery_id": job.get("id"),
            "payload": job.get("payload", {}),
        }
        # Não reutilizar self.session: ela possui o bearer exclusivo da API interna
        # e esse token jamais deve ser enviado a um endpoint de cliente.
        response = requests.post(endpoint, json=body, headers=headers, timeout=int(job.get("timeout_seconds") or 30))
        if response.status_code < 200 or response.status_code >= 300:
            raise RuntimeError(f"Destino HTTPS respondeu HTTP {response.status_code}.")

        reference = response.headers.get("X-Request-Id") or response.headers.get("X-Correlation-Id") or f"http:{response.status_code}"
        return reference[:255], {"mode": "https_webhook", "http_status": response.status_code}

    def run(self) -> None:
        LOGGER.info("worker iniciado id=%s api=%s dry_run=%s", WORKER_ID, API_BASE_URL, DRY_RUN)
        while True:
            try:
                job = self.lease()
                if not job:
                    time.sleep(POLL_SECONDS)
                    continue
                job_id = int(job["id"])
                try:
                    reference, metadata = self.process(job)
                    self.complete(job_id, reference, metadata)
                    LOGGER.info("job entregue id=%s transport=%s reference=%s", job_id, job.get("transport"), reference)
                except Exception as exc:  # não interrompe a fila por falha individual
                    LOGGER.exception("job falhou id=%s", job_id)
                    self.fail(job_id, str(exc), {"worker_id": WORKER_ID, "transport": job.get("transport")})
            except requests.RequestException as exc:
                LOGGER.warning("API indisponível: %s", exc)
                time.sleep(max(POLL_SECONDS, 15))
            except Exception as exc:
                LOGGER.exception("falha inesperada do worker: %s", exc)
                time.sleep(max(POLL_SECONDS, 15))


if __name__ == "__main__":
    DeliveryWorker().run()
