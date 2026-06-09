#!/usr/bin/env bash
# Build hopperd and deploy to a remote Linux server over SSH (as root).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="${SCRIPT_DIR}/dist"

log() { echo "[deploy] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

usage() {
  cat <<'EOF'
Usage: deploy.sh [options] [host]

Deploy hopper bundle (binaries + scripts) to a remote server.

Options:
  -h, --help              Show this help
  -u, --user USER         SSH user (default: root)
  -p, --port PORT         SSH port (default: 22)
  -i, --identity PATH     SSH private key (default: ~/.ssh/id_rsa)
  -P, --path PATH         Remote install directory (default: ~/hopper)
  -y, --yes               Skip deploy confirmation prompt
  --no-build              Do not run build_dist.sh first

Environment overrides: DEPLOY_HOST, DEPLOY_USER, DEPLOY_PORT, DEPLOY_KEY, DEPLOY_PATH

Examples:
  ./deploy.sh 203.0.113.10
  ./deploy.sh -u root -P /opt/hopper 203.0.113.10
EOF
}

SSH_USER="${DEPLOY_USER:-root}"
SSH_PORT="${DEPLOY_PORT:-22}"
SSH_KEY="${DEPLOY_KEY:-$HOME/.ssh/id_rsa}"
REMOTE_PATH="${DEPLOY_PATH:-~/hopper}"
SSH_HOST="${DEPLOY_HOST:-}"
SKIP_CONFIRM=0
RUN_BUILD=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    -u | --user) SSH_USER="$2"; shift 2 ;;
    -p | --port) SSH_PORT="$2"; shift 2 ;;
    -i | --identity) SSH_KEY="$2"; shift 2 ;;
    -P | --path) REMOTE_PATH="$2"; shift 2 ;;
    -y | --yes) SKIP_CONFIRM=1; shift ;;
    --no-build) RUN_BUILD=0; shift ;;
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
SCP_BASE=(scp -i "$SSH_KEY" -P "$SSH_PORT" -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new)
RSYNC_RSH="ssh -i ${SSH_KEY} -p ${SSH_PORT} -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new"

ssh_cmd() {
  "${SSH_BASE[@]}" "${SSH_USER}@${SSH_HOST}" "$@"
}

scp_to() {
  local src="$1" dst="$2"
  "${SCP_BASE[@]}" "$src" "${SSH_USER}@${SSH_HOST}:${dst}"
}

detect_remote_arch() {
  local machine
  machine="$(ssh_cmd 'uname -m' 2>/dev/null | tr -d '\r\n')"
  case "$machine" in
    x86_64 | amd64) echo "amd64" ;;
    aarch64 | arm64) echo "arm64" ;;
    *) die "Unsupported remote architecture: ${machine:-unknown}" ;;
  esac
}

if [[ "$RUN_BUILD" -eq 1 ]]; then
  log "Building Linux binaries..."
  "${SCRIPT_DIR}/build_dist.sh"
fi

[[ -d "$DIST" ]] || die "Missing ${DIST}/ — run build_dist.sh first"
for arch in amd64 arm64; do
  [[ -f "${DIST}/hopperd-linux-${arch}" ]] || die "Missing ${DIST}/hopperd-linux-${arch}"
done

for script in hopper_common.sh configure_server.sh start_server.sh; do
  [[ -f "${SCRIPT_DIR}/${script}" ]] || die "Missing ${SCRIPT_DIR}/${script}"
done

REMOTE_ARCH="$(detect_remote_arch)"
log "Remote ${SSH_USER}@${SSH_HOST}:${SSH_PORT} (${REMOTE_ARCH}) → ${REMOTE_PATH}"

if [[ "$SKIP_CONFIRM" -eq 0 ]]; then
  printf 'Deploy to %s:%s as %s? [Y/n] ' "$SSH_HOST" "$REMOTE_PATH" "$SSH_USER"
  read -r confirm
  if [[ -n "${confirm}" && ! "${confirm}" =~ ^[Yy]$ ]]; then
    log "Cancelled."
    exit 0
  fi
fi

log "Checking SSH connection..."
ssh_cmd 'echo ok' >/dev/null || die "SSH to ${SSH_USER}@${SSH_HOST} failed"

log "Creating remote directories..."
ssh_cmd "mkdir -p ${REMOTE_PATH}/dist"

FILES=(
  hopper_common.sh
  configure_server.sh
  start_server.sh
)

