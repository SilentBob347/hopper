from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from .paths import REGISTRY_FILE


def registry_add(
    chain_id: str,
    overlay: str,
    listen_port: int,
    role: str,
    addr: str,
    index: int,
) -> None:
    data = {"chains": []}
    if REGISTRY_FILE.is_file():
        data = json.loads(REGISTRY_FILE.read_text())
    chains = [c for c in data.get("chains", []) if c.get("chain_id") != chain_id]
    chains.append(
        {
            "chain_id": chain_id,
            "overlay": overlay,
            "listen_port": listen_port,
            "role": role,
            "hop_addr": addr,
            "index": index,
            "started_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        }
    )
    REGISTRY_FILE.parent.mkdir(parents=True, exist_ok=True)
    REGISTRY_FILE.write_text(json.dumps({"chains": chains}, indent=2) + "\n")


def registry_remove(chain_id: str) -> None:
    if not REGISTRY_FILE.is_file():
        return
    data = json.loads(REGISTRY_FILE.read_text())
    data["chains"] = [c for c in data.get("chains", []) if c.get("chain_id") != chain_id]
    REGISTRY_FILE.write_text(json.dumps(data, indent=2) + "\n")
