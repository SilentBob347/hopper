#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$APP_ROOT/.." && pwd)"
OUT="$REPO_ROOT/screenshots/android"
APK="$APP_ROOT/app/build/outputs/apk/debug/app-debug.apk"
PKG="com.aengix.hopper"

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export PATH="$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH"

mkdir -p "$OUT/phone" "$OUT/tablet-7" "$OUT/tablet-10"

log() { printf '==> %s\n' "$*"; }

wait_for_boot() {
  adb wait-for-device
  until adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' | grep -q 1; do
    sleep 2
  done
  adb shell settings put global window_animation_scale 0
  adb shell settings put global transition_animation_scale 0
  adb shell settings put global animator_duration_scale 0
}

stop_emulator() {
  adb emu kill 2>/dev/null || true
  sleep 3
}

start_emulator() {
  local avd="$1"
  log "Starting emulator: $avd"
  stop_emulator
  nohup emulator -avd "$avd" -no-audio -no-boot-anim -gpu swiftshader_indirect >/tmp/hopper-emulator.log 2>&1 &
  wait_for_boot
}

# Set exact portrait resolution (9:16). Capture matches this size — no post-processing.
set_display() {
  local size="$1"
  local density="$2"
  adb shell wm size reset >/dev/null 2>&1 || true
  adb shell wm density reset >/dev/null 2>&1 || true
  adb shell settings put system user_rotation 0
  adb shell wm size "$size"
  adb shell wm density "$density"
  local actual
  actual="$(adb shell wm size | tr -d '\r' | awk -F': ' '/Override size/{print $2; exit} /Physical size/{print $2}')"
  log "Display: $actual (target $size)"
}

install_apk() {
  log "Installing APK"
  adb install -r "$APK" >/dev/null
}

open_screen() {
  local route="$1"
  local wait_text="$2"
  adb shell am force-stop "$PKG"
  sleep 1
  adb shell am start -S -W -n "$PKG/.MainActivity" --es route "$route" --ez seed_demo true >/dev/null
  wait_for_text "$wait_text"
  sleep 1
}

wait_for_text() {
  local text="$1"
  for _ in $(seq 1 15); do
    if adb shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 \
      && adb shell cat /sdcard/window_dump.xml 2>/dev/null | grep -q "$text"; then
      return 0
    fi
    sleep 1
  done
  log "Warning: timed out waiting for UI text: $text"
  sleep 2
}

capture() {
  local out="$1"
  local expect_w="$2"
  local expect_h="$3"
  adb exec-out screencap -p >"$out"
  local w h
  w="$(sips -g pixelWidth "$out" 2>/dev/null | awk '/pixelWidth/{print $2}')"
  h="$(sips -g pixelHeight "$out" 2>/dev/null | awk '/pixelHeight/{print $2}')"
  if [[ "$w" != "$expect_w" || "$h" != "$expect_h" ]]; then
    log "Warning: $out is ${w}x${h}, expected ${expect_w}x${expect_h}"
  else
    log "Saved $out (${w}x${h})"
  fi
}

capture_set() {
  local form_factor="$1"
  local out_dir="$2"
  local expect_w="$3"
  local expect_h="$4"

  declare -a shots=(
    "01-home:home:Configure chains"
    "02-chains:chains:Server library"
    "03-chain-detail:chain/chain-eu-us:Entry"
    "04-servers:servers:Import"
    "05-server-detail:server/srv-ams-entry:Export"
  )

  for shot in "${shots[@]}"; do
    IFS=':' read -r name route wait_text <<< "$shot"
    log "Capturing $form_factor / $name"
    open_screen "$route" "$wait_text"
    capture "$out_dir/${name}.png" "$expect_w" "$expect_h"
  done
}

build_apk() {
  log "Building debug APK"
  (cd "$APP_ROOT" && ./gradlew assembleDebug -q)
}

main() {
  build_apk

  if [[ "${SKIP_PHONE:-0}" != "1" ]]; then
    log "Phone (1080x1920, 9:16)"
    start_emulator "Medium_Phone"
    set_display 1080x1920 420
    install_apk
    capture_set "phone" "$OUT/phone" 1080 1920
  fi

  if [[ "${SKIP_TABLET_7:-0}" != "1" ]]; then
    log "7-inch tablet (1200x1920, 9:16)"
    start_emulator "Medium_Phone"
    set_display 1200x1920 240
    install_apk
    capture_set "7-inch tablet" "$OUT/tablet-7" 1200 1920
  fi

  if [[ "${SKIP_TABLET_10:-0}" != "1" ]]; then
    log "10-inch tablet (1600x2560, 9:16)"
    start_emulator "Medium_Tablet"
    set_display 1600x2560 320
    install_apk
    capture_set "10-inch tablet" "$OUT/tablet-10" 1600 2560
  fi

  stop_emulator
  log "Done. Screenshots saved under $OUT"
  find "$OUT" -name '*.png' -print
}

main "$@"
