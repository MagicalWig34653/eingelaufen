# Eingelaufen (Sportausrüstung-App)

Native iOS-App (Swift 6, SwiftUI, SwiftData, HealthKit, ActivityKit, WidgetKit, App Intents, UserNotifications) für Sportausrüstung, Komponenten, Wartung und Verschleiß. Local-first, kein Konto, **kein eigener Server**, kein Cloud-Sync in V1. Sprache: Deutsch.

## Zuerst lesen
1. `docs/STATUS.md` – Stand, nächste Schritte, offene Entscheidungen
2. `docs/PLAN.md` – Meilensteine M0–M9, Testmatrix T-01…T-14, Annahmen P-xx, Entscheidungen E-xx
3. `docs/ARCHITEKTUR.md` – Schichten, Datenmodell, Invarianten I-01…I-10
4. `docs/PLATTFORM.md` – geprüfte Apple-Vorgaben F-01…F-15
5. `docs/SPEC.md` – fachliche Spezifikation (nicht abschwächen)

## Entscheidungen
- Deployment Target **iOS 26+** (E-02, 21.11.). Name **Eingelaufen**, Bundle-ID `de.linolaske.eingelaufen` (E-01, 23.11.). Repo wird laut E-03 (23.11.) in `eingelaufen` umbenannt und öffentlich gemacht (AGPL-3.0-or-later), erst nach Historienprüfung; Sichtbarkeit nur nach dieser Reihenfolge ändern (PLAN.md E-03). Lokaler Ordner bleibt `sportausruestung`.

## Harte Regeln
- **Keine Team-Signierung** (registriert App IDs im Developer-Portal), nichts in App Store Connect, kein TestFlight ohne Lino. Simulator-Builds laufen mit `CODE_SIGNING_ALLOWED=NO`.
- **Bauen/Testen:** `project.yml` ist die Quelle, `Eingelaufen.xcodeproj` ist generiert und ignoriert (`xcodegen generate`). `Packages/GearCore/test.sh` (Kern), `scripts/test.sh app` (App-Tests), `scripts/test.sh ui` (UI-Tests), `scripts/screenshots.sh` (hell/dunkel/XXL nach `docs/screenshots/m2/`). Simulator „Eingelaufen iPhone“, nur ein Gerät. Alles über `~/Development/orchestrator/tools/sparsam`.
- **UI:** Texte im String Catalog (`App/Resources/Localizable.xcstrings`), Accessibility-Identifier für UI-Tests, Schreiben nur über `PersistenceActor`-Befehle (`GearCommand`), Lesen per `@Query`.
- Rechenlogik gehört in `GearCore` (keine UI, keine Persistenz, kein HealthKit, keine Systemuhr) und wird test-first geschrieben. Jeder Spec-Pflichttest T-xx hat einen benannten Test.
- Ledger ist abgeleitet, nie Wahrheit. Ein Schreiber (`PersistenceActor`), Seiteneffekte erst nach Commit, HealthKit-Anker im selben Commit wie die Datensätze.
- Fehlende Werte sind `nil`, nie `0`. Keine erfundene Distanz, keine Prozent-Verschleißangaben, Schätzungen kennzeichnen.
- Nie aus leeren HealthKit-Ergebnissen auf Löschung oder verweigerten Zugriff schließen.
- Keine Drittanbieter-Pakete, kein Netzwerk, kein Analytics. Keine Gesundheitswerte in Logs.
- Keine Deploys, kein Codex. Arbeit über Todolino-Karten im Unterprojekt (siehe `.todolino.json`).
