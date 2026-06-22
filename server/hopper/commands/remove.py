from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from ..daemon import stop_all_legacy_cleanup
from ..logutil import log
from ..paths import hopper_dir, KEY_DIR, KEY_PATH


def _teardown_all_tuns() -> None:
    if not shutil.which("ip"):
        return
    r = subprocess.run(["ip", "-o", "link", "show"], capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if ": hopper" not in line:
            continue
        tun = line.split(": ", 2)[1].split("@")[0].strip()
        subprocess.run(["ip", "link", "set", tun, "down"], capture_output=True)
        subprocess.run(["ip", "route", "del", "10.64.0.0/16", "dev", tun], capture_output=True)
        subprocess.run(["ip", "addr", "flush", "dev", tun], capture_output=True)
        subprocess.run(["ip", "link", "delete", tun], capture_output=True)


def _teardown_nat() -> None:
    if not shutil.which("iptables") or not shutil.which("ip"):
        return
    r = subprocess.run(["ip", "route", "show", "default"], capture_output=True, text=True)
    iface = ""
    if r.returncode == 0 and r.stdout.strip():
        parts = r.stdout.strip().split()
        if len(parts) >= 5:
            iface = parts[4]
    if not iface:
        return
    for octet in range(256):
        subprocess.run(
            ["iptables", "-t", "nat", "-D", "POSTROUTING", "-s", f"10.64.{octet}.0/24", "-o", iface, "-j", "MASQUERADE"],
            capture_output=True,
        )
    r = subprocess.run(["ip", "-o", "link", "show"], capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if ": hopper" not in line:
            continue
        tun = line.split(": ", 2)[1].split("@")[0].strip()
        subprocess.run(["iptables", "-D", "FORWARD", "-i", tun, "-j", "ACCEPT"], capture_output=True)
        subprocess.run(["iptables", "-D", "FORWARD", "-o", tun, "-j", "ACCEPT"], capture_output=True)
    subprocess.run(
        ["iptables", "-D", "FORWARD", "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"],
        capture_output=True,
    )


def _clean_authorized_keys() -> None:
    auth = Path.home() / ".ssh" / "authorized_keys"
    if not auth.is_file():
        return
    pub_file = KEY_PATH.with_suffix(".pub")
    needle = ""
    if pub_file.is_file():
        parts = pub_file.read_text().split()
        if len(parts) >= 2:
            needle = f"{parts[0]} {parts[1]}"
    kept: list[str] = []
    for line in auth.read_text().splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            kept.append(line)
            continue
        if needle and needle in line:
            continue
        parts = s.split()
        if parts and (parts[-1].startswith("hopper-") or parts[-1] == "hopper-peer"):
            continue
        kept.append(line)
    auth.write_text("\n".join(kept) + ("\n" if kept else ""))
    log("Cleaned hopper entries from authorized_keys")


def run_remove(args: list[str]) -> int:
    yes = False
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("-y", "--yes"):
            yes = True
        elif a in ("-h", "--help"):
            print("Usage: hopper remove [-y|--yes]", file=sys.stderr)
            return 0
        else:
            print(f"Unknown argument: {a}", file=sys.stderr)
            return 1
        i += 1

    if not yes and sys.stdin.isatty():
        confirm = input(f"Remove hopper from {hopper_dir()} and {KEY_DIR}? [y/N] ").strip()
        if confirm.lower() != "y":
            log("Cancelled.")
            return 0

    stop_all_legacy_cleanup()
    _teardown_all_tuns()
    _teardown_nat()
    _clean_authorized_keys()
    if KEY_DIR.is_dir():
        shutil.rmtree(KEY_DIR)
    install = hopper_dir()
    if install.is_dir():
        shutil.rmtree(install)
    log(f"Removed {install} and {KEY_DIR}")
    return 0
