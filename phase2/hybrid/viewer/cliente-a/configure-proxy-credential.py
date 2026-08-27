#!/usr/bin/env python3
"""Configura credencial exclusiva do proxy OHIF Cliente A sem expor segredo."""
import base64
import json
import os
import secrets
import stat
import sys
from pathlib import Path

if len(sys.argv) not in (3, 4):
    raise SystemExit("uso: configure_client_a_viewer_proxy.py ORTHANC_JSON BASIC_OUTPUT [PASSWORD_FILE]")

config_path = Path(sys.argv[1])
basic_path = Path(sys.argv[2])
password_file = Path(sys.argv[3]) if len(sys.argv) == 4 else None
username = "api_cliente_a_service"

config_stat = config_path.stat()
config = json.loads(config_path.read_text(encoding="utf-8"))
users = config.get("RegisteredUsers")
if not isinstance(users, dict):
    raise SystemExit("RegisteredUsers ausente ou inválido")

if password_file is not None:
    password = password_file.read_text(encoding="utf-8").strip()
    if len(password) < 24:
        raise SystemExit("credencial temporária ausente ou insuficiente")
else:
    password = secrets.token_urlsafe(32)
users[username] = password
config["RegisteredUsers"] = users

tmp_config = config_path.with_suffix(config_path.suffix + ".tmp")
tmp_config.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
os.chmod(tmp_config, stat.S_IMODE(config_stat.st_mode))
os.chown(tmp_config, config_stat.st_uid, config_stat.st_gid)
os.replace(tmp_config, config_path)

basic = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
basic_path.parent.mkdir(parents=True, exist_ok=True)
tmp_basic = basic_path.with_suffix(basic_path.suffix + ".tmp")
tmp_basic.write_text(basic + "\n", encoding="utf-8")
os.chmod(tmp_basic, 0o600)
os.chown(tmp_basic, 0, 0)
os.replace(tmp_basic, basic_path)

if password_file is not None:
    password_file.unlink(missing_ok=True)

print("CLIENT_A_VIEWER_PROXY_CREDENTIAL_CONFIGURED")
