from __future__ import annotations

import json
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
