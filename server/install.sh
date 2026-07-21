#!/usr/bin/env bash
# Hopper server bootstrap — pipe from raw.githubusercontent.com or run locally.
set -euo pipefail

HOPPER_REF="${HOPPER_REF:-main}"
HOPPER_INSTALL_DIR="${HOPPER_INSTALL_DIR:-${HOME}/hopper}"
HOPPER_GIT_REMOTE="${HOPPER_GIT_REMOTE:-https://github.com/ZonD80/hopper.git}"
HOPPER_GIT_SUBDIR="${HOPPER_GIT_SUBDIR:-server}"

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
  --skip-sync         Do not pull server tree from git (use files already on disk)
  --skip-binary       Do not download hopperd (use dist/ binary already on disk)
  -y, --yes           Skip confirmation for --remove
  -h, --help          Show help

Environment:
  HOPPER_REF, HOPPER_INSTALL_DIR, HOPPER_GIT_REMOTE, HOPPER_GIT_SUBDIR
EOF
}

CONFIGURE=0
REMOVE=0
YES=0
SKIP_SYNC=0
SKIP_BINARY=0
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
    --skip-sync) SKIP_SYNC=1; shift ;;
    --skip-binary) SKIP_BINARY=1; shift ;;
    -y | --yes) YES=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

case "${HOPPER_INSTALL_DIR}" in
  "~") HOPPER_INSTALL_DIR="${HOME}" ;;
  "~/"*) HOPPER_INSTALL_DIR="${HOME}/${HOPPER_INSTALL_DIR#"~/"}" ;;
esac

export HOPPER_DIR="${HOPPER_INSTALL_DIR}"
export PYTHONPATH="${HOPPER_DIR}${PYTHONPATH:+:$PYTHONPATH}"
mkdir -p "${HOPPER_DIR}"
log "hopper install dir=${HOPPER_DIR} ref=${REF}"

hopperctl() {
  if [[ -x "${HOPPER_DIR}/hopperctl" ]]; then
    exec "${HOPPER_DIR}/hopperctl" "$@"
  fi
  if [[ -x "${HOPPER_DIR}/.venv/bin/python" ]]; then
    exec env PYTHONPATH="${PYTHONPATH}" "${HOPPER_DIR}/.venv/bin/python" -m hopper.cli "$@"
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

python3_venv_works() {
  local testdir
  testdir="$(mktemp -d)"
  if python3 -m venv "$testdir" >/dev/null 2>&1; then
    rm -rf "$testdir"
    return 0
  fi
  rm -rf "$testdir"
  return 1
}

ensure_python() {
  if command -v python3 >/dev/null 2>&1 && python3_venv_works; then
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    log "python3-venv missing — installing..."
  else
    log "Installing python3..."
  fi
  if [[ "$(id -u)" -ne 0 ]]; then
    die "python3 with venv support required. Run as root or install python3-venv manually."
  fi
  local py_ver=""
  py_ver="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-venv python3-pip git curl ca-certificates
    [[ -n "$py_ver" ]] && DEBIAN_FRONTEND=noninteractive apt-get install -y "python${py_ver}-venv" 2>/dev/null || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y python3 python3-pip git curl
  elif command -v yum >/dev/null 2>&1; then
    yum install -y python3 python3-pip git curl
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache python3 py3-pip git curl
  else
    die "Cannot install python3 automatically"
  fi
  python3_venv_works || die "python3 venv still unavailable after package install"
}

checkout_git_ref() {
  local repo="$1" ref="$2"
  if git -C "$repo" checkout "$ref" 2>/dev/null; then
    return 0
  fi
  case "$ref" in
    v* | [0-9]*.[0-9]*)
      git -C "$repo" checkout "tags/${ref}" 2>/dev/null && return 0
      ;;
  esac
  git -C "$repo" fetch origin "$ref" --depth 1 2>/dev/null || true
  git -C "$repo" checkout "$ref" 2>/dev/null && return 0
  return 1
}

copy_tree_item() {
  local src="$1" dest="$2"
  if [[ -d "$src" ]]; then
    mkdir -p "$dest"
    cp -a "${src}/." "${dest}/"
  else
    cp -a "$src" "$dest"
  fi
}

