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
  --local                 Upload server tree from this repo instead of GitHub curl
  --binaries [DIR]        Rsync local hopperd-linux-* binary (default: server/dist)
  --no-binaries           With --local, do not upload dist/ even if present
  --no-qr                 Do not open QR import page

Environment: DEPLOY_HOST, DEPLOY_USER, DEPLOY_PORT, DEPLOY_KEY, DEPLOY_PATH,
             HOPPER_REF, HOPPER_INSTALL_URL, DEPLOY_BINARIES
EOF
}

SSH_USER="${DEPLOY_USER:-root}"
SSH_PORT="${DEPLOY_PORT:-22}"
SSH_KEY="${DEPLOY_KEY:-$HOME/.ssh/id_rsa}"
REMOTE_PATH="${DEPLOY_PATH:-~/hopper}"
SSH_HOST="${DEPLOY_HOST:-}"
SKIP_CONFIRM=0
NO_QR=0
USE_LOCAL=0
BINARIES_DIR=""
BINARIES_EXPLICIT=0
NO_BINARIES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    -u | --user) SSH_USER="$2"; shift 2 ;;
    -p | --port) SSH_PORT="$2"; shift 2 ;;
    -i | --identity) SSH_KEY="$2"; shift 2 ;;
    -P | --path) REMOTE_PATH="$2"; shift 2 ;;
    -y | --yes) SKIP_CONFIRM=1; shift ;;
    --ref) HOPPER_REF="$2"; INSTALL_URL="https://raw.githubusercontent.com/${HOPPER_REPO}/${HOPPER_REF}/server/install.sh"; shift 2 ;;
    --local) USE_LOCAL=1; shift ;;
    --binaries)
      BINARIES_EXPLICIT=1
      if [[ $# -ge 2 && "$2" != -* ]]; then
        BINARIES_DIR="$2"
        shift 2
      else
        BINARIES_DIR="${DEPLOY_BINARIES:-${SCRIPT_DIR}/dist}"
        shift
      fi
      ;;
    --no-binaries) NO_BINARIES=1; shift ;;
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
RSYNC_SSH=(ssh -i "$SSH_KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=accept-new)
ssh_cmd() { "${SSH_BASE[@]}" "${SSH_USER}@${SSH_HOST}" "$@"; }
rsync_to_remote() {
  rsync -az -e "$(printf '%q ' "${RSYNC_SSH[@]}")" "$@"
}

remote_linux_arch() {
  ssh_cmd 'case "$(uname -m)" in x86_64|amd64) echo amd64;; aarch64|arm64) echo arm64;; *) echo unknown;; esac'
}

resolve_binaries_dir() {
  if [[ "$NO_BINARIES" -eq 1 ]]; then
    return 1
  fi
  if [[ -n "$BINARIES_DIR" ]]; then
    [[ -d "$BINARIES_DIR" ]] || die "Binaries directory not found: $BINARIES_DIR"
    return 0
  fi
  if [[ "$USE_LOCAL" -eq 1 ]]; then
    BINARIES_DIR="${SCRIPT_DIR}/dist"
    [[ -d "$BINARIES_DIR" ]] || return 1
    local f
    for f in "${BINARIES_DIR}"/hopperd-linux-*; do
      [[ -f "$f" ]] && return 0
    done
    return 1
  fi
  return 1
}

sync_local_binaries() {
  local src_dir="$1"
  local arch name src remote_dist
  arch="$(remote_linux_arch)"
  [[ "$arch" != unknown ]] || die "Unsupported remote CPU architecture"
  name="hopperd-linux-${arch}"
  src="${src_dir}/${name}"
  [[ -f "$src" ]] || die "Missing local binary: ${src} (run ./build_dist.sh or pass --binaries DIR)"
  remote_dist="${REMOTE_PATH_EXPANDED}/dist"
  log "Uploading ${name} → ${remote_dist}/"
  ssh_cmd "mkdir -p $(printf %q "$remote_dist")"
  rsync_to_remote "$src" "${SSH_USER}@${SSH_HOST}:${remote_dist}/"
  ssh_cmd "chmod +x $(printf %q "${remote_dist}/${name}")"
}

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

USE_LOCAL_BINARIES=0
if resolve_binaries_dir; then
  USE_LOCAL_BINARIES=1
elif [[ "$BINARIES_EXPLICIT" -eq 1 ]]; then
  die "No hopperd binary found under ${BINARIES_DIR}"
fi

extract_json_line() {
  python3 -c '
import sys
for line in reversed(sys.stdin.read().splitlines()):
    s = line.strip()
    if s.startswith("{"):
        print(s)
        break
'
}

log "Running remote install..."
install_out="$(mktemp)"
install_err="$(mktemp)"
trap 'rm -f "$install_out" "$install_err"' EXIT
install_args=(--configure --host "$SSH_HOST" --port "$SSH_PORT")
[[ "$USE_LOCAL_BINARIES" -eq 1 ]] && install_args=(--skip-binary "${install_args[@]}")
install_args_quoted="$(printf '%q ' "${install_args[@]}")"
install_failed=0
if [[ "$USE_LOCAL" -eq 1 ]]; then
  log "Uploading local server tree to ${REMOTE_PATH_EXPANDED}..."
  ssh_cmd "mkdir -p $(printf %q "$REMOTE_PATH_EXPANDED")"
  rsync_to_remote \
    --exclude '.venv/' --exclude 'dist/' --exclude '.repo/' \
    "${SCRIPT_DIR}/" "${SSH_USER}@${SSH_HOST}:${REMOTE_PATH_EXPANDED}/"
  if [[ "$USE_LOCAL_BINARIES" -eq 1 ]]; then
    sync_local_binaries "$BINARIES_DIR"
  fi
  remote_install_cmd="cd $(printf %q "$REMOTE_PATH_EXPANDED") && ./install.sh --skip-sync ${install_args_quoted}"
  ssh_cmd "$remote_install_cmd" >"$install_out" 2>"$install_err" || install_failed=1
else
  if [[ "$USE_LOCAL_BINARIES" -eq 1 ]]; then
    sync_local_binaries "$BINARIES_DIR"
  fi
  log "Remote install URL: ${INSTALL_URL}"
  remote_install_cmd="curl -fsSL $(printf %q "$INSTALL_URL") | HOPPER_REF=$(printf %q "$HOPPER_REF") HOPPER_INSTALL_DIR=$(printf %q "$REMOTE_PATH_EXPANDED") bash -s -- ${install_args_quoted}"
  ssh_cmd "$remote_install_cmd" >"$install_out" 2>"$install_err" || install_failed=1
fi
if [[ "$install_failed" -eq 1 ]]; then
  [[ -s "$install_err" ]] && cat "$install_err" >&2
  [[ -s "$install_out" ]] && cat "$install_out" >&2
  die "Remote install command failed (see output above)"
fi
[[ -s "$install_err" ]] && cat "$install_err" >&2
payload="$(extract_json_line <"$install_out")"
[[ -n "$payload" ]] || {
  [[ -s "$install_out" ]] && cat "$install_out" >&2
  die "Remote install did not return JSON profile"
}

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
