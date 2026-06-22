from __future__ import annotations

import shutil
import subprocess

from .logutil import log
from .paths import ChainContext


def setup_nat(ctx: ChainContext) -> None:
    subprocess.run(["sysctl", "-w", "net.ipv4.ip_forward=1"], capture_output=True)
    if not shutil.which("iptables"):
        log("WARN: iptables not found")
        return
    r = subprocess.run(["ip", "route", "show", "default"], capture_output=True, text=True)
    iface = ""
    if r.returncode == 0 and r.stdout.strip():
        parts = r.stdout.strip().split()
        if len(parts) >= 5:
            iface = parts[4]
    if not iface:
        return
    overlay = ctx.overlay_cidr
    tun = ctx.tun_name
    checks = [
        ["iptables", "-t", "nat", "-C", "POSTROUTING", "-s", overlay, "-o", iface, "-j", "MASQUERADE"],
        ["iptables", "-C", "FORWARD", "-i", tun, "-j", "ACCEPT"],
        ["iptables", "-C", "FORWARD", "-o", tun, "-j", "ACCEPT"],
        ["iptables", "-C", "FORWARD", "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"],
    ]
    adds = [
        ["iptables", "-t", "nat", "-A", "POSTROUTING", "-s", overlay, "-o", iface, "-j", "MASQUERADE"],
        ["iptables", "-A", "FORWARD", "-i", tun, "-j", "ACCEPT"],
        ["iptables", "-A", "FORWARD", "-o", tun, "-j", "ACCEPT"],
        ["iptables", "-A", "FORWARD", "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"],
    ]
    for check, add in zip(checks, adds):
        if subprocess.run(check, capture_output=True).returncode != 0:
            subprocess.run(add, capture_output=True)
