#!/usr/bin/env python3
"""Static safety checks for the reusable hybrid-tenant template."""
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "template"


def main() -> None:
    contract = yaml.safe_load((TEMPLATE / "tenant-contract.example.yaml").read_text(encoding="utf-8"))
    compose = yaml.safe_load((TEMPLATE / "docker-compose.yml").read_text(encoding="utf-8"))
    bootstrap = (ROOT / "bootstrap-tenant.sh").read_text(encoding="utf-8")
    orthanc = (TEMPLATE / "orthanc.json.template").read_text(encoding="utf-8")

    assert contract["tenant"]["profile"] in {"vpn_mtls", "vpn_only", "site_router"}
    assert contract["tenant"]["enabled"] is False
    assert contract["security"]["allow_services"] == ["C_ECHO", "C_STORE"]
    assert contract["backup"]["enabled"] is False

    services = compose["services"]
    assert set(services) == {"postgres", "orthanc"}
    assert "container_name" not in services["postgres"]
    assert "container_name" not in services["orthanc"]
    assert services["postgres"]["networks"] == ["tenant-internal"]
    assert services["orthanc"]["networks"] == ["tenant-internal", "tenant-ingress"]
    assert compose["networks"]["tenant-internal"]["internal"] is True
    assert all("${HOST_PRIVATE_IP" in value for value in services["orthanc"]["ports"])
    assert services["postgres"]["deploy"]["resources"]["limits"]
    assert services["orthanc"]["deploy"]["resources"]["limits"]
    assert "max_connections=${POSTGRES_MAX_CONNECTIONS" in " ".join(services["postgres"]["command"])
    assert "IndexConnectionsCount" in bootstrap
    assert "UseDynamicConnectionPool" in bootstrap
    assert "docker compose" in bootstrap
    assert not any(line.lstrip().startswith("docker-compose ") for line in bootstrap.splitlines())
    assert "--start" in bootstrap
    assert "gateway_route=disabled" in bootstrap
    assert "/var/lib/orthanc/db-v6" in bootstrap
    assert "DicomAlwaysAllowStore\": false" in orthanc
    assert "DicomAllowFind\": false" in orthanc

    print("TENANT_TEMPLATE_STATIC_TEST_OK")


if __name__ == "__main__":
    main()
