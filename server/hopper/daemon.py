from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import time
from pathlib import Path

from .logutil import die, log
from .paths import bin_dir, DAEMON_NAME, KEY_DIR, ChainContext, ensure_dirs
from .version import version_field


def detect_arch() -> str:
    machine = os.uname().machine
    if machine in ("x86_64", "amd64"):
        return "amd64"
    if machine in ("aarch64", "arm64"):
        return "arm64"
    die(f"Unsupported architecture: {machine}")
    return ""


def hopper_binary_path() -> Path:
    return bin_dir() / f"{DAEMON_NAME}-linux-{detect_arch()}"


def resolve_binary() -> Path:
    ensure_dirs()
    dest = hopper_binary_path()
    if dest.is_file():
        log(f"Using bundled {DAEMON_NAME} at {dest}")
    elif shutil.which("go") and (Path(__file__).resolve().parent.parent / "cmd" / "hopperd" / "main.go").is_file():
        log(f"Building {DAEMON_NAME} into {dest}...")
        ver = version_field("version", "dev")
        server_root = Path(__file__).resolve().parent.parent
        subprocess.run(
            [
                "go", "build",
                "-ldflags", f"-s -w -X main.version={ver}",
                "-o", str(dest),
                "./cmd/hopperd",
            ],
            cwd=server_root,
            env={**os.environ, "GOOS": "linux", "GOARCH": detect_arch(), "CGO_ENABLED": "0"},
            check=True,
        )
    else:
        die(f"Missing {dest}. Run hopper update or install from deploy.")
    dest.chmod(0o755)
    check = subprocess.run([str(dest), "-check"], capture_output=True)
    if check.returncode != 0:
        die(f"{dest} failed -check")
    return dest


def refresh_binary_from_release() -> bool:
    from .version import load_version

    base = load_version().get("release_base_url", "")
    if not base:
        return False
    dest = hopper_binary_path()
    url = f"{base}/hopperd-linux-{detect_arch()}"
    log(f"Downloading {url}...")
    tmp = dest.with_name(dest.name + ".download")
    try:
        if shutil.which("curl"):
            subprocess.run(["curl", "-fsSL", "-o", str(tmp), url], check=True)
        elif shutil.which("wget"):
            subprocess.run(["wget", "-q", "-O", str(tmp), url], check=True)
        else:
            return False
    except subprocess.CalledProcessError:
        tmp.unlink(missing_ok=True)
        return False
    if not tmp.is_file() or tmp.stat().st_size == 0:
        tmp.unlink(missing_ok=True)
        return False
    tmp.replace(dest)
    dest.chmod(0o755)
    return True


def port_listening(port: int) -> bool:
    if shutil.which("ss"):
        r = subprocess.run(["ss", "-ltn"], capture_output=True, text=True)
        return f":{port} " in r.stdout or f".{port} " in r.stdout
    if shutil.which("netstat"):
        r = subprocess.run(["netstat", "-ltn"], capture_output=True, text=True)
        return f":{port} " in r.stdout
    return False


def hopper_pids_for_config(cfg: Path) -> list[int]:
    if not shutil.which("pgrep"):
        return []
    r = subprocess.run(["pgrep", "-f", str(cfg)], capture_output=True, text=True)
    if r.returncode != 0:
        return []
    return [int(x) for x in r.stdout.split() if x.strip().isdigit()]


def kill_hopper_port(port: int) -> None:
    if shutil.which("fuser"):
        subprocess.run(["fuser", "-k", "-TERM", f"{port}/tcp"], capture_output=True)
        time.sleep(0.2)
        subprocess.run(["fuser", "-k", "-KILL", f"{port}/tcp"], capture_output=True)
        return
    if shutil.which("ss"):
        r = subprocess.run(["ss", "-ltnp"], capture_output=True, text=True)
        for line in r.stdout.splitlines():
            if f":{port} " not in line:
                continue
            if "pid=" in line:
                pid = line.split("pid=")[1].split(",")[0]
                subprocess.run(["kill", "-TERM", pid], capture_output=True)
                time.sleep(0.2)
                subprocess.run(["kill", "-KILL", pid], capture_output=True)
                return


def stop_chain_daemon(ctx: ChainContext) -> None:
    try:
        resolve_binary()
    except SystemExit:
        pass
    for pid in hopper_pids_for_config(ctx.hopper_config):
        subprocess.run(["kill", "-TERM", str(pid)], capture_output=True)
    kill_hopper_port(ctx.listen_port)
    for _ in range(30):
        if not hopper_pids_for_config(ctx.hopper_config):
            break
        time.sleep(0.1)
    for pid in hopper_pids_for_config(ctx.hopper_config):
        subprocess.run(["kill", "-KILL", str(pid)], capture_output=True)
    kill_hopper_port(ctx.listen_port)
    ctx.hopper_ready.unlink(missing_ok=True)
    from .registry import registry_remove

    registry_remove(ctx.chain_id)
    log(f"Stopped hopperd for chain {ctx.chain_id}")


