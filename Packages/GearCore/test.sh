#!/bin/bash
# Kurzer Testlauf mit knapper Ausgabe (nur Fehler und Zusammenfassung), über Linos Strom-Wrapper.
# Nutzung: Packages/GearCore/test.sh [swift-test-Argumente, z. B. --filter LedgerBuilderTests]
DIR="$(cd "$(dirname "$0")" && pwd)"
SPARSAM="${SPARSAM:-$HOME/Development/orchestrator/tools/sparsam}"
[ -x "$SPARSAM" ] || SPARSAM=""
$SPARSAM swift test --package-path "$DIR" "$@" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -E "error:|✘|Test run with|Suite .* (passed|failed)|Issue recorded" | cut -c1-220 | sort -u | head -60
exit "${PIPESTATUS[0]}"
