#!/usr/bin/env python3
import importlib.util
import json
import os
import tempfile
import time
import subprocess
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("agent.py")
spec = importlib.util.spec_from_file_location("tenant_agent", MODULE_PATH)
agent = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(agent)


class TenantAgentValidationTest(unittest.TestCase):
    def setUp(self) -> None:
        os.environ["WG_CLIENT_NETWORK"] = "10.200.10.0/24"

    def test_rejects_invalid_public_key(self) -> None:
        with self.assertRaises(agent.AgentError):
            agent.require_public_key("not-a-wireguard-key")

    def test_accepts_standard_wireguard_public_key_shape(self) -> None:
        self.assertEqual(agent.require_public_key("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="), "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")

    def test_rejects_network_address_as_peer(self) -> None:
        with self.assertRaises(agent.AgentError):
            agent.require_vpn_ip("10.200.10.0")

    def test_role_isolation_rejects_gateway_action_on_hybrid(self) -> None:
        os.environ["AGENT_ROLE"] = "hybrid"
        with self.assertRaises(agent.AgentError):
            agent.require_role("gateway")

    def test_echo_validation_requires_matching_recent_audit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            audit_path = Path(directory) / "audit.jsonl"
            now = time.strftime("%Y-%m-%dT%H:%M:%S+00:00", time.gmtime())
            audit_path.write_text(json.dumps({
                "timestamp": now,
                "tenant": "cliente-teste",
                "service": "C_ECHO",
                "outcome": "accepted",
                "source_ip": "10.200.10.9",
                "calling_ae": "CLIENTE_TESTE",
                "called_ae": "VOXEL_GW_T",
            }) + "\n", encoding="utf-8")
            os.environ["AGENT_ROLE"] = "gateway"
            os.environ["GATEWAY_AUDIT_LOG"] = str(audit_path)
            result = agent.check_echo({
                "tenant": "cliente-teste",
                "route_key": "cliente-teste",
                "calling_ae": "CLIENTE_TESTE",
                "called_ae": "VOXEL_GW_T",
                "vpn_client_ip": "10.200.10.9",
                "since": int(time.time()) - 30,
            })
            self.assertEqual(result["status"], "echo_validated")

    def test_api_register_builds_single_transaction_without_live_database(self) -> None:
        os.environ["AGENT_ROLE"] = "api"
        os.environ["API_DB_SCHEMA"] = "voxelpacs_mysql_source"
        os.environ["API_DB_NAME"] = "voxelpacs_homolog"
        captured: list[str] = []
        original_run = agent.run
        def fake_run(command, timeout=180):
            captured.extend(command)
            return subprocess.CompletedProcess(command, 0, "91|92\n", "")
        agent.run = fake_run
        try:
            result = agent.api_db_register({
                "operation_id": "f5d2d760-2297-4ee8-9f2d-4a91267f193a",
                "tenant_id": 3,
                "user_id": 7,
                "tenant": "cliente-teste",
                "route_key": "cliente-teste",
                "display_name": "Orthanc Cliente Teste",
                "backend_ae": "VOXEL_T_PACS",
                "dicom_port": 4248,
                "dicomweb_port": 8048,
                "gateway_public_key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
                "dicomweb_username": "cliente_teste_api",
                "dicomweb_password_ciphertext": "ciphertext-with-minimum-length",
            })
        finally:
            agent.run = original_run
        self.assertEqual(result["server_id"], 91)
        self.assertEqual(result["cell_id"], 92)
        self.assertIn("WITH operation AS", captured[-1])
        self.assertIn("ON CONFLICT (tenant_id,servidor_id)", captured[-1])

    def test_echo_validation_does_not_accept_historical_event(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            audit_path = Path(directory) / "audit.jsonl"
            audit_path.write_text(json.dumps({
                "timestamp": "2020-01-01T00:00:00+00:00",
                "tenant": "cliente-teste",
                "service": "C_ECHO",
                "outcome": "accepted",
                "source_ip": "10.200.10.9",
                "calling_ae": "CLIENTE_TESTE",
                "called_ae": "VOXEL_GW_T",
            }) + "\n", encoding="utf-8")
            os.environ["AGENT_ROLE"] = "gateway"
            os.environ["GATEWAY_AUDIT_LOG"] = str(audit_path)
            result = agent.check_echo({
                "tenant": "cliente-teste",
                "route_key": "cliente-teste",
                "calling_ae": "CLIENTE_TESTE",
                "called_ae": "VOXEL_GW_T",
                "vpn_client_ip": "10.200.10.9",
                "since": int(time.time()) - 30,
            })
            self.assertEqual(result["status"], "pending")


if __name__ == "__main__":
    unittest.main()
