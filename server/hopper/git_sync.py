from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

from .bootstrap import ensure_git
from .logutil import die, log
from .paths import hopper_dir
from .version import load_version, version_field

_VERSION_LIKE_REF = re.compile(r"^(v)?\d+\.\d+")


def repo_root() -> Path:
    return hopper_dir() / ".repo"


def _is_version_like_ref(ref: str) -> bool:
    return ref.startswith("v") or bool(_VERSION_LIKE_REF.match(ref))


def checkout_git_ref(root: Path, ref: str) -> None:
    """Checkout a branch, tag, or commit; only use tags/ for version-like refs."""

    def try_checkout(target: str) -> bool:
        r = subprocess.run(
            ["git", "-C", str(root), "checkout", target],
            capture_output=True,
        )
        return r.returncode == 0

    if try_checkout(ref):
        return

    if _is_version_like_ref(ref) and try_checkout(f"tags/{ref}"):
        return

    subprocess.run(
        ["git", "-C", str(root), "fetch", "origin", ref, "--depth", "1"],
        capture_output=True,
    )
    if try_checkout(ref):
        return

    if _is_version_like_ref(ref):
        subprocess.run(
            ["git", "-C", str(root), "fetch", "origin", f"refs/tags/{ref}", "--depth", "1"],
            capture_output=True,
        )
        if try_checkout(ref) or try_checkout(f"tags/{ref}"):
            return

    die(f"Cannot checkout git ref: {ref}")


def sync_from_git(ref: str | None = None, target_version: str | None = None) -> Path:
    ensure_git()
    ver = load_version()
    remote = ver.get("git_remote", "https://github.com/ZonD80/hopper.git")
    subdir = ver.get("git_subdir", "server")
    checkout_ref = ref or f"v{target_version or version_field('version')}"
    root = repo_root()

    if (root / ".git").is_dir():
        log(f"Updating git checkout in {root}...")
        subprocess.run(["git", "-C", str(root), "fetch", "--depth", "1", "origin"], check=False)
        subprocess.run(
            ["git", "-C", str(root), "fetch", "origin", checkout_ref, "--depth", "1"],
            capture_output=True,
        )
        checkout_git_ref(root, checkout_ref)
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
            checkout_git_ref(root, checkout_ref)
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