if command -v rsync >/dev/null 2>&1; then
  log "Uploading scripts (rsync)..."
  rsync -az -e "$RSYNC_RSH" \
    "${FILES[@]/#/${SCRIPT_DIR}/}" \
    "${SSH_USER}@${SSH_HOST}:${REMOTE_PATH}/"

  log "Uploading binaries (rsync)..."
  rsync -az -e "$RSYNC_RSH" \
    "${DIST}/hopperd-linux-amd64" \
    "${DIST}/hopperd-linux-arm64" \
    "${SSH_USER}@${SSH_HOST}:${REMOTE_PATH}/dist/"
else
  log "Uploading scripts (scp)..."
  for f in "${FILES[@]}"; do
    scp_to "${SCRIPT_DIR}/${f}" "${REMOTE_PATH}/"
  done

  log "Uploading binaries (scp)..."
  scp_to "${DIST}/hopperd-linux-amd64" "${REMOTE_PATH}/dist/"
  scp_to "${DIST}/hopperd-linux-arm64" "${REMOTE_PATH}/dist/"
fi

log "Setting permissions..."
ssh_cmd "chmod +x ${REMOTE_PATH}/*.sh ${REMOTE_PATH}/dist/hopperd-linux-*"

log "Verifying remote binary..."
ssh_cmd "${REMOTE_PATH}/dist/hopperd-linux-${REMOTE_ARCH} -check" | grep -q OK \
  || die "Remote hopperd -check failed"

log "Deployed to ${SSH_USER}@${SSH_HOST}:${REMOTE_PATH}"
log "Primary binary: ${REMOTE_PATH}/dist/hopperd-linux-${REMOTE_ARCH}"

log "Running configure_server.sh on remote (JSON)..."
payload="$(ssh_cmd "cd ${REMOTE_PATH} && ./configure_server.sh --json-only --host ${SSH_HOST} --port ${SSH_PORT}" 2>/dev/null | tail -1)"
[[ -n "$payload" && "$payload" == \{* ]] || die "configure_server.sh did not return JSON payload"

qr_html="${SCRIPT_DIR}/qr-${SSH_HOST//[^a-zA-Z0-9._-]/_}.html"
log "Writing ${qr_html}..."
python3 - "$qr_html" "$payload" "$SSH_HOST" <<'PY'
import html
import json
import pathlib
import sys

out_path, payload_raw, host = sys.argv[1:4]
json.loads(payload_raw)  # validate
payload_js = json.dumps(payload_raw)
title = f"Hopper — {host}"
doc = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js" crossorigin="anonymous"></script>
  <style>
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0; min-height: 100vh; display: flex; flex-direction: column;
      align-items: center; justify-content: center; gap: 1.25rem;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #1b2f4b; color: #e8f5e9;
    }}
    h1 {{ margin: 0; font-size: 1.25rem; font-weight: 600; }}
    p {{ margin: 0; max-width: 32rem; text-align: center; opacity: 0.85; font-size: 0.9rem; }}
    #qrcode {{
      padding: 1rem; background: #fff; border-radius: 12px;
      box-shadow: 0 8px 32px rgba(0,0,0,0.35);
    }}
    pre {{
      margin: 0; padding: 0.75rem 1rem; max-width: 90vw; overflow: auto;
      font-size: 0.65rem; background: rgba(0,0,0,0.25); border-radius: 8px;
    }}
  </style>
</head>
<body>
  <h1>ɹǝddoH — scan to add hop</h1>
  <p>Add in chain order: entry → exit</p>
  <div id="qrcode"></div>
  <pre id="payload"></pre>
  <script>
    const payload = {payload_js};
    document.getElementById("payload").textContent = payload;
    new QRCode(document.getElementById("qrcode"), {{
      text: payload,
      width: 320,
      height: 320,
      correctLevel: QRCode.CorrectLevel.M,
    }});
  </script>
</body>
</html>
"""
pathlib.Path(out_path).write_text(doc)
PY

open_in_browser() {
  local file="$1"
  local uri="file://${file}"
  if command -v open >/dev/null 2>&1; then
    open "$file"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$file"
  else
    log "Open in browser: ${uri}"
    return 1
  fi
}

log "Opening QR page in browser..."
open_in_browser "$qr_html" || true
sleep 5
rm -f "$qr_html"
log "QR page opened — scan with the app (temporary HTML removed)"
