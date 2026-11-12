#!/usr/bin/env bash
#
# Opt-in macOS GUI smoke for the Screenshot OCR page.
#
# Runs a separately packaged copy of WorkDock with its own bundle identifier and
# a throwaway home directory, then checks that:
#
#   1. exactly one main window is on screen;
#   2. the OCR page renders its screenshot / clipboard / image actions, its
#      editor, and its scroll region;
#   3. the page scrolls when the window is at the smallest size the app allows.
#
# It never starts OCR, never captures the screen, never touches the clipboard,
# and never asks for Accessibility, Screen Recording, or notification
# permission. The installed /Applications/WorkDock.app and the real preferences
# are not involved. A logged-in GUI session is required (a window must exist).
#
# Usage:
#   ./gui-smoke.sh
#   CONFIG=release ./gui-smoke.sh
#   BUILD=0 ./gui-smoke.sh              # reuse the existing build
#   KEEP_SMOKE_HOME=1 ./gui-smoke.sh    # keep the temp home for debugging
#
# Exit status: 0 when every check passes, 1 otherwise. The JSON report and app
# log stay under .build/gui-smoke/ for inspection.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-debug}"
BUILD="${BUILD:-1}"
WAIT_SECONDS="${WAIT_SECONDS:-90}"
BUNDLE_ID="${BUNDLE_ID:-cn.dylanliu.workdock.guismoke.ocr}"

APP_NAME="WorkDockGUISmoke"
OUT_DIR="$ROOT/.build/gui-smoke"
APP="$OUT_DIR/$APP_NAME.app"
REPORT="$OUT_DIR/report.json"
LOG="$OUT_DIR/smoke.log"

# Smallest window the app documents for module pages (MainWindowView).
MIN_WIDTH=360
MIN_HEIGHT=320

# --- Build and package -------------------------------------------------------

if [[ "$BUILD" == "1" ]]; then
  echo "==> building WorkDock ($CONFIG)"
  swift build -c "$CONFIG" --product WorkDock >/dev/null
fi

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/WorkDock"
if [[ ! -x "$BIN" ]]; then
  echo "!! $BIN not found — run without BUILD=0" >&2
  exit 1
fi

echo "==> packaging $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WorkDock"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$APP/Contents/Info.plist" >/dev/null
if [[ -f "$ROOT/logo.png" ]]; then
  cp "$ROOT/logo.png" "$APP/Contents/Resources/logo.png"
fi
if [[ -f "$ROOT/AppIcon.icns" ]]; then
  cp "$ROOT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
cp -R "$ROOT/Sources/WorkDock/Resources/"*.lproj "$APP/Contents/Resources/" 2>/dev/null || true
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "!! ad-hoc codesign failed (continuing)"

# --- Isolated run ------------------------------------------------------------

SMOKE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/workdock-guismoke-home.XXXXXX")"
SMOKE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/workdock-guismoke-tmp.XXXXXX")"
PID=""

cleanup() {
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  if [[ "${KEEP_SMOKE_HOME:-0}" == "1" ]]; then
    echo "==> kept smoke home: $SMOKE_HOME"
  else
    rm -rf "$SMOKE_HOME" "$SMOKE_TMP"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

rm -f "$REPORT"
echo "==> launching the probe (home: $SMOKE_HOME)"
CFFIXED_USER_HOME="$SMOKE_HOME" \
TMPDIR="$SMOKE_TMP" \
WORKDOCK_GUI_SMOKE="ocr-page" \
WORKDOCK_GUI_SMOKE_OUTPUT="$REPORT" \
WORKDOCK_GUI_SMOKE_BUNDLE_ID="$BUNDLE_ID" \
"$APP/Contents/MacOS/WorkDock" >"$LOG" 2>&1 &
PID=$!

deadline=$((SECONDS + WAIT_SECONDS))
while [[ ! -s "$REPORT" ]]; do
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "!! the smoke app exited before writing a report" >&2
    sed -n '1,60p' "$LOG" >&2 || true
    exit 1
  fi
  if (( SECONDS >= deadline )); then
    echo "!! no report after ${WAIT_SECONDS}s" >&2
    sed -n '1,60p' "$LOG" >&2 || true
    exit 1
  fi
  sleep 0.2
done

for _ in $(seq 1 50); do
  kill -0 "$PID" 2>/dev/null || break
  sleep 0.1
done

# --- Validate ----------------------------------------------------------------

raw() { /usr/bin/plutil -extract "$1" raw -o - "$REPORT" 2>/dev/null || true; }
compact_json() { /usr/bin/plutil -extract "$1" json -o - "$REPORT" 2>/dev/null | tr -d '[:space:]' || true; }

failures=()

require_equal() { # key expected label
  local actual
  actual="$(raw "$1")"
  if [[ "$actual" != "$2" ]]; then
    failures+=("$3: expected '$2', got '$actual'")
  fi
}

require_at_least() { # key minimum label
  local actual
  actual="$(raw "$1")"
  if ! awk -v a="$actual" -v b="$2" 'BEGIN { exit !(a >= b) }'; then
    failures+=("$3: expected >= $2, got '$actual'")
  fi
}

require_equal schemaVersion 1 "report schema"
require_equal bundleIdentifier "$BUNDLE_ID" "smoke bundle identifier"
require_equal expectedBundleIdentifier "$BUNDLE_ID" "probe bundle identifier"
require_equal mainWindowCount 1 "single main window"
require_equal userFacingWindowCount 1 "one visible app window (no extra result panel)"
require_equal isScrollable true "page scrolls at the smallest window size"
require_equal ocrPhase idle "OCR stayed idle"

resolved_expected="$(cd "$SMOKE_HOME" && pwd -P)"
resolved_actual="$(cd "$(raw homeDirectory)" 2>/dev/null && pwd -P || true)"
if [[ "$resolved_actual" != "$resolved_expected" ]]; then
  failures+=("home directory: expected '$resolved_expected', got '$resolved_actual'")
fi

require_at_least appliedContentSize.width "$MIN_WIDTH" "smallest window content width"
require_at_least appliedContentSize.height "$MIN_HEIGHT" "smallest window content height"

missing_controls="$(compact_json missingIdentifiers)"
if [[ "$missing_controls" != "[]" ]]; then
  failures+=("OCR page controls missing: $missing_controls")
fi
probe_failures="$(compact_json failures)"
if [[ "$probe_failures" != "[]" ]]; then
  failures+=("probe reported: $probe_failures")
fi

content_height="$(raw contentHeight)"
viewport_height="$(raw viewportHeight)"
if ! awk -v c="$content_height" -v v="$viewport_height" 'BEGIN { exit !(c > v + 1) }'; then
  failures+=("scroll geometry: content '${content_height}pt' does not exceed viewport '${viewport_height}pt'")
fi

# --- Result ------------------------------------------------------------------

if (( ${#failures[@]} > 0 )); then
  echo "FAIL — OCR page smoke found ${#failures[@]} problem(s):"
  printf '  - %s\n' "${failures[@]}"
  echo "  report: $REPORT"
  echo "  log:    $LOG"
  exit 1
fi

echo "PASS — OCR page smoke"
echo "  window:   requested $(raw requestedContentSize.width)×$(raw requestedContentSize.height), content $(raw appliedContentSize.width)×$(raw appliedContentSize.height), 1 main window"
echo "  controls: $(compact_json identifiers)"
echo "  scroll:   content $(raw contentHeight)pt > viewport $(raw viewportHeight)pt"
echo "  OCR:      $(raw ocrPhase) (no capture, no recognition)"
echo "  report:   $REPORT"
