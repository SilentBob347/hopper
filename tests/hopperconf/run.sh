#!/usr/bin/env bash
# Run .hopperconf interop tests: Python reference, Swift CryptoKit, Android HopperConf.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="$ROOT/tests/hopperconf"
ANDROID="$ROOT/app-android"

echo "==> Python reference tests"
if [[ ! -d "$DIR/.venv" ]]; then
  python3 -m venv "$DIR/.venv"
  "$DIR/.venv/bin/pip" install -q -r "$DIR/requirements.txt"
fi
"$DIR/.venv/bin/python" "$DIR/test_hopperconf.py" -v

echo
echo "==> Swift CryptoKit interop (golden vectors)"
swift "$DIR/test_swift_interop.swift"

echo
echo "==> Android HopperConf unit tests"
export JAVA_HOME="${JAVA_HOME:-}"
if [[ -z "$JAVA_HOME" || ! -x "$JAVA_HOME/bin/java" ]]; then
  for candidate in \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
    "$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home"; do
    if [[ -x "$candidate/bin/java" ]]; then
      export JAVA_HOME="$candidate"
      break
    fi
  done
fi
if [[ -z "${JAVA_HOME:-}" || ! -x "$JAVA_HOME/bin/java" ]]; then
  echo "error: set JAVA_HOME to JDK 17+ (or install Android Studio)" >&2
  exit 1
fi
(
  cd "$ANDROID"
  ./gradlew :app:testDebugUnitTest --tests 'com.aengix.hopper.data.HopperConfInteropTest' 
)

echo
echo "All .hopperconf interop tests passed."
