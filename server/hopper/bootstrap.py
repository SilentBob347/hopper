from __future__ import annotations

import os
import shutil
import subprocess
import sys
import venv
from pathlib import Path

from .logutil import die, log
from .paths import hopper_dir, venv_dir


def detect_pkg_manager() -> str:
    if shutil.which("apt-get"):
        return "apt"
    if shutil.which("dnf"):
        return "dnf"
    if shutil.which("yum"):
        return "yum"
    if shutil.which("apk"):
        return "apk"
    return "unknown"


def _install_packages(packages: list[str]) -> None:
    if os.geteuid() != 0:
        die(f"Install as root: {' '.join(packages)}")
    pm = detect_pkg_manager()
    if pm == "apt":
        subprocess.run(["apt-get", "update", "-qq"], check=True)
        env = os.environ.copy()
        env["DEBIAN_FRONTEND"] = "noninteractive"
        subprocess.run(["apt-get", "install", "-y", *packages], check=True, env=env)
    elif pm == "dnf":
        subprocess.run(["dnf", "install", "-y", *packages], check=True)
    elif pm == "yum":
        subprocess.run(["yum", "install", "-y", *packages], check=True)
    elif pm == "apk":
        subprocess.run(["apk", "add", "--no-cache", *packages], check=True)
    else:
        die(f"Cannot install packages automatically. Install: {' '.join(packages)}")


def ensure_python() -> None:
    if shutil.which("python3"):
        return
    log("python3 not found — installing...")
    _install_packages(["python3", "python3-venv", "python3-pip"])


def ensure_venv_packages() -> Path:
    """Create venv and pip install hopper package + requirements."""
    ensure_python()
    python = shutil.which("python3")
    if not python:
        die("python3 required")
    vdir = venv_dir()
    if not vdir.is_dir() or not (vdir / "bin" / "python").is_file():
        log(f"Creating venv at {vdir}")
        venv.create(vdir, with_pip=True)
    vpy = vdir / "bin" / "python"
    req = hopper_dir() / "requirements.txt"
    subprocess.run([str(vpy), "-m", "pip", "install", "--upgrade", "pip"], check=True)
    subprocess.run([str(vpy), "-m", "pip", "install", "-e", str(hopper_dir())], check=True)
    if req.is_file():
        subprocess.run([str(vpy), "-m", "pip", "install", "-r", str(req)], check=True)
    return vpy


def ensure_git() -> None:
    if shutil.which("git"):
        return
    log("git not found — installing...")
    _install_packages(["git"])


def venv_python() -> Path:
    vpy = venv_dir() / "bin" / "python"
    if vpy.is_file():
        return vpy
    return Path(shutil.which("python3") or sys.executable)
