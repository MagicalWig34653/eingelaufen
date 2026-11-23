# Eingelaufen

Native iOS-App (Swift 6, SwiftUI, SwiftData) für Sportausrüstung: wie viel wurde was genutzt, wann ist Wartung fällig. Local-first, kein Konto, kein eigener Server. Sprache: Deutsch.

Stand und Plan: `docs/STATUS.md`, `docs/PLAN.md`. Der Rechenkern liegt als Swift-Paket in `Packages/GearCore`.

## Bauen

```
brew install xcodegen
xcodegen generate
scripts/test.sh core   # GearCore
scripts/test.sh app    # App-Tests
scripts/test.sh ui     # UI-Tests (Simulator)
```

## Lizenz

AGPL-3.0-or-later, siehe `LICENSE`.
