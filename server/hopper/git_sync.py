from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from .bootstrap import ensure_git
from .logutil import die, log
from .paths import hopper_dir
from .version import load_version, version_field


def repo_root() -> Path:
    return hopper_dir() / ".repo"


def sync_from_git(ref: str | None = None, target_version: str | None = None) -> Path:
    ensure_git()
    ver = load_version()
    remote = ver.get("git_remote", "https://github.com/ZonD80/hopper.git")
    subdir = ver.get("git_subdir", "server")
    checkout_ref = ref or f"v{target_version or version_field('version')}"
    root = repo_root()

    if (root / ".git").is_dir():
        log(f"Updating git checkout in {root}...")
        subprocess.run(["git", "-C", str(root), "fetch", "--tags", "--depth", "1", "origin"], check=False)
        subprocess.run(["git", "-C", str(root), "fetch", "--tags", "origin"], check=False)
        subprocess.run(["git", "-C", str(root), "checkout", checkout_ref], check=False)
        subprocess.run(["git", "-C", str(root), "checkout", f"tags/{checkout_ref}"], check=False)
        subprocess.run(["git", "-C", str(root), "sparse-checkout", "set", subdir], check=False)
    else:
        log(f"Cloning {remote} (ref {checkout_ref})...")
        if root.exists():
            shutil.rmtree(root)
        r = subprocess.run(
            ["git", "clone", "--depth", "1", "--branch", checkout_ref, remote, str(root)],
            capture_output=True,
        )
        if r.returncode != 0:
            subprocess.run(["git", "clone", "--depth", "1", remote, str(root)], check=True)
            subprocess.run(["git", "-C", str(root), "checkout", checkout_ref], check=False)
            subprocess.run(["git", "-C", str(root), "checkout", f"tags/{checkout_ref}"], check=False)
        subprocess.run(["git", "-C", str(root), "sparse-checkout", "init", "--cone"], check=False)
        subprocess.run(["git", "-C", str(root), "sparse-checkout", "set", subdir], check=False)

    src = root / subdir
    if not src.is_dir():
        src = root / "server"
    if not src.is_dir():
        die("server directory not found in checkout")
    return src


def copy_tree_into_install(src: Path) -> None:
    """Sync server tree from git checkout into HOPPER_DIR."""
    skip = {".repo", ".venv", "dist", "__pycache__", ".git"}
    for item in src.iterdir():
        if item.name in skip:
            continue
        dest = hopper_dir() / item.name
        if item.is_dir():
            if dest.is_dir():
                shutil.copytree(item, dest, dirs_exist_ok=True)
            else:
                shutil.copytree(item, dest)
        else:
            shutil.copy2(item, dest)
    for script in hopper_dir().glob("*.sh"):
        script.chmod(0o755)
    hopperctl = hopper_dir() / "hopperctl"
    if hopperctl.is_file():
        hopperctl.chmod(0o755)
