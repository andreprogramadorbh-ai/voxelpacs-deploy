#!/usr/bin/env python3
"""Teste local do DICOM Encapsulated PDF sem enviar dados a PACS externo."""

from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path

from pydicom import dcmread
from pydicom.uid import EncapsulatedPDFStorage

root = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("delivery_worker", root / "worker.py")
if spec is None or spec.loader is None:
    raise RuntimeError("Não foi possível carregar worker.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

worker = module.DeliveryWorker.__new__(module.DeliveryWorker)
job = {
    "payload": {
        "study_instance_uid": "2.25.123456789012345678901234567890123456",
        "patient_id": "HOMOLOGACAO-001",
        "patient_name": "TESTE^HOMOLOGACAO",
        "patient_birth_date": "1980-01-02",
        "patient_sex": "O",
        "study_date": "2026-08-14",
        "study_time": "10:30:00",
        "accession_number": "HOMOLOG-001",
    }
}
pdf = b"%PDF-1.4\n% Homologacao VOXEL PACS\n1 0 obj\n<<>>\nendobj\n%%EOF\n"
dataset, uid = worker.build_encapsulated_pdf_dataset(job, pdf)

assert str(dataset.SOPClassUID) == str(EncapsulatedPDFStorage)
assert str(dataset.StudyInstanceUID) == job["payload"]["study_instance_uid"]
assert dataset.PatientID == "HOMOLOGACAO-001"
assert dataset.EncapsulatedDocument == pdf
assert dataset.MIMETypeOfEncapsulatedDocument == "application/pdf"
assert str(dataset.SOPInstanceUID) == uid

with tempfile.TemporaryDirectory() as temp_dir:
    path = Path(temp_dir) / "homologacao.dcm"
    dataset.save_as(path, enforce_file_format=True)
    restored = dcmread(path)
    assert str(restored.SOPClassUID) == str(EncapsulatedPDFStorage)
    assert restored.EncapsulatedDocument == pdf

print("[OK] DICOM Encapsulated PDF válido, sem transmissão externa")
