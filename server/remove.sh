#!/usr/bin/env bash
# Remove hopper install from a remote server (reverts deploy.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "[remove] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

usage() {
  cat <<'EOF'
Usage: remove.sh [options] [host]

Stop hopperd and remove hopper bundle, ~/.hopper, TUN, and hopper SSH keys.

Options:
  -h, --help              Show this help
  -u, --user USER         SSH user (default: root)
  -p, --port PORT         SSH port (default: 22)
  -i, --identity PATH     SSH private key (default: ~/.ssh/id_rsa)
  -P, --path PATH         Remote install directory (default: ~/hopper)
  -y, --yes               Skip confirmation prompt

Environment overrides: DEPLOY_HOST, DEPLOY_USER, DEPLOY_PORT, DEPLOY_KEY, DEPLOY_PATH

Examples:
  ./remove.sh 203.0.113.10
  ./remove.sh -y -P /opt/hopper 203.0.113.10
EOF
}

SSH_USER="${DEPLOY_USER:-root}"
SSH_PORT="${DEPLOY_PORT:-22}"
SSH_KEY="${DEPLOY_KEY:-$HOME/.ssh/id_rsa}"
REMOTE_PATH="${DEPLOY_PATH:-~/hopper}"
SSH_HOST="${DEPLOY_HOST:-}"
SKIP_CONFIRM=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    -u | --user) SSH_USER="$2"; shift 2 ;;
    -p | --port) SSH_PORT="$2"; shift 2 ;;
    -i | --identity) SSH_KEY="$2"; shift 2 ;;
    -P | --path) REMOTE_PATH="$2"; shift 2 ;;
    -y | --yes) SKIP_CONFIRM=1; shift ;;
    -*) die "Unknown option: $1 (try --help)" ;;
    *)
      [[ -z "$SSH_HOST" ]] || die "Unexpected argument: $1"
      SSH_HOST="$1"
      shift
      ;;
  esac
done

if [[ -z "$SSH_HOST" ]]; then
  printf 'Server IP or hostname: '
  read -r SSH_HOST
  SSH_HOST="${SSH_HOST// /}"
fi
[[ -n "$SSH_HOST" ]] || die "Host is required"

if [[ ! -f "$SSH_KEY" ]]; then
  die "SSH key not found: $SSH_KEY"
fi

SSH_BASE=(ssh -i "$SSH_KEY" -p "$SSH_PORT" -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new)

ssh_cmd() {
  "${SSH_BASE[@]}" "${SSH_USER}@${SSH_HOST}" "$@"
}

log "Target ${SSH_USER}@${SSH_HOST}:${SSH_PORT} install=${REMOTE_PATH}"

if [[ "$SKIP_CONFIRM" -eq 0 ]]; then
  printf 'Remove hopper from %s (%s)? [y/N] ' "$SSH_HOST" "$REMOTE_PATH"
  read -r confirm
  [[ "${confirm}" =~ ^[Yy]$ ]] || { log "Cancelled."; exit 0; }
fi

log "Checking SSH connection..."
ssh_cmd 'echo ok' >/dev/null || die "SSH to ${SSH_USER}@${SSH_HOST} failed"

log "Stopping hopperd and removing files on remote..."
ssh_cmd "REMOTE_PATH=$(printf '%q' "$REMOTE_PATH") bash -s" <<'REMOTE'
set -euo pipefail

KEY_DIR="${HOME}/.hopper"
TUN_NAME="hopper0"
OVERLAY_CIDR="10.64.0.0/24"
DAEMON_NAME="hopperd"

log() { echo "[remove@remote] $*" >&2; }

stop_hopperd() {
  if [[ -f "${REMOTE_PATH}/hopper_common.sh" ]]; then
    export HOPPER_DIR="${REMOTE_PATH}"
    # shellcheck source=/dev/null
    source "${REMOTE_PATH}/hopper_common.sh"
    stop_daemon || true
    return
  fi

  pkill -TERM -f "${DAEMON_NAME}-linux-" 2>/dev/null || true
  if command -v fuser >/dev/null 2>&1; then
    fuser -k -TERM 7400/tcp 2>/dev/null || true
    sleep 0.2
    fuser -k -KILL 7400/tcp 2>/dev/null || true
  fi
  pkill -KILL -f "${DAEMON_NAME}-linux-" 2>/dev/null || true
}

teardown_tun() {
  command -v ip >/dev/null 2>&1 || return 0
  ip link set "${TUN_NAME}" down 2>/dev/null || true
  ip route del "${OVERLAY_CIDR}" dev "${TUN_NAME}" 2>/dev/null || true
  ip addr flush dev "${TUN_NAME}" 2>/dev/null || true
  ip link delete "${TUN_NAME}" 2>/dev/null || true
}

teardown_nat() {
  command -v iptables >/dev/null 2>&1 || return 0
  local iface
  iface="$(ip route show default 2>/dev/null | awk '{print $5; exit}')"
  if [[ -n "${iface}" ]]; then
    iptables -t nat -D POSTROUTING -s "${OVERLAY_CIDR}" -o "${iface}" -j MASQUERADE 2>/dev/null || true
  fi
  iptables -D FORWARD -i "${TUN_NAME}" -j ACCEPT 2>/dev/null || true
  iptables -D FORWARD -o "${TUN_NAME}" -j ACCEPT 2>/dev/null || true
  iptables -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
}

clean_authorized_keys() {
  local auth="${HOME}/.ssh/authorized_keys"
  [[ -f "${auth}" ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0

  local pub_file=""
  [[ -f "${KEY_DIR}/id_ed25519.pub" ]] && pub_file="${KEY_DIR}/id_ed25519.pub"

  python3 - "${auth}" "${pub_file}" <<'PY'
import pathlib, sys
auth_path, pub_path = sys.argv[1:3]
needle = ""
if pub_path:
    pub = pathlib.Path(pub_path).read_text().split()
    if len(pub) >= 2:
        needle = f"{pub[0]} {pub[1]}"
lines = pathlib.Path(auth_path).read_text().splitlines()
kept = []
for line in lines:
    s = line.strip()
    if not s or s.startswith("#"):
        kept.append(line)
        continue
    if needle and needle in line:
        continue
    parts = s.split()
    if parts and (parts[-1].startswith("hopper-") or parts[-1] == "hopper-peer"):
        continue
    kept.append(line)
pathlib.Path(auth_path).write_text("\n".join(kept) + ("\n" if kept else ""))
PY
  log "Cleaned hopper entries from authorized_keys"
}

stop_hopperd
teardown_tun
teardown_nat
clean_authorized_keys
rm -rf "${KEY_DIR}"
rm -rf "${REMOTE_PATH}"
log "Removed ${REMOTE_PATH} and ${KEY_DIR}"
REMOTE

qr_html="${SCRIPT_DIR}/qr-${SSH_HOST//[^a-zA-Z0-9._-]/_}.html"
rm -f "$qr_html"

log "Done — hopper removed from ${SSH_USER}@${SSH_HOST}"
