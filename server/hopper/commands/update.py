from __future__ import annotations

import json
import sys

from ..bootstrap import ensure_venv_packages, ensure_git
from ..daemon import maybe_setcap, refresh_binary_from_release, resolve_binary, stop_all_legacy_cleanup
from ..git_sync import copy_tree_into_install, sync_from_git
from ..logutil import die, log
from ..paths import hopper_dir
from ..version import load_version, version_field


def run_update(args: list[str]) -> int:
    mode = "check"
    target_version = ""
    json_only = False

    i = 0
    while i < len(args):
        a = args[i]
        if a == "--check":
            mode = "check"
        elif a == "--update":
            mode = "update"
        elif a == "--to":
            i += 1
            target_version = args[i]
        elif a == "--json-only":
            json_only = True
        elif a in ("-h", "--help"):
            print("Usage: hopper update [--check] [--update] [--to VERSION] [--json-only]", file=sys.stderr)
            return 2
        else:
            die(f"Unknown argument: {a}")
        i += 1

    if mode == "check":
        print(json.dumps(load_version(), separators=(",", ":")))
        return 0

    ensure_git()
    from_ver = version_field("version", "unknown")
    if not target_version:
        target_version = version_field("version")

    src = sync_from_git(target_version=target_version)
    log(f"Syncing into {hopper_dir()}...")
    copy_tree_into_install(src)
    ensure_venv_packages()

    if not refresh_binary_from_release():
        resolve_binary()

    try:
        maybe_setcap()
    except SystemExit:
        pass

    result = {
        "updated": True,
        "from": from_ver,
        "to": target_version,
        "version": target_version,
    }
    print(json.dumps(result, separators=(",", ":")))
    return 0

