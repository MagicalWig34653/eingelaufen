#!/bin/bash
# Signiertes Release-Archiv für internes TestFlight (kein Upload, keine Einreichung).
# Die Team-ID steht NIE im Repo: aus $EINGELAUFEN_TEAM oder der gitignorierten Datei .signing.local (eine Zeile).
# Nutzung: scripts/archive.sh            → build/Eingelaufen.xcarchive
# Upload nur über ~/Development/orchestrator/tools/testflight-upload.sh nach Freigabe des Brains.
set -euo pipefail
cd "$(dirname "$0")/.."
TEAM="${EINGELAUFEN_TEAM:-$(head -1 .signing.local 2>/dev/null || true)}"
[ -n "$TEAM" ] || { echo "Keine Team-ID: EINGELAUFEN_TEAM setzen oder .signing.local anlegen (gitignored)." >&2; exit 2; }
SPARSAM="${SPARSAM:-$HOME/Development/orchestrator/tools/sparsam}"
[ -x "$SPARSAM" ] || SPARSAM=""
xcodegen generate >/dev/null
rm -rf build/Eingelaufen.xcarchive
$SPARSAM xcodebuild archive \
  -project Eingelaufen.xcodeproj -scheme Eingelaufen -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Eingelaufen.xcarchive -derivedDataPath build/DerivedData \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -E "error:|warning: .*(sign|provision)|ARCHIVE (SUCCEEDED|FAILED)" | sort -u | head -40
test -f build/Eingelaufen.xcarchive/Info.plist
