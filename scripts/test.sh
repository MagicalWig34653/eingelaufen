#!/bin/bash
# Kerntests und App-Tests (Simulator „Eingelaufen iPhone“, selbst anlegen: siehe docs/STATUS.md).
# Nutzung: scripts/test.sh [core|app|ui] [Klasse[/Test] ...]   (Standard: core + app; ui nur die UI-Tests; optional Klassen/Tests, z. B. MaintenanceUITests/testX)
set -eu
cd "$(dirname "$0")/.."
SPARSAM="${SPARSAM:-$HOME/Development/orchestrator/tools/sparsam}"
[ -x "$SPARSAM" ] || SPARSAM=""
DEST="${EINGELAUFEN_DEST:-platform=iOS Simulator,name=Eingelaufen iPhone}"
what="${1:-all}"
if [ "$what" = all ] || [ "$what" = core ]; then
  $SPARSAM swift test --package-path Packages/GearCore
fi
if [ "$what" = all ] || [ "$what" = app ] || [ "$what" = ui ]; then
  xcodegen generate --quiet
  case "$what" in
    ui) only="-only-testing:EingelaufenUITests"; if [ $# -gt 1 ]; then only=""; shift; for t in "$@"; do only="$only -only-testing:EingelaufenUITests/$t"; done; fi ;;
    app) only="-only-testing:EingelaufenTests" ;;
    *) only="" ;;
  esac
  $SPARSAM xcodebuild test -project Eingelaufen.xcodeproj -scheme Eingelaufen \
    -destination "$DEST" -derivedDataPath build/DerivedData -collect-test-diagnostics never $only \
    CODE_SIGNING_ALLOWED=NO 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error:|✘|Test run with|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)|Suite .* (passed|failed)" | cut -c1-220 | sort -u
  exit "${PIPESTATUS[0]}"
fi
