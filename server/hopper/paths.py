from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from .logutil import daily_hopper_log


def hopper_dir() -> Path:
    env = os.environ.get("HOPPER_DIR")
    if env:
        return Path(env).expanduser().resolve()
    return Path(__file__).resolve().parent.parent


def bin_dir() -> Path:
    return hopper_dir() / "dist"


def version_file() -> Path:
    return hopper_dir() / "VERSION.json"


def venv_dir() -> Path:
    return hopper_dir() / ".venv"


KEY_DIR = Path.home() / ".hopper"
KEY_PATH = KEY_DIR / "id_ed25519"
REGISTRY_FILE = KEY_DIR / "registry.json"
DAEMON_NAME = "hopperd"


@dataclass
class ChainContext:
    chain_id: str
    chain_dir: Path
    tun_name: str
    overlay_cidr: str
    listen_port: int
    hopper_ready: Path
    hopper_log: Path
    hopper_config: Path

    @classmethod
    def for_chain(cls, chain_id: str, octet: int) -> ChainContext:
        chain_dir = KEY_DIR / "chains" / chain_id
        tun = f"hopper_{chain_id.replace('-', '')}"[:15]
        return cls(
            chain_id=chain_id,
            chain_dir=chain_dir,
            tun_name=tun,
            overlay_cidr=f"10.64.{octet}.0/24",
            listen_port=7400 + octet,
            hopper_ready=chain_dir / "hopper-ready",
            hopper_log=daily_hopper_log(chain_dir),
            hopper_config=chain_dir / "hopper.json",
        )


def ensure_dirs() -> None:
    d = bin_dir()
    d.mkdir(parents=True, exist_ok=True)
    if os.geteuid() == 0:
        try:
            os.chmod(d, 0o755)
            st = d.stat()
            if st.st_uid != 0:
                os.chown(d, 0, st.st_gid)
        except OSError:
            pass
    KEY_DIR.mkdir(parents=True, exist_ok=True)
