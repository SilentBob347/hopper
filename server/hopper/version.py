from __future__ import annotations

import json
import re
from functools import lru_cache
from typing import Any

from .paths import version_file


@lru_cache
def load_version() -> dict[str, Any]:
    vf = version_file()
    if not vf.is_file():
        return {}
    return json.loads(vf.read_text())


def version_field(name: str, default: str = "") -> str:
    return str(load_version().get(name, default) or default)


def _github_repo_url(remote: str) -> str:
    remote = remote.strip().rstrip("/")
    if not remote:
        return ""
    if remote.startswith("git@"):
        # git@github.com:owner/repo.git
        match = re.match(r"git@([^:]+):(.+?)(?:\.git)?$", remote)
        if match:
            return f"https://{match.group(1)}/{match.group(2)}"
        return ""
    remote = re.sub(r"\.git$", "", remote)
    if "github.com" in remote:
        return remote
    return ""


def release_download_base() -> str:
    """Base URL for hopperd release assets (always latest GitHub release)."""
    data = load_version()
    explicit = str(data.get("release_latest_url", "") or "").strip().rstrip("/")
    if explicit:
        return explicit

    repo = _github_repo_url(str(data.get("git_remote", "") or ""))
    if repo:
        return f"{repo}/releases/latest/download"

    legacy = str(data.get("release_base_url", "") or "").strip().rstrip("/")
    if "/releases/download/" in legacy:
        prefix = legacy.split("/releases/download/", 1)[0]
        return f"{prefix}/releases/latest/download"
    return legacy
