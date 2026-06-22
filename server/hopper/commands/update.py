from __future__ import annotations

import json
import os
import sys

from ..bootstrap import ensure_venv_packages, ensure_git
from ..git_sync import copy_tree_into_install, sync_from_git
from ..logutil import die, log
from ..paths import hopper_dir
from ..reexec import POST_SYNC_UPDATE, reexec_hopperctl
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

    post_sync = os.environ.get(POST_SYNC_UPDATE) == "1"
    ensure_git()
    from_ver = version_field("version", "unknown")
    if not target_version:
        target_version = version_field("version")

    if not post_sync:
        src = sync_from_git(target_version=target_version)
        log(f"Syncing into {hopper_dir()}...")
        copy_tree_into_install(src)
        ensure_venv_packages(force_reinstall=True)
        log("update: server tree updated — reloading hopperctl")
        reexec_hopperctl("update", args, env_flag=POST_SYNC_UPDATE)

    ensure_venv_packages(force_reinstall=post_sync)

    from ..daemon import maybe_setcap, refresh_binary_from_release, resolve_binary

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
