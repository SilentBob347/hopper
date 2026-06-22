"""Hopper node profile v2 — shared between server configure and mobile apps."""

from __future__ import annotations

from typing import Any

PROFILE_VERSION = 2

# Wire-format keys (snake_case JSON). Keep in sync with app HopProfileCodec.
KEY_VERSION = "v"
KEY_NAME = "name"
KEY_HOST = "host"
KEY_PORT = "port"
KEY_USER = "user"
KEY_PRIVATE_KEY = "private_key"
KEY_INSTALL_DIR = "install_dir"
KEY_SERVER_VERSION = "server_version"
KEY_MIN_APP_VERSION = "min_app_version"
KEY_HOST_KEY = "host_key"

DEFAULT_INSTALL_DIR = "~/hopper"
UNKNOWN_VERSION = "unknown"


def build_node_profile(
    *,
    name: str,
    host: str,
    port: int | str,
    user: str,
    private_key: str,
    install_dir: str,
    server_version: str,
    min_app_version: str,
    host_key: str = "",
) -> dict[str, Any]:
    """Build deploy / QR / export node profile JSON (v2)."""
    payload: dict[str, Any] = {
        KEY_VERSION: PROFILE_VERSION,
        KEY_NAME: name,
        KEY_HOST: host,
        KEY_PORT: str(port),
        KEY_USER: user,
        KEY_PRIVATE_KEY: private_key,
        KEY_INSTALL_DIR: install_dir or DEFAULT_INSTALL_DIR,
        KEY_SERVER_VERSION: server_version or UNKNOWN_VERSION,
        KEY_MIN_APP_VERSION: min_app_version or UNKNOWN_VERSION,
    }
    if host_key.strip():
        payload[KEY_HOST_KEY] = [host_key.strip()]
    return payload
