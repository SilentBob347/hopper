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


def _venv_works(python: str) -> bool:
    import tempfile

    td = Path(tempfile.mkdtemp())
    try:
        venv.create(td, with_pip=True)
        return True
    except Exception:
        return False
    finally:
        shutil.rmtree(td, ignore_errors=True)


def _python_minor_version() -> str:
    python = shutil.which("python3")
    if not python:
        return ""
    r = subprocess.run(
        [python, "-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"],
        capture_output=True,
        text=True,
    )
    return r.stdout.strip() if r.returncode == 0 else ""


def ensure_python() -> None:
    python = shutil.which("python3")
    if python and _venv_works(python):
        return
    if python:
        log("python3-venv missing — installing...")
    else:
        log("python3 not found — installing...")
    pkgs = ["python3", "python3-venv", "python3-pip"]
    ver = _python_minor_version()
    if ver:
        pkgs.append(f"python{ver}-venv")
    _install_packages(pkgs)
    python = shutil.which("python3")
    if not python or not _venv_works(python):
        die("python3 venv still unavailable after package install")


def _venv_python_ready(vdir: Path) -> bool:
    vpy = vdir / "bin" / "python"
    if not vpy.is_file():
        return False
    pip_ok = subprocess.run([str(vpy), "-m", "pip", "--version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if pip_ok.returncode != 0:
        return False
    hopper_ok = subprocess.run(
        [str(vpy), "-c", "import hopper.cli"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return hopper_ok.returncode == 0


def ensure_venv_packages() -> Path:
    """Create venv and pip install hopper package + requirements."""
    ensure_python()
    python = shutil.which("python3")
    if not python:
        die("python3 required")
    vdir = venv_dir()
    if not _venv_python_ready(vdir):
        if vdir.is_dir():
            log(f"Removing incomplete venv at {vdir}")
            shutil.rmtree(vdir)
        log(f"Creating venv at {vdir}")
        venv.create(vdir, with_pip=True)
    vpy = vdir / "bin" / "python"
    req = hopper_dir() / "requirements.txt"
    subprocess.run([str(vpy), "-m", "pip", "install", "--upgrade", "pip", "-q"], check=True)
    subprocess.run([str(vpy), "-m", "pip", "install", "-e", str(hopper_dir()), "-q"], check=True)
    if req.is_file():
        subprocess.run([str(vpy), "-m", "pip", "install", "-r", str(req), "-q"], check=True)
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
