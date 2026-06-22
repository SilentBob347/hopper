#!/usr/bin/env bash
# Hopper server bootstrap — pipe from raw.githubusercontent.com or run locally.
set -euo pipefail

HOPPER_REF="${HOPPER_REF:-main}"
HOPPER_INSTALL_DIR="${HOPPER_INSTALL_DIR:-${HOME}/hopper}"
HOPPER_GIT_REMOTE="${HOPPER_GIT_REMOTE:-https://github.com/ZonD80/hopper.git}"
HOPPER_GIT_SUBDIR="${HOPPER_GIT_SUBDIR:-server}"
RAW_BASE="${HOPPER_RAW_BASE:-https://raw.githubusercontent.com/ZonD80/hopper}"

log() { echo "[install] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Bootstrap hopper server (Python venv + hopperd) on this Linux host.

Options:
  --ref TAG           Git ref to install (default: main or HOPPER_REF)
  --dir PATH          Install directory (default: ~/hopper)
  --configure         Run hopper configure after install
  --host HOST         SSH host for profile (with --configure)
  --port PORT         SSH port for profile (default: 22)
  --remove            Remove hopper from this host
  -y, --yes           Skip confirmation for --remove
  -h, --help          Show help

Environment:
  HOPPER_REF, HOPPER_INSTALL_DIR, HOPPER_GIT_REMOTE, HOPPER_GIT_SUBDIR, HOPPER_RAW_BASE
EOF
}

CONFIGURE=0
REMOVE=0
YES=0
HOST=""
PORT="22"
REF="${HOPPER_REF}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref) REF="$2"; shift 2 ;;
    --dir) HOPPER_INSTALL_DIR="$2"; shift 2 ;;
    --configure) CONFIGURE=1; shift ;;
    --host) HOST="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --remove) REMOVE=1; shift ;;
    -y | --yes) YES=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

export HOPPER_DIR="${HOPPER_INSTALL_DIR}"
mkdir -p "${HOPPER_DIR}"

hopperctl() {
  if [[ -x "${HOPPER_DIR}/hopperctl" ]]; then
    exec "${HOPPER_DIR}/hopperctl" "$@"
  fi
  if [[ -x "${HOPPER_DIR}/.venv/bin/python" ]]; then
    exec "${HOPPER_DIR}/.venv/bin/python" -m hopper.cli "$@"
  fi
  die "hopperctl not available — bootstrap incomplete"
}

if [[ "$REMOVE" -eq 1 ]]; then
  if [[ -x "${HOPPER_DIR}/hopperctl" ]]; then
    args=(remove)
    [[ "$YES" -eq 1 ]] && args+=(-y)
    hopperctl "${args[@]}"
    exit 0
  fi
  die "Nothing to remove at ${HOPPER_DIR}"
fi

ensure_python() {
  command -v python3 >/dev/null 2>&1 && return 0
  log "Installing python3..."
  if [[ "$(id -u)" -ne 0 ]]; then
    die "python3 required. Run as root or install python3-venv manually."
  fi
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-venv python3-pip git curl
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y python3 python3-pip git curl
  elif command -v yum >/dev/null 2>&1; then
    yum install -y python3 python3-pip git curl
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache python3 py3-pip git curl
  else
    die "Cannot install python3 automatically"
  fi
}

ensure_python
command -v git >/dev/null 2>&1 || { log "Installing git..."; ensure_python; }
command -v curl >/dev/null 2>&1 || die "curl required"

# Seed minimal tree when piped from curl (no local checkout yet)
if [[ ! -f "${HOPPER_DIR}/pyproject.toml" ]]; then
  log "Fetching server tree (ref=${REF})..."
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  git clone --depth 1 --branch "${REF}" "${HOPPER_GIT_REMOTE}" "${TMP}/repo" 2>/dev/null \
    || git clone --depth 1 "${HOPPER_GIT_REMOTE}" "${TMP}/repo"
  git -C "${TMP}/repo" checkout "${REF}" 2>/dev/null || git -C "${TMP}/repo" checkout "tags/${REF}" 2>/dev/null || true
  SRC="${TMP}/repo/${HOPPER_GIT_SUBDIR}"
  [[ -d "$SRC" ]] || SRC="${TMP}/repo/server"
  [[ -d "$SRC" ]] || die "server/ not found in checkout"
  shopt -s dotglob nullglob
  for item in "${SRC}"/*; do
    base="$(basename "$item")"
    [[ "$base" == ".repo" || "$base" == ".venv" || "$base" == "dist" ]] && continue
    cp -a "$item" "${HOPPER_DIR}/"
  done
  chmod +x "${HOPPER_DIR}"/*.sh 2>/dev/null || true
  chmod +x "${HOPPER_DIR}/hopperctl" 2>/dev/null || true
fi

export HOPPER_DIR
if [[ -x "${HOPPER_DIR}/hopperctl" ]]; then
  args=(install --ref "${REF}")
  [[ "$CONFIGURE" -eq 1 ]] && args+=(--configure)
  [[ -n "$HOST" ]] && args+=(--host "$HOST")
  [[ -n "$PORT" ]] && args+=(--port "$PORT")
  exec "${HOPPER_DIR}/hopperctl" "${args[@]}"
fi

# First run before hopperctl exists: create venv and install package
python3 -m venv "${HOPPER_DIR}/.venv"
"${HOPPER_DIR}/.venv/bin/pip" install --upgrade pip
"${HOPPER_DIR}/.venv/bin/pip" install -e "${HOPPER_DIR}"
chmod +x "${HOPPER_DIR}/hopperctl" 2>/dev/null || true
args=(install --ref "${REF}")
[[ "$CONFIGURE" -eq 1 ]] && args+=(--configure)
[[ -n "$HOST" ]] && args+=(--host "$HOST")
[[ -n "$PORT" ]] && args+=(--port "$PORT")
exec "${HOPPER_DIR}/.venv/bin/python" -m hopper.cli "${args[@]}"
