from __future__ import annotations

from .paths import ChainContext, ensure_dirs


def chain_octet_from_id(chain_id: str) -> int:
    h = 2166136261
    for ch in chain_id.replace("-", "").encode():
        h = (h ^ ch) * 16777619
        h &= 0xFFFFFFFF
    return 1 + (h % 254)


def init_chain_context(chain_id: str) -> ChainContext:
    if not chain_id:
        from .logutil import die

        die("chain-id is required")
    octet = chain_octet_from_id(chain_id)
    ctx = ChainContext.for_chain(chain_id, octet)
    ensure_dirs()
    ctx.chain_dir.mkdir(parents=True, exist_ok=True)
    return ctx
