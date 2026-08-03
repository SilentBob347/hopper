from __future__ import annotations

import os
import re
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

_DAILY_LOG_RE = re.compile(r"^hopper-(\d{4}-\d{2}-\d{2})\.log$")
DEFAULT_LOG_KEEP_DAYS = 2


def log(msg: str) -> None:
    ts = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    print(f"[{ts}] {msg}", file=sys.stderr)


def die(msg: str, code: int = 1) -> None:
    log(f"ERROR: {msg}")
    raise SystemExit(code)


def log_keep_days() -> int:
    """Days of daily logs to retain. Override with HOPPER_LOG_KEEP_DAYS (default 2)."""
    raw = os.environ.get("HOPPER_LOG_KEEP_DAYS", "").strip()
    if not raw:
        return DEFAULT_LOG_KEEP_DAYS
    try:
        days = int(raw)
    except ValueError:
        return DEFAULT_LOG_KEEP_DAYS
    return days if days >= 1 else DEFAULT_LOG_KEEP_DAYS


def daily_hopper_log(chain_dir: Path, day: date | None = None) -> Path:
    """Path for the hopperd log file for a given calendar day (local time)."""
    d = day or date.today()
    return chain_dir / f"hopper-{d.isoformat()}.log"


def prune_hopper_logs(chain_dir: Path, keep_days: int | None = None) -> None:
    """Delete dated hopperd logs older than the retention window.

    Default keep_days=2 keeps today and yesterday; day-before-yesterday and
    older are removed. Also drops the legacy undated hopper.log if present.
    """
    if not chain_dir.is_dir():
        return
    if keep_days is None:
        keep_days = log_keep_days()
    if keep_days < 1:
        keep_days = DEFAULT_LOG_KEEP_DAYS
    oldest_keep = date.today() - timedelta(days=keep_days - 1)

    legacy = chain_dir / "hopper.log"
    if legacy.is_file():
        legacy.unlink(missing_ok=True)
        log(f"Removed legacy log {legacy}")

    for path in sorted(chain_dir.glob("hopper-*.log")):
        match = _DAILY_LOG_RE.match(path.name)
        if not match:
            continue
        try:
            log_day = date.fromisoformat(match.group(1))
        except ValueError:
            continue
        if log_day < oldest_keep:
            path.unlink(missing_ok=True)
            log(f"Removed old log {path.name}")
