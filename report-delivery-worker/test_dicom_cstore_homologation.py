#!/usr/bin/env python3
"""Envia apenas um Encapsulated PDF técnico, sem dados clínicos, para homologação C-STORE."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from pydicom.dataset import Dataset, FileDataset
from pydicom.uid import EncapsulatedPDFStorage, ExplicitVRLittleEndian, PYDICOM_IMPLEMENTATION_UID, generate_uid

if len(sys.argv) != 5:
    raise SystemExit("Uso: test_dicom_cstore_homologation.py <host> <port> <called_ae> <calling_ae>")

host, port, called_ae, calling_ae = sys.argv[1:]
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
dataset.PatientName = "TESTE^VOXEL^HOMOLOGACAO"
dataset.PatientID = "VOXEL-HOMOLOG-DICOM-PDF"
dataset.PatientBirthDate = "19000101"
dataset.PatientSex = "O"
dataset.StudyInstanceUID = generate_uid()
dataset.SeriesInstanceUID = generate_uid()
dataset.StudyDate = now.strftime("%Y%m%d")
dataset.StudyTime = now.strftime("%H%M%S")
dataset.AccessionNumber = "VOXELHOMOL001"
dataset.StudyID = "HOMOLOG"
dataset.SeriesNumber = 999
dataset.InstanceNumber = 1
dataset.Modality = "DOC"
dataset.SeriesDescription = "VOXEL PACS - TESTE TECNICO"
dataset.DocumentTitle = "Teste tecnico DICOM Encapsulated PDF"
dataset.ContentDate = now.strftime("%Y%m%d")
dataset.ContentTime = now.strftime("%H%M%S")
dataset.BurnedInAnnotation = "NO"
dataset.MIMETypeOfEncapsulatedDocument = "application/pdf"
dataset.EncapsulatedDocument = b"%PDF-1.4\n% VOXEL PACS TESTE TECNICO SEM DADOS CLINICOS\n1 0 obj\n<<>>\nendobj\n%%EOF\n"

with tempfile.TemporaryDirectory(prefix="voxel-cstore-test-") as temp_dir:
    path = Path(temp_dir) / "teste-tecnico-encapsulated-pdf.dcm"
    dataset.save_as(path, enforce_file_format=True)
    result = subprocess.run(
        ["storescu", "-v", "-aec", called_ae, "-aet", calling_ae, host, str(port), str(path)],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )

if result.returncode != 0:
    detail = (result.stderr or result.stdout or "erro sem detalhe").strip()
    raise SystemExit(f"C-STORE falhou ({result.returncode}): {detail[:1000]}")

print(f"[OK] C-STORE ACEITO; SOPInstanceUID={sop_instance_uid}")
print("Paciente técnico: TESTE^VOXEL^HOMOLOGACAO | PatientID: VOXEL-HOMOLOG-DICOM-PDF")
