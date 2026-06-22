from __future__ import annotations

import shutil
import socket
import subprocess
from pathlib import Path

from .logutil import die
from .paths import KEY_DIR, KEY_PATH


def ensure_keypair() -> None:
    KEY_DIR.mkdir(parents=True, exist_ok=True)
    ssh_dir = Path.home() / ".ssh"
    ssh_dir.mkdir(mode=0o700, exist_ok=True)
    if KEY_PATH.is_file():
        return
    if not shutil_which("ssh-keygen"):
        die("ssh-keygen required")
    host = socket.getfqdn() or socket.gethostname()
    subprocess.run(
        ["ssh-keygen", "-t", "ed25519", "-f", str(KEY_PATH), "-N", "", "-C", f"hopper@{host}"],
        check=True,
    )
    KEY_PATH.chmod(0o600)
    KEY_PATH.with_suffix(".pub").chmod(0o644)


def install_authorized_key() -> None:
    pub_path = KEY_PATH.with_suffix(".pub")
    pub = pub_path.read_text().strip()
    auth = Path.home() / ".ssh" / "authorized_keys"
    auth.parent.mkdir(mode=0o700, exist_ok=True)
    auth.touch(mode=0o600)
    lines = auth.read_text().splitlines() if auth.is_file() else []
    if any(pub in line for line in lines):
        return
    hostname = socket.gethostname()
    with auth.open("a") as f:
        f.write(f"{pub} hopper-{hostname}\n")


def trust_pubkey(pubkey: str) -> None:
    if not pubkey:
        return
    ssh_dir = Path.home() / ".ssh"
    ssh_dir.mkdir(mode=0o700, exist_ok=True)
    auth = ssh_dir / "authorized_keys"
    auth.touch(mode=0o600)
    if pubkey in auth.read_text():
        return
    with auth.open("a") as f:
        f.write(f"{pubkey} hopper-peer\n")


def read_host_key(host: str, port: int) -> str:
    if not shutil_which("ssh-keyscan"):
        return ""
    try:
        out = subprocess.check_output(
            ["ssh-keyscan", "-p", str(port), "-t", "ed25519,rsa", host],
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except subprocess.CalledProcessError:
        return ""
    for line in out.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 3 and parts[1] in ("ssh-ed25519", "ssh-rsa"):
            return f"{parts[1]} {parts[2]}"
    return ""


def fetch_public_ip() -> str:
    if shutil_which("curl"):
        try:
            ip = subprocess.check_output(
                ["curl", "-fsSL", "--max-time", "10", "https://whatismyip.akamai.com/"],
                stderr=subprocess.DEVNULL,
                text=True,
            ).strip()
            if ip:
                return ip
        except subprocess.CalledProcessError:
            pass
    try:
        out = subprocess.check_output(["hostname", "-I"], text=True).strip().split()
        if out:
            return out[0]
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return "127.0.0.1"


def shutil_which(cmd: str) -> str | None:
    return shutil.which(cmd)
