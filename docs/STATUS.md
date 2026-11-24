# Status und Übergabe

**Stand:** 24.11.2026 · Quelle der Wahrheit für den Arbeitsstand, bei jeder Änderung mitpflegen.
**Name: Eingelaufen** (Bundle-ID `de.linolaske.eingelaufen`). Internes TestFlight vorbereitet (24.11.): signiertes Archiv baut (`scripts/archive.sh`, Team-ID nur in gitignorierter `.signing.local`), Icon, Privacy Manifest, Export-Compliance (`ITSAppUsesNonExemptEncryption=NO`). **App-Eintrag in App Store Connect fehlt noch: legt Lino an (Frage auf Karte 45F13FE1).** Upload nur über `tools/testflight-upload.sh` nach Freigabe des Brains.

## Entscheidungen von Lino (21.11.2026)
- **E-02:** Deployment Target **iOS 26+** (Swift 6, aktuelle SwiftData/ActivityKit).
- **E-01 (23.11.):** Name **Eingelaufen**, Bundle-ID `de.linolaske.eingelaufen` (Frage 3555E3BC). Recherche: `docs/NAMENSRECHERCHE.md`.
- **E-03 (23.11., Frage BDCE15A9):** „Namen ändern und dann veröffentlichen“. Lesart des Brains: Repo in `eingelaufen` umbenennen, öffentlich, AGPL-3.0-or-later. Reihenfolge und Stand siehe PLAN.md E-03 und Abschnitt „Veröffentlichung“ unten.

## Was steht
| Bereich | Stand |
|---|---|
| Spec | `docs/SPEC.md` v1.0 (Kopie von Linos Datei, SHA-256 `1ed20b01…ab81b4`), unverändert |
| Architektur | `docs/ARCHITEKTUR.md` |
| Plan, Meilensteine M0–M9, Testmatrix, Annahmen, Entscheidungen | `docs/PLAN.md` |
| Apple-Vorgaben geprüft (HealthKit, Hintergrund, Notifications, Live Activities, SwiftData, Privacy) | `docs/PLATTFORM.md` |
| Code | Nur `Packages/GearCore` (namensunabhängig, `Packages/GearCore/test.sh` oder `swift test`): **M1 vollständig im Kern**: M1a (Katalog, HealthKit-Mapping, Vorlagen), M1b (InstallationGraph, LedgerBuilder, UsageQuery, LedgerProjection), M1c (AssignmentEngine, Inbox-Reducer, Korrektur/Regel-Lernen, ImportReconciler, Backup v1 mit Validator, Vorschau und Wiederherstellen). **170 Tests in 10 Suites grün, Zeilenabdeckung 97,0 %** (Stand nach Gegenreview 23.11.) (Ziel ≥ 90 %). T-01…T-14 haben je einen benannten Test. Kern bleibt unverändert die Wahrheit für Rechenlogik. |
| App (M2) | **XcodeGen-Projekt `Eingelaufen`** (`project.yml`, iOS 26, Swift 6, SwiftUI/SwiftData): `SchemaV1` mit 18 Entitäten, `PersistenceActor` als einziger Schreiber, Outbox (at-least-once), Ausrüstung anlegen/umbenennen/einlagern/archivieren, manuelle Aktivität mit Zuordnung, Onboarding (3 Schritte, Health „Später“), 3 Tabs + Einstellungen. **App-Tests 40 in 7 Suiten grün, UI-Tests 10 grün (9 Abläufe + Screenshot-Lauf)**, Screenshots hell/dunkel/XXL in `docs/screenshots/m2/` angesehen. Aufruf: `scripts/test.sh core\|app\|ui`, `scripts/screenshots.sh`. |
| M5 Komponenten und Wartung (24.11.) | **Kern** (`ComponentPlanner`, `QuickAction`/`MaintenanceEntry`, `MaintenanceEvaluator`): 207 Kern-Tests grün, T-02 im Kern und in der Persistenz (rückdatierter Tausch == Neuaufbau). **App**: Befehle im `PersistenceActor` (Komponente anlegen/montieren/ausbauen/umbauen/ersetzen, Wartung, Regeln), 52 App-Tests grün. **UI**: Komponenten-/Wartungsbereich im Detail (7 Schnellaktionen, Regeln, drei getrennte Statusarten, frühere Komponenten), Hinweise (max. 3) auf der Übersicht; `MaintenanceUITests` geschrieben; alle 10 Wartungs-UI-Tests grün, UI-Suite komplett **21 Tests grün** (24.11.). Screenshots hell/dunkel in `docs/screenshots/m5/` angesehen (`scripts/screenshots_m5.sh`). Abnahme durch Lino offen (Review auf der Karte). |
| Board | Todolino-Unterprojekt `1F2204B9-850F-4A39-8A56-7232BE9C754F`, Repo-Schlüssel `local/sportausruestung` |

