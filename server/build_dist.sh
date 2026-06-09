#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="${SCRIPT_DIR}/dist"
mkdir -p "$DIST"

build_one() {
  local name="$1" pkg="$2" arch="$3"
  local out="${DIST}/${name}-linux-${arch}"
  echo "Building ${out} ..."
  (cd "$SCRIPT_DIR" && GOOS=linux GOARCH="$arch" CGO_ENABLED=0 go build -ldflags="-s -w" -o "$out" "./cmd/${pkg}")
  chmod +x "$out"
  if [[ ! -s "$out" ]]; then
    echo "ERROR: empty binary ${out}" >&2
    exit 1
  fi
  file "$out" | grep -q "ELF.*executable" || {
    echo "ERROR: ${out} is not a Linux ELF binary" >&2
    exit 1
  }
  echo "OK: ${out} ($(wc -c <"$out" | tr -d ' ') bytes)"
}

for arch in amd64 arm64; do
  build_one hopperd hopperd "$arch"
done

echo ""
echo "Prebuilt binaries in ${DIST}/"
ls -la "$DIST"
