#!/usr/bin/env bash
# Shared helpers for configure_server.sh and start_server.sh
set -euo pipefail

HOPPER_DIR="${HOPPER_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
BIN_DIR="${HOPPER_DIR}/dist"
KEY_DIR="${HOME}/.hopper"
KEY_PATH="${KEY_DIR}/id_ed25519"
DAEMON_NAME="hopperd"
TUN_NAME="hopper0"
OVERLAY_CIDR="${OVERLAY_CIDR:-10.64.0.0/24}"
HOPPER_READY="${KEY_DIR}/hopper-ready"
HOPPER_LOG="${KEY_DIR}/hopper.log"
HOPPER_CONFIG="${KEY_DIR}/hopper.json"
HOPPER_BIN=""

log() {
  echo "[$(date -Iseconds)] $*" >&2
}

die() {
  log "ERROR: $*"
  exit 1
}

detect_arch() {
  local machine
  machine="$(uname -m)"
  case "$machine" in
    x86_64 | amd64) echo "amd64" ;;
    aarch64 | arm64) echo "arm64" ;;
    *) die "Unsupported architecture: $machine" ;;
  esac
}

resolve_binary() {
  local arch dest
  arch="$(detect_arch)"
  dest="${BIN_DIR}/${DAEMON_NAME}-linux-${arch}"
  mkdir -p "$BIN_DIR" "$KEY_DIR"

  if [[ -f "$dest" ]]; then
    log "Using bundled ${DAEMON_NAME} at ${dest}"
  elif command -v go >/dev/null 2>&1 && [[ -f "${HOPPER_DIR}/cmd/hopperd/main.go" ]]; then
    log "Building ${DAEMON_NAME} into ${dest}..."
    (cd "${HOPPER_DIR}" && GOOS=linux GOARCH="$arch" CGO_ENABLED=0 go build -ldflags="-s -w" -o "$dest" "./cmd/hopperd")
  else
    die "Missing ${dest}. Run build_dist.sh locally and upload dist/ to ${BIN_DIR}/"
  fi

  chmod +x "$dest"
  if ! "$dest" -check >/dev/null 2>&1; then
    die "${dest} failed -check"
  fi
  HOPPER_BIN="$dest"
}

port_listening() {
  local port="$1"
  [[ -n "$port" ]] || return 1
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | grep -qE "[:.]${port}[[:space:]]"
    return
  fi
  command -v netstat >/dev/null 2>&1 && netstat -ltn 2>/dev/null | grep -qE "[:.]${port}[[:space:]]"
}

hopper_pids() {
  local pids=""
  if command -v pgrep >/dev/null 2>&1; then
    pids="$(pgrep -f "${DAEMON_NAME}-linux-" 2>/dev/null || true)"
    if [[ -z "$pids" ]]; then
      pids="$(pgrep -x "${DAEMON_NAME}" 2>/dev/null || true)"
    fi
    if [[ -z "$pids" ]]; then
      pids="$(pgrep -f "${HOPPER_CONFIG}" 2>/dev/null || true)"
    fi
  fi
  echo "$pids"
}

kill_hopper_port() {
  local port="${1:-7400}"
  if command -v fuser >/dev/null 2>&1; then
    fuser -k -TERM "${port}/tcp" 2>/dev/null || true
    sleep 0.2
    fuser -k -KILL "${port}/tcp" 2>/dev/null || true
    return
  fi
  if command -v ss >/dev/null 2>&1; then
    local pid
    pid="$(ss -ltnp 2>/dev/null | grep -E ":${port}[[:space:]]" | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | head -1)"
    if [[ -n "$pid" ]]; then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 0.2
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
}

stop_daemon() {
  resolve_binary 2>/dev/null || true

  local pid
  for pid in $(hopper_pids); do
    kill -TERM "$pid" 2>/dev/null || true
  done
  if [[ -n "${HOPPER_BIN:-}" ]]; then
    pkill -TERM -f "${HOPPER_BIN}" 2>/dev/null || true
  fi
  pkill -TERM -f "${DAEMON_NAME}-linux-" 2>/dev/null || true
  kill_hopper_port 7400

  local i
  for i in $(seq 1 30); do
    [[ -z "$(hopper_pids)" ]] && break
    sleep 0.1
  done

  for pid in $(hopper_pids); do
    kill -KILL "$pid" 2>/dev/null || true
  done
  pkill -KILL -f "${DAEMON_NAME}-linux-" 2>/dev/null || true
  kill_hopper_port 7400

  rm -f "$HOPPER_READY"
  log "Stopped previous hopperd instances"
}

