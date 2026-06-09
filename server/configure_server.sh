#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOPPER_DIR="$SCRIPT_DIR"
source "${SCRIPT_DIR}/hopper_common.sh"

JSON_ONLY=0
CLI_HOST=""
CLI_PORT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json-only) JSON_ONLY=1; shift ;;
    --host) CLI_HOST="$2"; shift 2 ;;
    --port) CLI_PORT="$2"; shift 2 ;;
    -h | --help)
      echo "Usage: configure_server.sh [--json-only] [--host H] [--port P]" >&2
      exit 0
      ;;
    *) die "Unknown argument: $1" ;;
  esac
done

fetch_public_ip() {
  local ip=""
  if command -v curl >/dev/null 2>&1; then
    ip="$(curl -fsSL --max-time 10 "https://whatismyip.akamai.com/" 2>/dev/null | tr -d '\r\n' || true)"
  fi
  [[ -n "$ip" ]] && { echo "$ip"; return; }
  ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  [[ -n "$ip" ]] && { echo "$ip"; return; }
  echo "127.0.0.1"
}

read_host_key() {
  command -v ssh-keyscan >/dev/null 2>&1 || return 0
  local host="$1" port="$2" line keytype key
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    keytype=$(echo "$line" | awk '{print $2}')
    key=$(echo "$line" | awk '{print $3}')
    if [[ "$keytype" == ssh-ed25519 || "$keytype" == ssh-rsa ]]; then
      echo "${keytype} ${key}"
      return 0
    fi
  done < <(ssh-keyscan -p "$port" -t ed25519,rsa "$host" 2>/dev/null || true)
  echo ""
}

ensure_keypair() {
  mkdir -p "$KEY_DIR" "${HOME}/.ssh"
  chmod 700 "$KEY_DIR" "${HOME}/.ssh"
  if [[ -f "$KEY_PATH" ]]; then
    return
  fi
  command -v ssh-keygen >/dev/null 2>&1 || die "ssh-keygen required"
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "hopper@$(hostname -f 2>/dev/null || hostname)"
  chmod 600 "$KEY_PATH"
  chmod 644 "${KEY_PATH}.pub"
}

install_authorized_key() {
  local pub
  pub="$(cat "${KEY_PATH}.pub")"
  mkdir -p "${HOME}/.ssh"
  touch "${HOME}/.ssh/authorized_keys"
  chmod 600 "${HOME}/.ssh/authorized_keys"
  grep -qF "$pub" "${HOME}/.ssh/authorized_keys" 2>/dev/null || echo "$pub hopper-$(hostname)" >>"${HOME}/.ssh/authorized_keys"
}

maybe_setcap() {
  resolve_binary
  if [[ "$(id -u)" -ne 0 ]]; then
    log "Tip: run as root once to setcap hopperd, or allow passwordless sudo for start_server.sh"
    return
  fi
  if command -v setcap >/dev/null 2>&1; then
    setcap cap_net_admin+ep "$HOPPER_BIN" 2>/dev/null || log "WARN: setcap failed"
  fi
}

print_profile() {
  local payload="$1"
  log ""
  log "Hopper node profile (JSON) — import via deploy.sh QR or paste into the app."
  echo "$payload"
  log "Install path: ${HOPPER_DIR}"
}

main() {
  require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required: $1"; }
  require_cmd python3

  local user host port host_key name payload
  user="$(id -un)"
  host="${CLI_HOST:-$(fetch_public_ip)}"
  port="${CLI_PORT:-22}"

  if [[ "$JSON_ONLY" -eq 0 && -t 0 ]]; then
    printf 'SSH host for clients [%s]: ' "$host"
    read -r input_host
    [[ -n "${input_host// }" ]] && host="$input_host"
    printf 'SSH port [%s]: ' "$port"
    read -r input_port
    [[ -n "${input_port// }" ]] && port="$input_port"
  fi

  ensure_keypair
  install_authorized_key
  maybe_setcap

  name="$(hostname -f 2>/dev/null || hostname)"
  host_key="$(read_host_key "$host" "$port")"

  payload="$(python3 - "$host" "$port" "$user" "$name" "$KEY_PATH" "$host_key" "$HOPPER_DIR" <<'PY'
import json, pathlib, sys
host, port, user, name, key_path, host_key, install_dir = sys.argv[1:8]
payload = {
    "v": 2,
    "name": name,
    "host": host,
    "port": str(port),
    "user": user,
    "private_key": pathlib.Path(key_path).read_text(),
    "install_dir": install_dir,
}
if host_key.strip():
    payload["host_key"] = [host_key.strip()]
print(json.dumps(payload, separators=(",", ":")))
PY
)"

  if [[ "$JSON_ONLY" -eq 1 ]]; then
    echo "$payload"
  else
    print_profile "$payload"
  fi
}

main
