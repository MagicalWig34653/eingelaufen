# Status und Übergabe

**Stand:** 25.11.2026 · Quelle der Wahrheit für den Arbeitsstand, bei jeder Änderung mitpflegen.
**Name: Eingelaufen** (Bundle-ID `de.linolaske.eingelaufen`). Internes TestFlight vorbereitet (24.11.): signiertes Archiv baut (`scripts/archive.sh`, Team-ID nur in gitignorierter `.signing.local`), Icon, Privacy Manifest, Export-Compliance (`ITSAppUsesNonExemptEncryption=NO`). App-Eintrag in App Store Connect angelegt (Lino, SKU eingelaufen-1), interne Gruppe „intern“ nur Lino. Build 1 (0.1.0) archiviert von e932400, Nachweis `runtime/nachweise/eingelaufen-1`; **Hochgeladen 25.11., 17:29** über das Upload-Tor (Freigabe des Brains 17:14): Build 1 `VALID`, nur intern, `usesNonExemptEncryption=false`, „Was testen“ (de-DE) gesetzt, Gruppe „intern“ mit genau einem Tester (Account-Inhaber, eingeladen). Weitere Uploads wieder nur über `tools/testflight-upload.sh` nach Freigabe. **Echter Lauf (25.11.):** `scripts/echter-lauf.sh` (Schema `EingelaufenEcht`, `RealRunUITests`, nie in der normalen Suite) prüft ohne Fake-Schalter echten Dateispeicher (Neustart) und echtes Simulator-HealthKit (Lesedialog inkl. iOS-26-Seite „Wie viele Daten teilen?“, Import 1 Training, Anker, Neustart); das Training legt nur das Test-Hilfsziel `Tools/HealthSeeder` an (ad hoc signiert, kein Team). Grün.

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
| M3 HealthKit-Import (25.11.) | **Software fertig, gegen Fake-Quelle getestet; Gerätespike S-1 offen bei Lino** (`docs/spikes/S-1.md`). **Kern** (`HealthImporter`, `HealthWorkoutSource`/`ImportStore`, Zeitraum, Status, Distanzarten, Segmente und Ersatz nur gleiche Quelle im `ImportReconciler`): T-05…T-08 gegen Fake-Quelle, Completion-Handler in allen Pfaden, 234 Kern-Tests grün (rot 6615691, grün 288b454). **App** (rot 9cd0d5d, grün d3f9bed): HealthKit nur lesen (Trainings + 9 Distanzarten), verankerte Abfrage, Beobachter + Background Delivery, Abgleich bei Start/Vordergrund/Entsperren, Import und Anker in einem Commit, Onboarding Schritt 2 mit Zeitraumwahl (30/90/365/alle), Einstellungen mit Import-Status und „Jetzt abgleichen“, neutrale Texte; 76 App-Tests grün (08e71ab, 87d0622). **UI** (25.11.): komplette Suite **28 Tests grün** auf Stand 87d0622, davon 4 `HealthUITests` gegen die Fake-Quelle (3 davon zuerst rot gegen 9cd0d5d, der vierte vor dem Fix 87d0622). Screenshots hell/dunkel in `docs/screenshots/m3/` angesehen (`scripts/screenshots_m3.sh`). |
| M5 Komponenten und Wartung (24.11.) | **Kern** (`ComponentPlanner`, `QuickAction`/`MaintenanceEntry`, `MaintenanceEvaluator`): 207 Kern-Tests grün, T-02 im Kern und in der Persistenz (rückdatierter Tausch == Neuaufbau). **App**: Befehle im `PersistenceActor` (Komponente anlegen/montieren/ausbauen/umbauen/ersetzen, Wartung, Regeln), 52 App-Tests grün. **UI**: Komponenten-/Wartungsbereich im Detail (7 Schnellaktionen, Regeln, drei getrennte Statusarten, frühere Komponenten), Hinweise (max. 3) auf der Übersicht; `MaintenanceUITests` geschrieben; alle 10 Wartungs-UI-Tests grün, UI-Suite komplett **21 Tests grün** (24.11.). Screenshots hell/dunkel in `docs/screenshots/m5/` angesehen (`scripts/screenshots_m5.sh`). Abnahme durch Lino offen (Review auf der Karte). |
| Board | Todolino-Unterprojekt `1F2204B9-850F-4A39-8A56-7232BE9C754F`, Repo-Schlüssel `local/sportausruestung` |

