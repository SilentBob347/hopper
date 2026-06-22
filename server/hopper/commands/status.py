from __future__ import annotations

import json
import socket
import sys
from datetime import datetime, timezone
from pathlib import Path

from ..paths import KEY_DIR, REGISTRY_FILE, version_file


def _read_json(path: Path) -> dict | None:
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError:
        return None


def run_status(args: list[str]) -> int:
    chain_filter = ""
    pretty = False

    i = 0
    while i < len(args):
        a = args[i]
        if a == "--chain-id":
            i += 1
            chain_filter = args[i]
        elif a == "--pretty":
            pretty = True
        elif a in ("-h", "--help"):
            print("Usage: hopper status [--chain-id UUID] [--pretty]", file=sys.stderr)
            return 0
        else:
            print(f"Unknown argument: {a}", file=sys.stderr)
            return 1
        i += 1

    chains_root = KEY_DIR / "chains"
    host_version = _read_json(version_file())
    chains: list[dict] = []
    known_ids: set[str] = set()

    registry = _read_json(REGISTRY_FILE) or {"chains": []}
    for entry in registry.get("chains", []):
        cid = entry.get("chain_id", "")
        if chain_filter and cid != chain_filter:
            continue
        known_ids.add(cid)
        runtime = _read_json(chains_root / cid / "runtime.json") or {}
        leases = _read_json(chains_root / cid / "leases.json") or {}
        chains.append(
            {
                "chain_id": cid,
                "overlay": entry.get("overlay"),
                "listen_port": entry.get("listen_port"),
                "role": entry.get("role"),
                "hop_addr": entry.get("hop_addr"),
                "started_at": entry.get("started_at"),
                "running": bool(runtime.get("running")),
                "last_activity": runtime.get("last_activity"),
                "sessions": runtime.get("sessions", []),
                "leases": leases,
            }
        )

    if chains_root.is_dir():
        for chain_dir in chains_root.iterdir():
            if not chain_dir.is_dir():
                continue
            cid = chain_dir.name
            if cid in known_ids:
                continue
            if chain_filter and cid != chain_filter:
                continue
            runtime = _read_json(chain_dir / "runtime.json")
            if not runtime:
                continue
            chains.append(
                {
                    "chain_id": cid,
                    "overlay": runtime.get("overlay"),
                    "listen_port": runtime.get("listen_port"),
                    "role": runtime.get("mode"),
                    "hop_addr": runtime.get("hop_addr"),
                    "running": bool(runtime.get("running")),
                    "last_activity": runtime.get("last_activity"),
                    "sessions": runtime.get("sessions", []),
                }
            )

    out = {
        "host": socket.gethostname(),
        "server_version": (host_version or {}).get("version"),
        "min_app_version": (host_version or {}).get("min_app_version"),
        "checked_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "chains": chains,
    }
    print(json.dumps(out, indent=2 if pretty else None))
    return 0
