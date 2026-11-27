#!/bin/bash
# Screenshots M6 (Mitteilungen) in hell und dunkel (systemweit per simctl ui) nach docs/screenshots/m6.
# Nutzung: scripts/screenshots_m6.sh   (Simulator „Eingelaufen iPhone“ muss existieren)
set -eu
cd "$(dirname "$0")/.."
SPARSAM="${SPARSAM:-$HOME/Development/orchestrator/tools/sparsam}"
[ -x "$SPARSAM" ] || SPARSAM=""
NAME="${EINGELAUFEN_SIM:-Eingelaufen iPhone}"
UDID=$(xcrun simctl list devices | grep "$NAME (" | head -1 | sed 's/.*(\([0-9A-F-]\{36\}\)).*/\1/')
xcrun simctl boot "$UDID" 2>/dev/null || true
OUT="$PWD/docs/screenshots/m6"; mkdir -p "$OUT"
xcodegen generate --quiet
run() { # tag appearance
  xcrun simctl ui "$UDID" appearance "$2"; xcrun simctl ui "$UDID" content_size large
  TEST_RUNNER_SCREENSHOT_DIR="$OUT" TEST_RUNNER_SCREENSHOT_TAG="$1" $SPARSAM xcodebuild test \
    -project Eingelaufen.xcodeproj -scheme Eingelaufen -destination "id=$UDID" -derivedDataPath build/DerivedData -collect-test-diagnostics never \
    -only-testing:EingelaufenUITests/ScreenshotUITests/testNotificationScreens CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)"
}
run light light
run dark dark
xcrun simctl ui "$UDID" appearance light
# Das Repo ist öffentlich und der Home-Bildschirm zeigt fremde Apps: alles außer Mitteilung und Aktionen weichzeichnen
# (Ausschnitte für 1206×2622, „Eingelaufen iPhone“).
for tag in light dark; do
  f="$OUT/$tag-m6-2-mitteilung-aktionen.png"
  ffmpeg -loglevel error -i "$f" -filter_complex \
    "[0]split=3[a][b][c];[a]gblur=sigma=45[bg];[b]crop=1130:250:38:222[n];[c]crop=764:450:222:505[m];[bg][n]overlay=38:222[x];[x][m]overlay=222:505" \
    -frames:v 1 -y "$f.tmp.png"
  mv "$f.tmp.png" "$f"
done
