#!/usr/bin/env bash
# Remove hopper install from a remote server.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HOPPER_REPO="${HOPPER_REPO:-ZonD80/hopper}"
HOPPER_REF="${HOPPER_REF:-main}"
INSTALL_URL="${HOPPER_INSTALL_URL:-https://raw.githubusercontent.com/${HOPPER_REPO}/${HOPPER_REF}/server/install.sh}"

log() { echo "[remove] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

usage() {
  cat <<'EOF'
Usage: remove.sh [options] [host]

Stop hopperd and remove hopper bundle, ~/.hopper, TUNs, and hopper SSH keys.

Options:
  -h, --help              Show this help
  -u, --user USER         SSH user (default: root)
  -p, --port PORT         SSH port (default: 22)
  -i, --identity PATH     SSH private key (default: ~/.ssh/id_rsa)
  -P, --path PATH         Remote install directory (default: ~/hopper)
  -y, --yes               Skip confirmation prompt
  --ref TAG               Git ref for install.sh (default: main)

Environment: DEPLOY_HOST, DEPLOY_USER, DEPLOY_PORT, DEPLOY_KEY, DEPLOY_PATH, HOPPER_REF
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
    --ref) HOPPER_REF="$2"; INSTALL_URL="https://raw.githubusercontent.com/${HOPPER_REPO}/${HOPPER_REF}/server/install.sh"; shift 2 ;;
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
[[ -f "$SSH_KEY" ]] || die "SSH key not found: $SSH_KEY"

SSH_BASE=(ssh -i "$SSH_KEY" -p "$SSH_PORT" -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new)
ssh_cmd() { "${SSH_BASE[@]}" "${SSH_USER}@${SSH_HOST}" "$@"; }

log "Target ${SSH_USER}@${SSH_HOST}:${SSH_PORT} install=${REMOTE_PATH}"

if [[ "$SKIP_CONFIRM" -eq 0 ]]; then
  printf 'Remove hopper from %s (%s)? [y/N] ' "$SSH_HOST" "$REMOTE_PATH"
  read -r confirm
  [[ "${confirm}" =~ ^[Yy]$ ]] || { log "Cancelled."; exit 0; }
fi

log "Checking SSH connection..."
ssh_cmd 'echo ok' >/dev/null || die "SSH to ${SSH_USER}@${SSH_HOST} failed"

REMOTE_PATH_EXPANDED="$(ssh_cmd "eval echo $(printf %q "$REMOTE_PATH")")"

log "Removing hopper on remote..."
if ssh_cmd "test -x $(printf %q "${REMOTE_PATH_EXPANDED}/hopperctl")"; then
  ssh_cmd "$(printf %q "${REMOTE_PATH_EXPANDED}/hopperctl") remove -y"
else
  ssh_cmd "curl -fsSL $(printf %q "$INSTALL_URL") | HOPPER_INSTALL_DIR=$(printf %q "$REMOTE_PATH_EXPANDED") bash -s -- --remove -y" \
    || ssh_cmd "rm -rf $(printf %q "$REMOTE_PATH_EXPANDED") ~/.hopper"
fi

qr_html="${SCRIPT_DIR}/qr-${SSH_HOST//[^a-zA-Z0-9._-]/_}.html"
rm -f "$qr_html"

log "Done — hopper removed from ${SSH_USER}@${SSH_HOST}"
