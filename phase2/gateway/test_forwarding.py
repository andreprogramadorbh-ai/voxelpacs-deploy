#!/usr/bin/env python3
from pathlib import Path
import tempfile
import threading
import time

from pydicom.dataset import Dataset, FileMetaDataset
from pydicom.uid import ExplicitVRLittleEndian, generate_uid
from pynetdicom import AE, AllStoragePresentationContexts, VerificationPresentationContexts, evt
from pynetdicom.sop_class import CTImageStorage

from app.gateway import Gateway

SOURCE = Path(__file__).parent / "config" / "tenants.example.yaml"
received = []


def on_store(event):
    received.append(event.dataset.SOPInstanceUID)
    return 0x0000


def synthetic_dataset():
    ds = Dataset()
    ds.SOPClassUID = CTImageStorage
    ds.SOPInstanceUID = generate_uid()
    ds.PatientName = "SYNTHETIC^ONLY"
    ds.PatientID = "SYNTHETIC-DO-NOT-USE"
    ds.StudyInstanceUID = generate_uid()
    ds.SeriesInstanceUID = generate_uid()
    ds.Modality = "CT"
    ds.Rows = 1
    ds.Columns = 1
    ds.SamplesPerPixel = 1
    ds.PhotometricInterpretation = "MONOCHROME2"
    ds.BitsAllocated = 8
    ds.BitsStored = 8
    ds.HighBit = 7
    ds.PixelRepresentation = 0
    ds.PixelData = b"\x00"
    ds.file_meta = FileMetaDataset()
    ds.file_meta.TransferSyntaxUID = ExplicitVRLittleEndian
    return ds


def client_association(calling_ae: str):
    client = AE(ae_title=calling_ae)
    client.add_requested_context(CTImageStorage, ExplicitVRLittleEndian)
    return client.associate("127.0.0.1", 11112, ae_title="VOXEL_GW_A")


def main():
    backend = AE(ae_title="VOXEL_A_PACS")
    for context in VerificationPresentationContexts + AllStoragePresentationContexts:
        backend.add_supported_context(context.abstract_syntax, context.transfer_syntax)
    backend_server = backend.start_server(("127.0.0.1", 11113), block=False, evt_handlers=[(evt.EVT_C_STORE, on_store)])
    try:
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "tenants.yaml"
            logs = Path(tmp) / "audit.jsonl"
            text = SOURCE.read_text(encoding="utf-8")
            text = text.replace("  - key: \"cliente-a\"\n    enabled: false", "  - key: \"cliente-a\"\n    enabled: true", 1)
            text = text.replace("10.200.10.2/32", "127.0.0.1/32")
            text = text.replace("port: 4242\n  ae_title", "port: 11112\n  ae_title", 1)
            text = text.replace("port: 4244", "port: 11113", 1)
            text = text.replace("host: \"10.0.0.3\"", "host: \"127.0.0.1\"", 1)
            text = text.replace("/var/log/voxelpacs-gateway/association-audit.jsonl", str(logs))
            config.write_text(text, encoding="utf-8")
            gateway = Gateway(config)
            thread = threading.Thread(target=gateway.serve, daemon=True)
            thread.start()
            time.sleep(0.4)

            rejected = client_association("UNKNOWN")
            try:
                assert not rejected.is_established, "gateway accepted an unauthorized association"
            finally:
                if rejected.is_established:
                    rejected.release()

            assoc = client_association("CLIENTE_A_MOD")
            assert assoc.is_established, f"gateway did not accept authorized association; audit={logs.read_text(encoding='utf-8')}"
            try:
                status = assoc.send_c_store(synthetic_dataset())
            finally:
                assoc.release()
            assert status and int(status.Status) == 0x0000, f"unexpected C-STORE status: {status}"
            deadline = time.time() + 2
            while not received and time.time() < deadline:
                time.sleep(0.05)
            assert len(received) == 1, "backend did not receive synthetic C-STORE"
            audit = logs.read_text(encoding="utf-8")
            assert '"outcome":"forwarded"' in audit
            assert '"service":"ASSOCIATION"' in audit
            assert "SYNTHETIC" not in audit
            gateway.aes["default"].shutdown()
    finally:
        backend_server.shutdown()
    print("GATEWAY_FORWARDING_TEST_OK")


if __name__ == "__main__":
    main()
