#!/usr/bin/env bash
# Client-invoked (SSH exec). Non-interactive. Logs to stderr; prints one JSON line on stdout.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOPPER_DIR="${HOPPER_DIR:-$SCRIPT_DIR}"
source "${SCRIPT_DIR}/hopper_common.sh"

ROLE=""
ADDR=""
INDEX=""
OVERLAY="${OVERLAY_CIDR}"
CLIENT_ADDR=""
NEXT_HOST=""
NEXT_PORT="22"
NEXT_USER=""
TRUST_PUBKEY=""
TRUST_ONLY=0
STOP_ONLY=0

usage() {
  cat >&2 <<'EOF'
Usage: start_server.sh --role exit|relay --addr A.B.C.D --index N
       [--overlay CIDR] [--client-addr A.B.C.D]
       [--next-host H --next-port P --next-user U]
       [--trust-pubkey 'ssh-ed25519 AAAA...'] [--trust-only]
       [--stop-only]
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="$2"; shift 2 ;;
    --addr) ADDR="$2"; shift 2 ;;
    --index) INDEX="$2"; shift 2 ;;
    --overlay) OVERLAY="$2"; shift 2 ;;
    --client-addr) CLIENT_ADDR="$2"; shift 2 ;;
    --next-host) NEXT_HOST="$2"; shift 2 ;;
    --next-port) NEXT_PORT="$2"; shift 2 ;;
    --next-user) NEXT_USER="$2"; shift 2 ;;
    --trust-pubkey) TRUST_PUBKEY="$2"; shift 2 ;;
    --trust-only) TRUST_ONLY=1; shift ;;
    --stop-only) STOP_ONLY=1; shift ;;
    --hopper-dir) export HOPPER_DIR="$2"; BIN_DIR="${HOPPER_DIR}/dist"; shift 2 ;;
    -h | --help) usage ;;
    *) die "Unknown argument: $1" ;;
  esac
done

if [[ "$STOP_ONLY" -eq 1 ]]; then
  stop_daemon
  python3 -c 'import json; print(json.dumps({"stopped": True}))'
  exit 0
fi

if [[ -n "$TRUST_PUBKEY" ]]; then
  trust_pubkey "$TRUST_PUBKEY"
  if [[ "$TRUST_ONLY" -eq 1 ]]; then
    python3 -c 'import json; print(json.dumps({"trusted": True}))'
    exit 0
  fi
fi

[[ -n "$ROLE" && -n "$ADDR" && "$INDEX" != "" ]] || usage

stop_daemon

if [[ "$ROLE" == "exit" ]]; then
  :
elif [[ "$ROLE" == "relay" ]]; then
  [[ -n "$NEXT_HOST" && -n "$NEXT_USER" ]] || die "relay node requires --next-host and --next-user"
else
  die "role must be exit or relay"
fi

write_hopper_config "$ROLE" "$ADDR" "$OVERLAY" "$CLIENT_ADDR" "$NEXT_HOST" "$NEXT_PORT" "$NEXT_USER"

if [[ "$ROLE" == "exit" ]]; then
  setup_nat || true
fi

port="$(start_hopperd_detached)"
emit_ready_json "$ROLE" "$ADDR" "$INDEX" "$OVERLAY" "$port"
