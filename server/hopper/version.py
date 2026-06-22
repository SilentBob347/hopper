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


def github_repo_slug() -> str:
    repo = _github_repo_url(str(load_version().get("git_remote", "") or ""))
    if not repo or "github.com/" not in repo:
        return ""
    return repo.split("github.com/", 1)[-1].strip("/")


def _fetch_latest_release_tag(slug: str) -> str:
    import json
    import urllib.error
    import urllib.request

    url = f"https://api.github.com/repos/{slug}/releases/latest"
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "hopper-server-install",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())
        return str(data.get("tag_name", "")).strip()
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError, ValueError):
        return ""


def release_asset_urls(arch: str) -> list[str]:
    """Ordered hopperd download URLs to try (latest release, then pinned tags)."""
    asset = f"hopperd-linux-{arch}"
    urls: list[str] = []
    data = load_version()
    repo = _github_repo_url(str(data.get("git_remote", "") or ""))

    if repo:
        urls.append(f"{repo}/releases/latest/download/{asset}")
        slug = github_repo_slug()
        if slug:
            tag = _fetch_latest_release_tag(slug)
            if tag:
                urls.append(f"{repo}/releases/download/{tag}/{asset}")
        ver = str(data.get("version", "") or "").strip()
        if ver:
            tag = ver if ver.startswith("v") else f"v{ver}"
            urls.append(f"{repo}/releases/download/{tag}/{asset}")

    legacy = str(data.get("release_base_url", "") or "").strip().rstrip("/")
    if legacy and legacy not in urls:
        urls.append(f"{legacy}/{asset}")

    seen: set[str] = set()
    ordered: list[str] = []
    for url in urls:
        if url not in seen:
            seen.add(url)
            ordered.append(url)
    return ordered
