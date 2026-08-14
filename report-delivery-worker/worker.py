#!/usr/bin/env python3
"""VOXEL Report Delivery Worker.

Consome jobs exclusivamente pela API autenticada do servidor VOXEL PACS. Por
padrão roda em modo DRY_RUN e nunca abre conexão com PACS, SFTP ou HTTPS de
clientes. A ativação de qualquer destino exige homologação explícita.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import logging
import os
import socket
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import requests
from pydicom.dataset import Dataset, FileDataset
from pydicom.sequence import Sequence
from pydicom.uid import EncapsulatedPDFStorage, ExplicitVRLittleEndian, PYDICOM_IMPLEMENTATION_UID, generate_uid

API_BASE_URL = os.environ.get("DELIVERY_HUB_API_URL", "https://server.voxelpacs.com.br").rstrip("/")
WORKER_TOKEN = os.environ.get("VOXEL_REPORT_DELIVERY_WORKER_TOKEN", "")
WORKER_ID = os.environ.get("DELIVERY_HUB_WORKER_ID", f"delivery-worker:{socket.gethostname()}")
POLL_SECONDS = max(1, int(os.environ.get("DELIVERY_HUB_POLL_SECONDS", "5")))
DRY_RUN = os.environ.get("DELIVERY_HUB_DRY_RUN", "true").lower() in {"1", "true", "yes"}
DICOM_PDF_ENABLED = os.environ.get("DELIVERY_HUB_DICOM_PDF_ENABLED", "false").lower() in {"1", "true", "yes"}
DICOMWEB_BASE_URL = os.environ.get("DELIVERY_HUB_DICOMWEB_URL", "https://dicom.voxelpacs.com.br/dicom-web").rstrip("/")

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
        if transport == "dicom_pdf":
            return self.send_dicom_encapsulated_pdf(job)

        raise RuntimeError(
            f"Conector '{transport}' não foi ativado. Mantenha DELIVERY_HUB_DRY_RUN=true "
            "até homologar o artefato e o protocolo do cliente."
        )

    def download_pdf_artifact(self, job: dict[str, Any]) -> tuple[bytes, dict[str, Any]]:
        response = self.session.get(
            f"{API_BASE_URL}/api/report-delivery/jobs/{int(job['id'])}/artifact",
            headers={"Accept": "application/pdf"},
            timeout=max(30, int(job.get("timeout_seconds") or 30)),
        )
        response.raise_for_status()
        content = response.content
        if len(content) < 100 or not content.startswith(b"%PDF"):
            raise RuntimeError("API não retornou um PDF clínico válido para o job DICOM.")

        digest = hashlib.sha256(content).hexdigest()
        expected = response.headers.get("X-Voxel-Artifact-SHA256", "").lower()
        if expected and not secrets_compare(digest, expected):
            raise RuntimeError("Hash do PDF recebido não confere com o informado pela API.")
        return content, {
            "pdf_sha256": digest,
            "pdf_size_bytes": len(content),
            "study_instance_uid": response.headers.get("X-Voxel-Study-Instance-UID", ""),
        }

    def send_dicom_encapsulated_pdf(self, job: dict[str, Any]) -> tuple[str, dict[str, Any]]:
        if not DICOM_PDF_ENABLED:
            raise RuntimeError("Conector DICOM PDF está desabilitado. Defina DELIVERY_HUB_DICOM_PDF_ENABLED=true após homologação.")

        config = json.loads(job.get("configuration_json") or "{}")
        host = str(config.get("host") or "").strip()
        called_ae = str(config.get("called_ae") or "").strip()
        calling_ae = str(config.get("calling_ae") or "VOXEL_PACS").strip()
        port = int(config.get("port") or 0)
        if not host or not called_ae or not calling_ae or not (1 <= port <= 65535):
            raise RuntimeError("Destino DICOM exige host, porta, Called AE e Calling AE válidos.")
        if config.get("use_tls"):
            raise RuntimeError("DICOM TLS ainda não foi homologado para este destino; mantenha-o desabilitado.")
        if not all(0 < len(value) <= 16 and all(char.isalnum() or char in "_ -" for char in value) for value in (called_ae, calling_ae)):
            raise RuntimeError("AE Titles DICOM contêm caracteres inválidos.")

        pdf, metadata = self.download_pdf_artifact(job)
        source_identity = self.fetch_original_study_identity(str(metadata.get("study_instance_uid") or ""))
        dataset, sop_instance_uid = self.build_encapsulated_pdf_dataset(job, pdf, source_identity)
        timeout_seconds = max(5, min(120, int(job.get("timeout_seconds") or 30)))

        with tempfile.TemporaryDirectory(prefix="voxel-dicom-pdf-") as temporary_directory:
            dicom_path = Path(temporary_directory) / "report.pdf.dcm"
            dataset.save_as(str(dicom_path), enforce_file_format=True)
            result = subprocess.run(
                ["storescu", "-aec", called_ae, "-aet", calling_ae, host, str(port), str(dicom_path)],
                capture_output=True,
                text=True,
                timeout=timeout_seconds,
                check=False,
            )
            if result.returncode != 0:
                detail = (result.stderr or result.stdout or "erro sem detalhe").strip().replace("\n", " ")
                raise RuntimeError(f"C-STORE recusado pelo PACS ({result.returncode}): {detail[:400]}")

        metadata.update({
            "mode": "dicom_pdf",
            "sop_class_uid": str(EncapsulatedPDFStorage),
            "sop_instance_uid": sop_instance_uid,
            "called_ae": called_ae,
            "calling_ae": calling_ae,
            "remote_host": host,
            "remote_port": port,
        })
        return f"dicom:{sop_instance_uid}", metadata

    def fetch_original_study_identity(self, study_uid: str) -> dict[str, str]:
        if not study_uid:
            raise RuntimeError("StudyInstanceUID ausente para consulta DICOMweb do estudo original.")
        response = requests.get(
            f"{DICOMWEB_BASE_URL}/studies/{study_uid}/metadata",
            headers={"Accept": "application/dicom+json", "User-Agent": "VOXEL-Report-Delivery-Worker/1.0"},
            timeout=30,
        )
        response.raise_for_status()
        metadata = response.json()
        item = metadata[0] if isinstance(metadata, list) and metadata else metadata
        if not isinstance(item, dict):
            raise RuntimeError("DICOMweb não retornou metadados válidos do estudo original.")

        def value(tag: str) -> str:
            entry = item.get(tag, {})
            values = entry.get("Value", []) if isinstance(entry, dict) else []
            if not values:
                return ""
            raw = values[0]
            if isinstance(raw, dict):
                return str(raw.get("Alphabetic") or "")
            return str(raw)

        identity = {
            "patient_name": value("00100010"),
            "patient_id": value("00100020"),
            "patient_birth_date": value("00100030"),
            "patient_sex": value("00100040"),
            "issuer_of_patient_id": value("00100021"),
            "study_date": value("00080020"),
            "study_time": value("00080030"),
            "accession_number": value("00080050"),
            "study_id": value("00200010"),
            "institution_name": value("00080080"),
            "study_description": value("00081030"),
            "referring_physician_name": value("00080090"),
        }
        if not identity["patient_id"] or not identity["patient_name"]:
            raise RuntimeError("Metadados DICOM originais incompletos para devolutiva clínica.")
        return identity

    def build_encapsulated_pdf_dataset(
        self,
        job: dict[str, Any],
        pdf: bytes,
        source_identity: dict[str, str] | None = None,
    ) -> tuple[FileDataset, str]:
        payload = job.get("payload") or {}
        if not isinstance(payload, dict):
            raise RuntimeError("Payload clínico inválido para o artefato DICOM.")
        study_uid = str(payload.get("study_instance_uid") or "").strip()
        if not study_uid:
            raise RuntimeError("StudyInstanceUID ausente no snapshot do job.")

        now = datetime.now(timezone.utc)
        sop_instance_uid = generate_uid()
        file_meta = Dataset()
        file_meta.MediaStorageSOPClassUID = EncapsulatedPDFStorage
        file_meta.MediaStorageSOPInstanceUID = sop_instance_uid
        file_meta.TransferSyntaxUID = ExplicitVRLittleEndian
        file_meta.ImplementationClassUID = PYDICOM_IMPLEMENTATION_UID

        dataset = FileDataset(None, {}, file_meta=file_meta, preamble=b"\0" * 128)
        dataset.SpecificCharacterSet = "ISO_IR 192"
        dataset.SOPClassUID = EncapsulatedPDFStorage
        dataset.SOPInstanceUID = sop_instance_uid
        identity = source_identity or {}
        dataset.PatientName = str(identity.get("patient_name") or payload.get("patient_name") or "")
        dataset.PatientID = str(identity.get("patient_id") or payload.get("patient_id") or "")
        issuer_of_patient_id = str(identity.get("issuer_of_patient_id") or payload.get("issuer_of_patient_id") or "").strip()
        if issuer_of_patient_id:
            dataset.IssuerOfPatientID = issuer_of_patient_id[:64]
        dataset.PatientBirthDate = normalize_dicom_date(str(identity.get("patient_birth_date") or payload.get("patient_birth_date") or ""))
        dataset.PatientSex = str(identity.get("patient_sex") or payload.get("patient_sex") or "")[:1].upper()
        dataset.StudyInstanceUID = study_uid
        dataset.SeriesInstanceUID = generate_uid()
        dataset.StudyDate = normalize_dicom_date(str(identity.get("study_date") or payload.get("study_date") or ""))
        dataset.StudyTime = normalize_dicom_time(str(identity.get("study_time") or payload.get("study_time") or ""))
        dataset.AccessionNumber = normalize_dicom_sh(str(identity.get("accession_number") or payload.get("accession_number") or ""))
        dataset.ReferringPhysicianName = str(identity.get("referring_physician_name") or "")
        dataset.StudyID = normalize_dicom_sh(str(identity.get("study_id") or ""))
        dataset.InstitutionName = str(identity.get("institution_name") or "")
        dataset.StudyDescription = str(identity.get("study_description") or "")
        dataset.SeriesNumber = 999
        dataset.InstanceNumber = 1
        dataset.Modality = "DOC"
        dataset.SeriesDescription = "Laudo Médico"
        dataset.Manufacturer = "VOXEL PACS"
        dataset.ManufacturerModelName = "VOXEL Report Delivery Hub"
        dataset.SoftwareVersions = "1.0"
        dataset.ConversionType = "WSD"
        dataset.SecondaryCaptureDeviceManufacturer = "VOXEL PACS"
        dataset.SecondaryCaptureDeviceSoftwareVersions = "1.0"
        dataset.DocumentTitle = "Laudo Radiológico"
        dataset.ConceptNameCodeSequence = Sequence([])
        dataset.ContentDate = now.strftime("%Y%m%d")
        dataset.ContentTime = now.strftime("%H%M%S")
        dataset.AcquisitionDateTime = now.strftime("%Y%m%d%H%M%S+0000")
        dataset.InstanceCreationDate = now.strftime("%Y%m%d")
        dataset.InstanceCreationTime = now.strftime("%H%M%S")
        dataset.BurnedInAnnotation = "NO"
        dataset.MIMETypeOfEncapsulatedDocument = "application/pdf"
        dataset.EncapsulatedDocument = pdf
        dataset.EncapsulatedDocumentLength = len(pdf)
        return dataset, sop_instance_uid

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


def normalize_dicom_date(value: str) -> str:
    return "".join(char for char in value if char.isdigit())[:8]


def normalize_dicom_time(value: str) -> str:
    return "".join(char for char in value if char.isdigit())[:6]


def normalize_dicom_sh(value: str) -> str:
    return value.strip()[:16]


def secrets_compare(left: str, right: str) -> bool:
    return hmac.compare_digest(left, right)


if __name__ == "__main__":
    DeliveryWorker().run()
