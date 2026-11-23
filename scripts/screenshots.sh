#!/bin/bash
# Screenshots der Kernscreens in hell, dunkel und XXL (systemweit per simctl ui) nach docs/screenshots/m2.
# Nutzung: scripts/screenshots.sh   (Simulator „Eingelaufen iPhone“ muss existieren)
set -eu
cd "$(dirname "$0")/.."
SPARSAM="${SPARSAM:-$HOME/Development/orchestrator/tools/sparsam}"
[ -x "$SPARSAM" ] || SPARSAM=""
NAME="${EINGELAUFEN_SIM:-Eingelaufen iPhone}"
UDID=$(xcrun simctl list devices | grep "$NAME (" | head -1 | sed 's/.*(\([0-9A-F-]\{36\}\)).*/\1/')
xcrun simctl boot "$UDID" 2>/dev/null || true
OUT="$PWD/docs/screenshots/m2"; mkdir -p "$OUT"
xcodegen generate --quiet
run() { # tag appearance content_size
  xcrun simctl ui "$UDID" appearance "$2"; xcrun simctl ui "$UDID" content_size "$3"
  TEST_RUNNER_SCREENSHOT_DIR="$OUT" TEST_RUNNER_SCREENSHOT_TAG="$1" $SPARSAM xcodebuild test \
    -project Eingelaufen.xcodeproj -scheme Eingelaufen -destination "id=$UDID" -derivedDataPath build/DerivedData \
    -only-testing:EingelaufenUITests/ScreenshotUITests CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)"
}
run light light large
run dark dark large
run xxl light extra-extra-large
xcrun simctl ui "$UDID" appearance light; xcrun simctl ui "$UDID" content_size large
