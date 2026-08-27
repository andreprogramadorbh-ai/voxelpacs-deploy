#!/usr/bin/env python3
from pathlib import Path
from types import SimpleNamespace
import tempfile

from app.gateway import Gateway

SOURCE = Path(__file__).parent / "config" / "tenants.profiles.example.yaml"


def event(source_ip: str, calling: str, called: str, rejections: list[tuple[int, int, int]] | None = None):
    acse = SimpleNamespace(send_reject=lambda result, source, diagnostic: rejections.append((result, source, diagnostic))) if rejections is not None else SimpleNamespace()
    return SimpleNamespace(
        assoc=SimpleNamespace(
            requestor=SimpleNamespace(address=source_ip, ae_title=calling),
            acceptor=SimpleNamespace(ae_title=called),
            acse=acse,
        )
    )


def main():
    with tempfile.TemporaryDirectory() as tmp:
        config = Path(tmp) / "tenants.yaml"
        logs = Path(tmp) / "audit.jsonl"
        text = SOURCE.read_text(encoding="utf-8")
        for tenant in ("cliente-a", "cliente-b", "cliente-c"):
            text = text.replace(
                f'key: "{tenant}"\n    enabled: false',
                f'key: "{tenant}"\n    enabled: true',
                1,
            )
        text = text.replace("/var/log/voxelpacs-gateway/association-audit.jsonl", str(logs))
        config.write_text(text, encoding="utf-8")
        gateway = Gateway(config)
        assert len(gateway.routes) == 3
        assert gateway._route_for(event("10.200.10.2", "PACSFIR", "VOXEL_GW_A"), "C_ECHO", "vpn-mtls")
        assert gateway._route_for(event("10.200.20.2", "CLIENTE_B_ROUTER", "VOXEL_GW_B"), "C_STORE", "vpn-plain")
        assert gateway._route_for(event("10.200.30.2", "CLIENTE_C_ROUTER", "VOXEL_GW_C"), "C_ECHO", "vpn-plain")
        assert gateway._route_for(event("10.200.10.2", "PACSFIR", "VOXEL_GW_A"), "C_ECHO", "vpn-plain") is None
        assert gateway._route_for(event("10.200.20.3", "CLIENTE_B_ROUTER", "VOXEL_GW_B"), "C_ECHO", "vpn-plain") is None
        assert gateway._route_for(event("10.200.20.2", "UNKNOWN", "VOXEL_GW_B"), "C_ECHO", "vpn-plain") is None
        assert gateway._route_for(event("10.200.20.2", "CLIENTE_B_ROUTER", "WRONG_AE"), "C_ECHO", "vpn-plain") is None
        assert gateway._route_for(event("10.200.20.2", "CLIENTE_B_ROUTER", "VOXEL_GW_B"), "C_FIND", "vpn-plain") is None

        rejections: list[tuple[int, int, int]] = []
        gateway.handle_requested(event("10.200.20.3", "CLIENTE_B_ROUTER", "VOXEL_GW_B", rejections), "vpn-plain")
        assert rejections == [(0x01, 0x01, 0x03)]
        assert '"service":"ASSOCIATION"' in logs.read_text(encoding="utf-8")
    print("GATEWAY_POLICY_TEST_OK")


if __name__ == "__main__":
    main()
