#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="${SCRIPT_DIR}/dist"
VERSION="$(python3 -c "import json; print(json.load(open('${SCRIPT_DIR}/VERSION.json'))['version'])" 2>/dev/null || echo dev)"
mkdir -p "$DIST"

build_one() {
  local name="$1" pkg="$2" arch="$3"
  local out="${DIST}/${name}-linux-${arch}"
  echo "Building ${out} (version ${VERSION}) ..."
  (cd "$SCRIPT_DIR" && GOOS=linux GOARCH="$arch" CGO_ENABLED=0 \
    go build -ldflags="-s -w -X main.version=${VERSION}" -o "$out" "./cmd/${pkg}")
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
echo "Prebuilt binaries in ${DIST}/ (version ${VERSION})"
ls -la "$DIST"
