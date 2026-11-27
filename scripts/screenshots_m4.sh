#!/bin/bash
# Screenshots M4 (Posteingang) in hell und dunkel (systemweit per simctl ui) nach docs/screenshots/m4.
# Nutzung: scripts/screenshots_m4.sh   (Simulator „Eingelaufen iPhone“ muss existieren)
set -eu
cd "$(dirname "$0")/.."
SPARSAM="${SPARSAM:-$HOME/Development/orchestrator/tools/sparsam}"
[ -x "$SPARSAM" ] || SPARSAM=""
NAME="${EINGELAUFEN_SIM:-Eingelaufen iPhone}"
UDID=$(xcrun simctl list devices | grep "$NAME (" | head -1 | sed 's/.*(\([0-9A-F-]\{36\}\)).*/\1/')
xcrun simctl boot "$UDID" 2>/dev/null || true
OUT="$PWD/docs/screenshots/m4"; mkdir -p "$OUT"
xcodegen generate --quiet
run() { # tag appearance
  xcrun simctl ui "$UDID" appearance "$2"; xcrun simctl ui "$UDID" content_size large
  TEST_RUNNER_SCREENSHOT_DIR="$OUT" TEST_RUNNER_SCREENSHOT_TAG="$1" $SPARSAM xcodebuild test \
    -project Eingelaufen.xcodeproj -scheme Eingelaufen -destination "id=$UDID" -derivedDataPath build/DerivedData -collect-test-diagnostics never \
    -only-testing:EingelaufenUITests/ScreenshotUITests/testInboxScreens CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)"
}
run light light
run dark dark
xcrun simctl ui "$UDID" appearance light
