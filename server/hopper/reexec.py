from __future__ import annotations

import os
import sys

from .logutil import log
from .paths import hopper_dir

POST_SYNC_INSTALL = "HOPPER_INSTALL_POST_SYNC"
POST_SYNC_UPDATE = "HOPPER_UPDATE_POST_SYNC"


def argv_without_flag(args: list[str], flag: str, *, takes_value: bool = False) -> list[str]:
    out: list[str] = []
    i = 0
    while i < len(args):
        if args[i] == flag:
            i += 2 if takes_value else 1
            continue
        out.append(args[i])
        i += 1
    return out


def reexec_hopperctl(subcommand: str, args: list[str], *, env_flag: str) -> int:
    """Replace current process with a fresh hopperctl run (loads updated code from disk)."""
    hopperctl = hopper_dir() / "hopperctl"
    if not hopperctl.is_file():
        die_msg = f"hopperctl not found at {hopperctl}"
        log(f"ERROR: {die_msg}")
        raise SystemExit(1)

    env = os.environ.copy()
    env[env_flag] = "1"
    env.setdefault("HOPPER_DIR", str(hopper_dir()))
    argv = [str(hopperctl), subcommand, *args]
    log(f"reexec: {' '.join(argv)}")
    os.execve(str(hopperctl), argv, env)
    raise SystemExit(f"reexec failed: {hopperctl}")