## M5-Befunde (24.11., behoben)
- Warnfarbe überfällig: rot/orange immer mit Symbol und Text (`DisplayNames.statusStyle`).
- Verschachtelte Komponenten: „Verbaut in“ zeigt den Weg (`InstallationGraph.ancestors`), Nutzung läuft über alle Ebenen (App-Test + UI-Test, Fixture `nested`).
- Einheit der Messgrenze: Text „Einheit wie beim Messwert“.
- Stand: Kern 208, App 56, UI 22 grün; CI grün.

## Nächste Schritte
1. **M1 `GearCore`**: Kern fertig, Abnahme durch Lino steht aus (Board M1/M1a/M1c). Bekannte Grenzen: Annahme P-09 (ein einziger verfügbarer Kandidat wird automatisch zugeordnet) ist von der Spec nicht gedeckt (6.2/17: automatisch nur explizite Regeln und Presets): `EnginePolicy.autoAssignSoleCandidate` steht seit dem Gegenreview auf **`false`**, der einzige Kandidat wird nur vorgeschlagen; die Option bleibt und wird nur auf Linos ausdrückliche Entscheidung eingeschaltet; Backup enthält kein Ledger (wird nach dem Wiederherstellen neu gebaut), `ImportCursor`/`AppSettings` gehören zur App.
2. ~~M2 App-Fundament~~ erledigt 23.11. (Abnahme durch Lino offen).
3. M3: Software fertig (25.11.), **Spike S-1 offen bei Lino** (`docs/spikes/S-1.md`); M3 ist laut DoD erst mit dem Geräteprotokoll abgeschlossen. M5 ist umgesetzt (Abnahme durch Lino offen). Nächster Software-Schritt: M4 (Posteingang, Zuordnung nach Import).
4. M5 offen: Prognose nur Kern-getestet (UI zeigt sie erst mit genug Daten), „Umbauen“/„Ausbauen“ im UI ohne eigenen UI-Test (Kern und Persistenz getestet).

## Wartet auf Lino
- Abnahme M1/M2 durch Lino.
- **E-04** Gerätetests: **S-1 jetzt möglich** (M3-Software fertig, `docs/spikes/S-1.md`), S-2 nach M7.

## Hinweise
- **Lehre M5:** (1) `NavigationLink { GearDetailView(..) }` (Closure-Ziel) innerhalb von `GearDetailView` ließ die App endlos auswerten (`sample`, Zähler: >200k Auswertungen): Navigation zu Gegenständen ist jetzt wertbasiert (`GearRoute`, Ziel am Stack-Wurzel in `RootView`). (2) Die schwebende Tab-Leiste verdeckt den unteren Rand und Listen laden lazy: UI-Tests nutzen `app.reveal`/`tapRevealed`. (3) UI-Läufe dauern ~1–2 Min. je Test (Simulator langsam), einzelne Tests über `scripts/test.sh ui Klasse/Test`.
- Bekannte Grenze M2: Der Outbox-Handler ist bis M4/M6 ein No-op (`NoSideEffects`); UI-Test-Fixtures (`-UITestFixture`) und die Fake-Trainingsquelle (`-UITestHealth workouts|empty|locked|unavailable`) gibt es nur in DEBUG-Builds; mit `-EingelaufenInMemory` wird HealthKit nie angefasst.
- Grenzen M3: (1) Offene Zuordnungen aus dem Import liegen im Datenbestand, haben aber noch keine Oberfläche (Posteingang = M4); bis dahin steht im Verlauf „Ohne Ausrüstung“. (2) Der Voll-Abgleich „Neu synchronisieren“ mit `missingInSourceSince` (ARCHITEKTUR 5.4) und `BGAppRefreshTask` sind nicht gebaut. (3) Das früheste erlaubte Datum bei begrenztem Zugriff (F-04) gibt es erst ab iOS 27 und wird noch nicht angezeigt. (4) Die HealthKit-Anbindung selbst (`HealthKitWorkoutSource`) lief nie gegen echtes HealthKit; nur Lesetypen und Mapper sind getestet. (5) Jeder Abgleich mit Änderungen lädt den ganzen Bestand (Messung in M9).
- Signierung: `project.yml` erzeugt jetzt `App/Eingelaufen.entitlements` (HealthKit, Background Delivery) und `NSHealthShareUsageDescription`. Das nächste signierte Archiv (`scripts/archive.sh`) muss diese Fähigkeiten an der App ID registrieren; ein früher gebautes Archiv enthält M3 nicht.
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