## M5-Befunde (24.11., behoben)
- Warnfarbe überfällig: rot/orange immer mit Symbol und Text (`DisplayNames.statusStyle`).
- Verschachtelte Komponenten: „Verbaut in“ zeigt den Weg (`InstallationGraph.ancestors`), Nutzung läuft über alle Ebenen (App-Test + UI-Test, Fixture `nested`).
- Einheit der Messgrenze: Text „Einheit wie beim Messwert“.
- Stand: Kern 208, App 56, UI 22 grün; CI grün.

## Nächste Schritte
1. **M1 `GearCore`**: Kern fertig, Abnahme durch Lino steht aus (Board M1/M1a/M1c). Bekannte Grenzen: der Reconciler übernimmt bei Ersatz (P-05) noch keine Segmente (kommt mit M3); Annahme P-09 (ein einziger verfügbarer Kandidat wird automatisch zugeordnet) ist von der Spec nicht gedeckt (6.2/17: automatisch nur explizite Regeln und Presets): `EnginePolicy.autoAssignSoleCandidate` steht seit dem Gegenreview auf **`false`**, der einzige Kandidat wird nur vorgeschlagen; die Option bleibt und wird nur auf Linos ausdrückliche Entscheidung eingeschaltet; Backup enthält kein Ledger (wird nach dem Wiederherstellen neu gebaut), `ImportCursor`/`AppSettings` gehören zur App.
2. ~~M2 App-Fundament~~ erledigt 23.11. (Abnahme durch Lino offen).
3. M3 (mit Gerätespike S-1) steht aus. M5 ist umgesetzt (Abnahme durch Lino offen).
4. M5 offen: Prognose nur Kern-getestet (UI zeigt sie erst mit genug Daten), „Umbauen“/„Ausbauen“ im UI ohne eigenen UI-Test (Kern und Persistenz getestet).

## Wartet auf Lino
- Abnahme M1/M2 durch Lino.
- **E-04** Gerätetests S-1 (nach M3) und S-2 (nach M7).

## Hinweise
- **Lehre M5:** (1) `NavigationLink { GearDetailView(..) }` (Closure-Ziel) innerhalb von `GearDetailView` ließ die App endlos auswerten (`sample`, Zähler: >200k Auswertungen): Navigation zu Gegenständen ist jetzt wertbasiert (`GearRoute`, Ziel am Stack-Wurzel in `RootView`). (2) Die schwebende Tab-Leiste verdeckt den unteren Rand und Listen laden lazy: UI-Tests nutzen `app.reveal`/`tapRevealed`. (3) UI-Läufe dauern ~1–2 Min. je Test (Simulator langsam), einzelne Tests über `scripts/test.sh ui Klasse/Test`.
- Bekannte Grenze M2: Der Outbox-Handler ist bis M3/M4 ein No-op (`NoSideEffects`); der Health-Schritt im Onboarding bietet nur „Später“; UI-Test-Fixtures (`-UITestFixture`) gibt es nur in DEBUG-Builds.
- Simulator: Dunkel/XXL gehen nur systemweit (`xcrun simctl ui … appearance|content_size`), Launch-Argumente wirken nicht; das macht `scripts/screenshots.sh`.
- CI-Workflow `.github/workflows/gearcore.yml` (swift test, macos-latest, nur bei Änderungen in `Packages/GearCore`): seit dem öffentlichen Repo grün (Lauf zu 02993a9, 23.11.). Die App-Tests und UI-Tests laufen nur lokal (Xcode 26/Simulator), nicht in der CI.
- Mac-Platte war am 21.11. rot (22,5 GB frei): Xcode-/Simulator-Arbeit erst bei Platte ≥ Gelb; DerivedData nach `build/`.

## Veröffentlichung (E-03, 23.11.2026)
Prüfung der gesamten Historie vor dem Öffentlichmachen (16 Commits):
- `gitleaks detect` über die Historie: keine Funde.
- `git log -p --all` mit Suche nach Schlüsseln, Tokens, Passwörtern, E-Mail-Adressen, Zertifikaten/Profilen (`.p12`, `.mobileprovision`, `.env`): keine Funde. Alle Commits tragen die GitHub-noreply-Adresse.
- Einziger Treffer: in `scripts/test.sh` und `Packages/GearCore/test.sh` steht der Standardpfad `$HOME/Development/orchestrator/tools/sparsam` (Ressourcenwrapper, per `SPARSAM` überschreibbar). Kein Geheimnis, keine Personendaten; als unkritisch bewertet und im Verlauf belassen.
- Screenshots in `docs/screenshots/m2/` zeigen nur Testdaten der DEBUG-Fixtures.
Vollzogen am 23.11.2026: LICENSE (AGPL-3.0-or-later) und README (2f83edb), zweiter gitleaks-Lauf über 18 Commits ohne Fund, Umbenennung in `MagicalWig34653/eingelaufen` (origin angepasst, lokaler Ordner bleibt `sportausruestung`), Sichtbarkeit **öffentlich**.

