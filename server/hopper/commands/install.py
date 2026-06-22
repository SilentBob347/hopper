from __future__ import annotations

import json
import os

from ..bootstrap import ensure_venv_packages, ensure_git
from ..git_sync import copy_tree_into_install, sync_from_git
from ..logutil import die, log
from ..paths import hopper_dir
from ..reexec import POST_SYNC_INSTALL, argv_without_flag, reexec_hopperctl


def run_install(args: list[str]) -> int:
    """Idempotent local install: venv, package, binaries, legacy cleanup."""
    ref = ""
    configure = False
    host = ""
    port = 22
    skip_binary = False

    i = 0
    while i < len(args):
        a = args[i]
        if a == "--ref":
            i += 1
            ref = args[i]
        elif a == "--configure":
            configure = True
        elif a == "--host":
            i += 1
            host = args[i]
        elif a == "--port":
            i += 1
            port = int(args[i])
        elif a == "--skip-binary":
            skip_binary = True
        elif a in ("-h", "--help"):
            print(
                "Usage: hopper install [--ref TAG] [--configure] [--host H] [--port P] [--skip-binary]",
                file=sys.stderr,
            )
            return 0
        else:
            die(f"Unknown argument: {a}")
        i += 1

    post_sync = os.environ.get(POST_SYNC_INSTALL) == "1"

    ensure_git()
    hopper_dir().mkdir(parents=True, exist_ok=True)
    log(
        f"install start: dir={hopper_dir()} ref={ref or '(none)'} "
        f"skip_binary={skip_binary} configure={configure} post_sync={post_sync}"
    )

    if ref and not post_sync:
        log(f"git sync: ref={ref}")
        src = sync_from_git(ref=ref)
        log(f"git sync: copying from {src}")
        copy_tree_into_install(src)
        ensure_venv_packages(force_reinstall=True)
        log("git sync: server tree updated — reloading hopperctl")
        reexec_hopperctl(
            "install",
            argv_without_flag(args, "--ref", takes_value=True),
            env_flag=POST_SYNC_INSTALL,
        )

    ensure_venv_packages(force_reinstall=post_sync)

    from ..daemon import maybe_setcap, refresh_binary_from_release, resolve_binary, stop_all_legacy_cleanup

    stop_all_legacy_cleanup()

    if not skip_binary:
        log("install: refreshing hopperd binary from GitHub release")
        if not refresh_binary_from_release():
            log("install: release download failed — checking dist/ or local build")
            try:
                resolve_binary()
            except SystemExit:
                log(
                    "WARN: hopperd binary not available — check deploy log above for download errors "
                    "(GitHub release hopperd-linux-amd64 / hopperd-linux-arm64)"
                )
    else:
        log("install: --skip-binary — using dist/ hopperd only")
        try:
            resolve_binary()
        except SystemExit:
            log("WARN: --skip-binary set but no valid hopperd in dist/")

    try:
        maybe_setcap()
    except SystemExit:
        pass

    if configure:
        from .configure import run_configure

        cfg_args = ["--json-only"]
        if host:
            cfg_args.extend(["--host", host])
        if port != 22:
            cfg_args.extend(["--port", str(port)])
        return run_configure(cfg_args)

    print(json.dumps({"installed": True, "dir": str(hopper_dir())}, separators=(",", ":")))
    return 0
