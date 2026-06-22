from __future__ import annotations

import sys
from datetime import datetime, timezone


def log(msg: str) -> None:
    ts = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    print(f"[{ts}] {msg}", file=sys.stderr)


def die(msg: str, code: int = 1) -> None:
    log(f"ERROR: {msg}")
    raise SystemExit(code)
