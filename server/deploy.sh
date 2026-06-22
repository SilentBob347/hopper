#!/usr/bin/env bash
# Deploy hopper to a remote Linux server via curl | bash install.sh one-liner.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HOPPER_REPO="${HOPPER_REPO:-ZonD80/hopper}"
HOPPER_REF="${HOPPER_REF:-main}"
INSTALL_URL="${HOPPER_INSTALL_URL:-https://raw.githubusercontent.com/${HOPPER_REPO}/${HOPPER_REF}/server/install.sh}"

log() { echo "[deploy] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

usage() {
  cat <<EOF
Usage: deploy.sh [options] [host]

Deploy hopper to a remote server using the install script from GitHub.

One-liner (manual):
  ssh root@HOST 'curl -fsSL ${INSTALL_URL} | HOPPER_REF=${HOPPER_REF} HOPPER_INSTALL_DIR=~/hopper bash -s -- --configure --host HOST --port 22'

Options:
  -h, --help              Show this help
  -u, --user USER         SSH user (default: root)
  -p, --port PORT         SSH port (default: 22)
  -i, --identity PATH     SSH private key (default: ~/.ssh/id_rsa)
  -P, --path PATH         Remote install directory (default: ~/hopper)
  -y, --yes               Skip deploy confirmation prompt
  --ref TAG               Git ref for install.sh (default: ${HOPPER_REF})
  --no-qr                 Do not open QR import page

Environment: DEPLOY_HOST, DEPLOY_USER, DEPLOY_PORT, DEPLOY_KEY, DEPLOY_PATH, HOPPER_REF, HOPPER_INSTALL_URL
EOF
}

SSH_USER="${DEPLOY_USER:-root}"
SSH_PORT="${DEPLOY_PORT:-22}"
SSH_KEY="${DEPLOY_KEY:-$HOME/.ssh/id_rsa}"
REMOTE_PATH="${DEPLOY_PATH:-~/hopper}"
SSH_HOST="${DEPLOY_HOST:-}"
SKIP_CONFIRM=0
NO_QR=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    -u | --user) SSH_USER="$2"; shift 2 ;;
    -p | --port) SSH_PORT="$2"; shift 2 ;;
    -i | --identity) SSH_KEY="$2"; shift 2 ;;
    -P | --path) REMOTE_PATH="$2"; shift 2 ;;
    -y | --yes) SKIP_CONFIRM=1; shift ;;
    --ref) HOPPER_REF="$2"; INSTALL_URL="https://raw.githubusercontent.com/${HOPPER_REPO}/${HOPPER_REF}/server/install.sh"; shift 2 ;;
    --no-qr) NO_QR=1; shift ;;
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

log "Remote ${SSH_USER}@${SSH_HOST}:${SSH_PORT} → ${REMOTE_PATH} (ref=${HOPPER_REF})"

if [[ "$SKIP_CONFIRM" -eq 0 ]]; then
  printf 'Deploy to %s:%s as %s? [Y/n] ' "$SSH_HOST" "$REMOTE_PATH" "$SSH_USER"
  read -r confirm
  if [[ -n "${confirm}" && ! "${confirm}" =~ ^[Yy]$ ]]; then
    log "Cancelled."
    exit 0
  fi
fi

read_identity_public_key() {
  local pub="${SSH_KEY}.pub"
  if [[ -f "$pub" ]]; then
    tr -d '\r\n' < "$pub"
    return 0
  fi
  ssh-keygen -y -f "$SSH_KEY" 2>/dev/null | tr -d '\r\n'
}

ensure_identity_in_authorized_keys() {
  local pub
  pub="$(read_identity_public_key)" || true
  [[ -n "$pub" ]] || die "Cannot derive public key from ${SSH_KEY}"

  log "Ensuring deploy key is in ${SSH_USER} authorized_keys..."
  if ssh_cmd "grep -qF $(printf %q "$pub") ~/.ssh/authorized_keys 2>/dev/null"; then
    log "Deploy key already authorized."
    return 0
  fi
  ssh_cmd "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo $(printf %q "$pub") deploy-\$(hostname -s 2>/dev/null || hostname) >>~/.ssh/authorized_keys"
  log "Added deploy key to authorized_keys."
}

log "Checking SSH connection..."
ssh_cmd 'echo ok' >/dev/null || die "SSH to ${SSH_USER}@${SSH_HOST} failed"
ensure_identity_in_authorized_keys

REMOTE_PATH_EXPANDED="$(ssh_cmd "eval echo $(printf %q "$REMOTE_PATH")")"

log "Running remote install from ${INSTALL_URL}..."
payload="$(ssh_cmd "curl -fsSL $(printf %q "$INSTALL_URL") | HOPPER_REF=$(printf %q "$HOPPER_REF") HOPPER_INSTALL_DIR=$(printf %q "$REMOTE_PATH_EXPANDED") bash -s -- --configure --host $(printf %q "$SSH_HOST") --port $(printf %q "$SSH_PORT")" 2>/dev/null | tail -1)"
[[ -n "$payload" && "$payload" == \{* ]] || die "Remote install did not return JSON profile"

log "Deployed to ${SSH_USER}@${SSH_HOST}:${REMOTE_PATH_EXPANDED}"

if [[ "$NO_QR" -eq 1 ]]; then
  echo "$payload"
  exit 0
fi

qr_html="${SCRIPT_DIR}/qr-${SSH_HOST//[^a-zA-Z0-9._-]/_}.html"
log "Writing ${qr_html}..."
export QR_HTML="$qr_html" PAYLOAD="$payload" QR_HOST="$SSH_HOST"
PYTHONPATH="${SCRIPT_DIR}" python3 <<'PY'
import os
from pathlib import Path
from hopper.qr import write_qr_html
write_qr_html(Path(os.environ["QR_HTML"]), os.environ["PAYLOAD"], os.environ["QR_HOST"])
PY

open_in_browser() {
  local file="$1"
  if command -v open >/dev/null 2>&1; then open "$file"
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$file"
  else log "Open in browser: file://${file}"; return 1; fi
}

log "Opening QR page in browser..."
open_in_browser "$qr_html" || true
sleep 5
rm -f "$qr_html"
log "QR page opened — scan with the app (temporary HTML removed)"