def chain_is_running(ctx: ChainContext) -> bool:
    if not ctx.hopper_ready.is_file() or ctx.hopper_ready.stat().st_size == 0:
        return False
    for line in ctx.hopper_ready.read_text().splitlines():
        if line.startswith("READY "):
            port = int(line.split()[1])
            return port_listening(port)
    return False


def write_hopper_config(
    ctx: ChainContext,
    role: str,
    addr: str,
    next_host: str = "",
    next_port: int = 22,
    next_user: str = "",
    next_tunnel_port: int = 0,
) -> None:
    octet = ctx.overlay_cidr.split(".")[2]
    cfg: dict = {
        "chain_id": ctx.chain_id,
        "addr": addr,
        "overlay": ctx.overlay_cidr,
        "client_pool": f"10.64.{octet}.2/24",
        "client_lease_ttl_sec": 3600,
        "tun": ctx.tun_name,
        "listen_host": "127.0.0.1",
        "listen_port": ctx.listen_port,
    }
    if role == "exit":
        cfg["nat"] = True
    elif next_host:
        cfg["next"] = {
            "host": next_host,
            "port": next_port,
            "user": next_user,
            "key_path": str(Path.home() / ".hopper" / "id_ed25519"),
            "tunnel_port": next_tunnel_port or ctx.listen_port,
        }
    ctx.hopper_config.write_text(json.dumps(cfg, indent=2) + "\n")


def start_hopperd_detached(ctx: ChainContext) -> int:
    binary = resolve_binary()
    time.sleep(0.2)
    log(f"Starting hopperd chain={ctx.chain_id} ({ctx.hopper_config})")
    log_path = open(ctx.hopper_log, "a")
    cmd = [
        str(binary), "-verbose",
        "--config", str(ctx.hopper_config),
        "--ready-file", str(ctx.hopper_ready),
    ]
    if shutil.which("setsid"):
        subprocess.Popen(
            ["setsid", "-f", *cmd],
            stdout=log_path,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
    else:
        subprocess.Popen(
            cmd,
            stdout=log_path,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
    for _ in range(40):
        if ctx.hopper_ready.is_file() and hopper_pids_for_config(ctx.hopper_config):
            for line in ctx.hopper_ready.read_text().splitlines():
                if line.startswith("READY "):
                    port = int(line.split()[1])
                    if port_listening(port):
                        return port
        time.sleep(0.25)
    die(f"hopperd failed — see {ctx.hopper_log}")
    return 0


def emit_ready_json(ctx: ChainContext, role: str, addr: str, index: int, port: int) -> str:
    return json.dumps(
        {
            "ready": True,
            "mode": role,
            "addr": addr,
            "index": index,
            "overlay": ctx.overlay_cidr,
            "port": port,
            "listen_port": ctx.listen_port,
            "chain_id": ctx.chain_id,
            "nat": role == "exit",
        },
        separators=(",", ":"),
    )


def stop_all_legacy_cleanup() -> None:
    log("Legacy cleanup: stopping all hopperd instances...")
    subprocess.run(["pkill", "-TERM", "-f", f"{DAEMON_NAME}-linux-"], capture_output=True)
    for port in range(7400, 7655):
        kill_hopper_port(port)
    time.sleep(0.5)
    subprocess.run(["pkill", "-KILL", "-f", f"{DAEMON_NAME}-linux-"], capture_output=True)
    if shutil.which("ip"):
        r = subprocess.run(["ip", "-o", "link", "show"], capture_output=True, text=True)
        for line in r.stdout.splitlines():
            if ": hopper" in line:
                tun = line.split(": ", 2)[1].split("@")[0].strip()
                subprocess.run(["ip", "link", "set", tun, "down"], capture_output=True)
                subprocess.run(["ip", "link", "delete", tun], capture_output=True)
    for legacy in (KEY_DIR / "hopper.json", KEY_DIR / "hopper-ready", KEY_DIR / "hopper.log"):
        legacy.unlink(missing_ok=True)


def maybe_setcap() -> None:
    if os.geteuid() != 0 or not shutil.which("setcap"):
        return
    try:
        binary = resolve_binary()
        subprocess.run(["setcap", "cap_net_admin+ep", str(binary)], capture_output=True)
    except SystemExit:
        pass
