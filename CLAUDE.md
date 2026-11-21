# Sportausrüstung-App (Arbeitstitel GearFlow – Name vorläufig)

Native iOS-App (Swift 6, SwiftUI, SwiftData, HealthKit, ActivityKit, WidgetKit, App Intents, UserNotifications) für Sportausrüstung, Komponenten, Wartung und Verschleiß. Local-first, kein Konto, **kein eigener Server**, kein Cloud-Sync in V1. Sprache: Deutsch.

## Zuerst lesen
1. `docs/STATUS.md` – Stand, nächste Schritte, offene Entscheidungen
2. `docs/PLAN.md` – Meilensteine M0–M9, Testmatrix T-01…T-14, Annahmen P-xx, Entscheidungen E-xx
3. `docs/ARCHITEKTUR.md` – Schichten, Datenmodell, Invarianten I-01…I-10
4. `docs/PLATTFORM.md` – geprüfte Apple-Vorgaben F-01…F-15
5. `docs/SPEC.md` – fachliche Spezifikation (nicht abschwächen)

## Harte Regeln
- **Name und Bundle-ID sind offen.** Keine Bundle-ID erfinden, keine Team-Signierung (registriert App IDs im Developer-Portal), nichts in App Store Connect, keine Veröffentlichung. Bis E-01 nur `swift test` im Paket `Packages/GearCore`.
- Rechenlogik gehört in `GearCore` (keine UI, keine Persistenz, kein HealthKit, keine Systemuhr) und wird test-first geschrieben. Jeder Spec-Pflichttest T-xx hat einen benannten Test.
- Ledger ist abgeleitet, nie Wahrheit. Ein Schreiber (`PersistenceActor`), Seiteneffekte erst nach Commit, HealthKit-Anker im selben Commit wie die Datensätze.
- Fehlende Werte sind `nil`, nie `0`. Keine erfundene Distanz, keine Prozent-Verschleißangaben, Schätzungen kennzeichnen.
- Nie aus leeren HealthKit-Ergebnissen auf Löschung oder verweigerten Zugriff schließen.
- Keine Drittanbieter-Pakete, kein Netzwerk, kein Analytics. Keine Gesundheitswerte in Logs.
- Keine Deploys, kein Codex. Arbeit über Todolino-Karten im Unterprojekt (siehe `.todolino.json`).
