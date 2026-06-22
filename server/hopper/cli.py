from __future__ import annotations

import sys

from .commands.configure import run_configure
from .commands.install import run_install
from .commands.remove import run_remove
from .commands.start import run_start
from .commands.status import run_status
from .commands.update import run_update


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv or argv[0] in ("-h", "--help"):
        print(
            "Usage: hopper <command> [options]\n\n"
            "Commands:\n"
            "  install     Bootstrap venv, package, hopperd binary\n"
            "  configure   Generate hop profile JSON\n"
            "  start       Start/stop hopperd for a chain\n"
            "  status      Report chain runtime status\n"
            "  update      Check or apply server update from git\n"
            "  remove      Remove hopper install from this host",
            file=sys.stderr,
        )
        return 0 if argv and argv[0] in ("-h", "--help") else (2 if argv else 0)

    cmd, rest = argv[0], argv[1:]
    handlers = {
        "install": run_install,
        "configure": run_configure,
        "start": run_start,
        "status": run_status,
        "update": run_update,
        "remove": run_remove,
    }
    handler = handlers.get(cmd)
    if not handler:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        return 2
    return handler(rest)


if __name__ == "__main__":
    raise SystemExit(main())