sync_server_tree() {
  local ref="$1"
  local repo_dir="${HOPPER_DIR}/.repo"
  local src subdir="${HOPPER_GIT_SUBDIR}"

  log "git sync: ref=${ref}"
  rm -rf "${repo_dir}"
  log "Cloning ${HOPPER_GIT_REMOTE} (ref ${ref})..."
  if ! git clone --depth 1 --single-branch --branch "${ref}" "${HOPPER_GIT_REMOTE}" "${repo_dir}" 2>&1; then
    log "Branch clone failed — trying shallow clone + checkout ${ref}"
    git clone --depth 1 "${HOPPER_GIT_REMOTE}" "${repo_dir}"
    checkout_git_ref "${repo_dir}" "${ref}" || die "Cannot checkout git ref: ${ref}"
  fi
  git -C "${repo_dir}" sparse-checkout init --cone 2>/dev/null || true
  git -C "${repo_dir}" sparse-checkout set "${subdir}" 2>/dev/null || true

  local head
  head="$(git -C "${repo_dir}" rev-parse --short HEAD 2>/dev/null || true)"
  [[ -n "$head" ]] && log "git sync: at ${head}"

  src="${repo_dir}/${subdir}"
  [[ -d "$src" ]] || src="${repo_dir}/server"
  [[ -d "$src" ]] || die "server/ not found in checkout"

  shopt -s dotglob nullglob
  for item in "${src}"/*; do
    local base
    base="$(basename "$item")"
    [[ "$base" == ".repo" || "$base" == ".venv" || "$base" == "dist" ]] && continue
    copy_tree_item "$item" "${HOPPER_DIR}/${base}"
  done
  chmod +x "${HOPPER_DIR}"/*.sh 2>/dev/null || true
  chmod +x "${HOPPER_DIR}/hopperctl" 2>/dev/null || true
  fix_dist_permissions
  log "git sync: server tree updated"
}

fix_dist_permissions() {
  local dist="${HOPPER_DIR}/dist"
  mkdir -p "$dist"
  chmod 755 "$dist" 2>/dev/null || true
  if [[ "$(id -u)" -eq 0 ]]; then
    chown root:root "$dist" 2>/dev/null || true
  fi
  chmod +x "${dist}"/hopperd-linux-* 2>/dev/null || true
}

ensure_python
command -v git >/dev/null 2>&1 || { log "Installing git..."; ensure_python; }
command -v curl >/dev/null 2>&1 || die "curl required"

if [[ "$SKIP_SYNC" -eq 0 ]]; then
  sync_server_tree "${REF}"
elif [[ ! -f "${HOPPER_DIR}/pyproject.toml" ]]; then
  die "No server tree at ${HOPPER_DIR} — run without --skip-sync first"
fi

clean_legacy_editable() {
  local sp="${HOPPER_DIR}/.venv/lib"
  [[ -d "$sp" ]] || return 0
  find "$sp" -path '*/site-packages/hopper_server*.dist-info' -exec rm -rf {} + 2>/dev/null || true
  find "$sp" -path '*/site-packages/hopper-server*.dist-info' -exec rm -rf {} + 2>/dev/null || true
  find "$sp" -path '*/site-packages/__editable__*hopper*' -delete 2>/dev/null || true
  find "$sp" -path '*/site-packages/hopper_server*.pth' -delete 2>/dev/null || true
}

ensure_venv() {
  if [[ ! -x "${HOPPER_DIR}/.venv/bin/python" ]]; then
    log "Creating Python venv..."
    python3 -m venv "${HOPPER_DIR}/.venv"
    "${HOPPER_DIR}/.venv/bin/pip" install --upgrade pip
    if [[ -f "${HOPPER_DIR}/requirements.txt" ]]; then
      "${HOPPER_DIR}/.venv/bin/pip" install -r "${HOPPER_DIR}/requirements.txt"
    fi
  else
    clean_legacy_editable
  fi
  PYTHONPATH="${HOPPER_DIR}" "${HOPPER_DIR}/.venv/bin/python" -c "import hopper.cli" \
    || die "hopper CLI not importable from ${HOPPER_DIR}"
}

ensure_venv

fix_dist_permissions

args=(install --skip-sync)
[[ "$SKIP_BINARY" -eq 1 ]] && args+=(--skip-binary)
[[ "$CONFIGURE" -eq 1 ]] && args+=(--configure)
[[ -n "$HOST" ]] && args+=(--host "$HOST")
[[ -n "$PORT" ]] && args+=(--port "$PORT")
exec "${HOPPER_DIR}/hopperctl" "${args[@]}"
