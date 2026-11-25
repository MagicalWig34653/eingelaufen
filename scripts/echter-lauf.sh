#!/bin/bash
# Echter Lauf im Simulator: echter Dateispeicher und echtes HealthKit, ohne Fake-Schalter und ohne Fixtures.
# Ad-hoc-Signatur („-“, kein Team, nichts im Developer-Portal), nur damit der Simulator die HealthKit-Entitlements
# bekommt. Das Hilfsziel HealthSeeder legt das eine Training an; die App selbst schreibt nichts nach Health.
# Nutzung: scripts/echter-lauf.sh   (Simulator „Eingelaufen iPhone“; deinstalliert dort zuerst beide Apps)
# Screenshots mit TEST_RUNNER_SCREENSHOT_DIR=<ordner>.
set -eu
cd "$(dirname "$0")/.."
SPARSAM="${SPARSAM:-$HOME/Development/orchestrator/tools/sparsam}"
[ -x "$SPARSAM" ] || SPARSAM=""
NAME="${EINGELAUFEN_SIM:-Eingelaufen iPhone}"
UDID=$(xcrun simctl list devices | grep "$NAME (" | head -1 | sed 's/.*(\([0-9A-F-]\{36\}\)).*/\1/')
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" >/dev/null
xcrun simctl uninstall "$UDID" de.linolaske.eingelaufen 2>/dev/null || true
xcrun simctl uninstall "$UDID" de.linolaske.eingelaufen.healthseeder 2>/dev/null || true
xcodegen generate --quiet
args=(-project Eingelaufen.xcodeproj -scheme EingelaufenEcht -destination "id=$UDID" -derivedDataPath build/DerivedDataEcht
      CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=)
$SPARSAM xcodebuild build-for-testing "${args[@]}" 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
xcrun simctl install "$UDID" build/DerivedDataEcht/Build/Products/Debug-iphonesimulator/HealthSeeder.app
$SPARSAM xcodebuild test-without-building "${args[@]}" 2>&1
