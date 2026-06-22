from __future__ import annotations

import json
import getpass
import os
import socket
import sys

from ..daemon import maybe_setcap, resolve_binary
from ..keys import ensure_keypair, fetch_public_ip, install_authorized_key, read_host_key
from ..logutil import die, log
from ..node_profile import build_node_profile
from ..paths import hopper_dir, KEY_PATH
from ..version import load_version, version_field


def run_configure(args: list[str]) -> int:
    json_only = False
    version_json = False
    host = ""
    port = 22

    i = 0
    while i < len(args):
        a = args[i]
        if a == "--json-only":
            json_only = True
        elif a == "--version-json":
            version_json = True
        elif a == "--host":
            i += 1
            host = args[i]
        elif a == "--port":
            i += 1
            port = int(args[i])
        elif a in ("-h", "--help"):
            print("Usage: hopper configure [--json-only] [--version-json] [--host H] [--port P]", file=sys.stderr)
            return 0
        else:
            die(f"Unknown argument: {a}")
        i += 1

    if version_json:
        print(json.dumps(load_version(), separators=(",", ":")))
        return 0

    user = os.environ.get("USER") or getpass.getuser()
    if not host:
        host = fetch_public_ip()
    if not json_only and sys.stdin.isatty():
        inp = input(f"SSH host for clients [{host}]: ").strip()
        if inp:
            host = inp
        inp = input(f"SSH port [{port}]: ").strip()
        if inp:
            port = int(inp)

    ensure_keypair()
    install_authorized_key()
    try:
        resolve_binary()
        maybe_setcap()
    except SystemExit:
        pass

    name = socket.getfqdn() or socket.gethostname()
    host_key = read_host_key(host, port)
    payload = build_node_profile(
        name=name,
        host=host,
        port=port,
        user=user,
        private_key=KEY_PATH.read_text(),
        install_dir=str(hopper_dir()),
        server_version=version_field("version", "unknown"),
        min_app_version=version_field("min_app_version", "unknown"),
        host_key=host_key,
    )

    text = json.dumps(payload, separators=(",", ":"))
    if json_only:
        print(text)
    else:
        log("")
        log("Hopper node profile (JSON) — import via deploy QR or paste into the app.")
        print(text)
        log(f"Install path: {hopper_dir()}")
    return 0
