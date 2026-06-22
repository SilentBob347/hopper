from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from ..chain import init_chain_context
from ..daemon import (
    chain_is_running,
    emit_ready_json,
    start_hopperd_detached,
    stop_chain_daemon,
    write_hopper_config,
)
from ..keys import trust_pubkey
from ..logutil import die
from ..nat import setup_nat
from ..registry import registry_add


def run_start(args: list[str]) -> int:
    chain_id = ""
    role = ""
    addr = ""
    index: int | None = None
    next_host = ""
    next_port = 22
    next_user = ""
    next_tunnel_port = 0
    trust_pubkey_str = ""
    trust_only = False
    stop_only = False
    if_running = ""

    i = 0
    while i < len(args):
        a = args[i]
        if a == "--chain-id":
            i += 1
            chain_id = args[i]
        elif a == "--role":
            i += 1
            role = args[i]
        elif a == "--addr":
            i += 1
            addr = args[i]
        elif a == "--index":
            i += 1
            index = int(args[i])
        elif a == "--next-host":
            i += 1
            next_host = args[i]
        elif a == "--next-port":
            i += 1
            next_port = int(args[i])
        elif a == "--next-user":
            i += 1
            next_user = args[i]
        elif a == "--next-tunnel-port":
            i += 1
            next_tunnel_port = int(args[i])
        elif a == "--trust-pubkey":
            i += 1
            trust_pubkey_str = args[i]
        elif a == "--trust-only":
            trust_only = True
        elif a == "--stop-only":
            stop_only = True
        elif a == "--if-running":
            i += 1
            if_running = args[i]
        elif a == "--hopper-dir":
            i += 1
            os.environ["HOPPER_DIR"] = str(Path(args[i]).expanduser().resolve())
        elif a == "--overlay":
            i += 1  # ignored; overlay is derived from chain-id
        elif a in ("-h", "--help"):
            print(
                "Usage: hopper start --chain-id UUID --role exit|relay --addr A.B.C.D --index N "
                "[--next-host H --next-port P --next-user U --next-tunnel-port P] "
                "[--trust-pubkey 'ssh-ed25519 AAAA...'] [--trust-only] [--stop-only] [--if-running skip]",
                file=sys.stderr,
            )
            return 2
        else:
            die(f"Unknown argument: {a}")
        i += 1

    ctx = init_chain_context(chain_id)

    if stop_only:
        stop_chain_daemon(ctx)
        print(json.dumps({"stopped": True, "chain_id": chain_id}, separators=(",", ":")))
        return 0

    if trust_pubkey_str:
        trust_pubkey(trust_pubkey_str)
        if trust_only:
            print(json.dumps({"trusted": True}, separators=(",", ":")))
            return 0

    if not role or not addr or index is None:
        print("Missing --role, --addr, or --index", file=sys.stderr)
        return 2

    if if_running == "skip" and chain_is_running(ctx):
        port = 0
        for line in ctx.hopper_ready.read_text().splitlines():
            if line.startswith("READY "):
                port = int(line.split()[1])
                break
        print(emit_ready_json(ctx, role, addr, index, port))
        return 0

    stop_chain_daemon(ctx)

    if role == "exit":
        pass
    elif role == "relay":
        if not next_host or not next_user:
            die("relay node requires --next-host and --next-user")
    else:
        die("role must be exit or relay")

    write_hopper_config(
        ctx, role, addr,
        next_host=next_host,
        next_port=next_port,
        next_user=next_user,
        next_tunnel_port=next_tunnel_port,
    )

    if role == "exit":
        try:
            setup_nat(ctx)
        except Exception:
            pass

    port = start_hopperd_detached(ctx)
    registry_add(ctx.chain_id, ctx.overlay_cidr, ctx.listen_port, role, addr, index)
    print(emit_ready_json(ctx, role, addr, index, port))
    return 0