write_hopper_config() {
  local role="$1" addr="$2" overlay="$3" client_addr="${4:-}"
  local next_host="${5:-}" next_port="${6:-}" next_user="${7:-}"

  python3 - "$role" "$addr" "$overlay" "$client_addr" "$next_host" "$next_port" "$next_user" "$KEY_PATH" "$HOPPER_CONFIG" <<'PY'
import json, pathlib, sys
role, addr, overlay, client_addr, next_host, next_port, next_user, key_path, cfg_path = sys.argv[1:10]
cfg = {
    "addr": addr,
    "overlay": overlay,
    "tun": "hopper0",
    "listen_host": "127.0.0.1",
    "listen_port": 7400,
}
if client_addr:
    cfg["client_addr"] = client_addr
if role == "exit":
    cfg["nat"] = True
elif next_host:
    cfg["next"] = {
        "host": next_host,
        "port": int(next_port or 22),
        "user": next_user or "",
        "key_path": key_path,
    }
pathlib.Path(cfg_path).write_text(json.dumps(cfg, indent=2) + "\n")
PY
}

setup_nat() {
  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || log "WARN: could not enable ip_forward"
  command -v iptables >/dev/null 2>&1 || {
    log "WARN: iptables not found"
    return
  }
  local iface
  iface="$(ip route show default 2>/dev/null | awk '{print $5; exit}')"
  [[ -n "$iface" ]] || return
  if ! iptables -t nat -C POSTROUTING -s "${OVERLAY_CIDR}" -o "$iface" -j MASQUERADE 2>/dev/null; then
    iptables -t nat -A POSTROUTING -s "${OVERLAY_CIDR}" -o "$iface" -j MASQUERADE 2>/dev/null \
      || log "WARN: MASQUERADE failed (need root)"
  fi
  if ! iptables -C FORWARD -i "$TUN_NAME" -j ACCEPT 2>/dev/null; then
    iptables -A FORWARD -i "$TUN_NAME" -j ACCEPT 2>/dev/null || true
  fi
  if ! iptables -C FORWARD -o "$TUN_NAME" -j ACCEPT 2>/dev/null; then
    iptables -A FORWARD -o "$TUN_NAME" -j ACCEPT 2>/dev/null || true
  fi
  if ! iptables -C FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
    iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
  fi
}

start_hopperd_detached() {
  resolve_binary
  sleep 0.2
  log "Starting hopperd (${HOPPER_CONFIG})"
  if command -v setsid >/dev/null 2>&1; then
    setsid -f "$HOPPER_BIN" -verbose --config "$HOPPER_CONFIG" --ready-file "$HOPPER_READY" >>"$HOPPER_LOG" 2>&1 < /dev/zero &
  else
    nohup "$HOPPER_BIN" -verbose --config "$HOPPER_CONFIG" --ready-file "$HOPPER_READY" >>"$HOPPER_LOG" 2>&1 < /dev/zero &
  fi
  local i port
  for i in $(seq 1 40); do
    if [[ -s "$HOPPER_READY" ]] && pgrep -f "${DAEMON_NAME}" >/dev/null 2>&1; then
      port="$(awk '/^READY /{print $2; exit}' "$HOPPER_READY")"
      if port_listening "$port"; then
        echo "$port"
        return 0
      fi
    fi
    sleep 0.25
  done
  die "hopperd failed — see ${HOPPER_LOG}"
}

trust_pubkey() {
  local pubkey="$1"
  [[ -n "$pubkey" ]] || return 0
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"
  touch "${HOME}/.ssh/authorized_keys"
  chmod 600 "${HOME}/.ssh/authorized_keys"
  if grep -qF "$pubkey" "${HOME}/.ssh/authorized_keys" 2>/dev/null; then
    return 0
  fi
  echo "$pubkey hopper-peer" >>"${HOME}/.ssh/authorized_keys"
}

emit_ready_json() {
  local role="$1" addr="$2" index="$3" overlay="$4" port="$5"
  python3 - "$role" "$addr" "$index" "$overlay" "$port" <<'PY'
import json, sys
role, addr, index, overlay, port = sys.argv[1:6]
print(json.dumps({
    "ready": True,
    "mode": role,
    "addr": addr,
    "index": int(index),
    "overlay": overlay,
    "port": int(port),
    "nat": role == "exit",
}, separators=(",", ":")))
PY
}
