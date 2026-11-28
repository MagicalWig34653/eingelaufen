# Architektur (Planungsstand)

**Stand:** 21.11.2026 · Grundlage: `docs/SPEC.md` v1.0 · Plattformfakten: `docs/PLATTFORM.md`
**Name:** „GearFlow“ ist nur Arbeitstitel. Bundle-ID, App-Group, Ordner- und Targetnamen sind **nicht festgelegt** (siehe `docs/PLAN.md`, Entscheidung E-01). Im Text steht `<App>` für den späteren Namen.

Dieses Dokument beschreibt, *wie* die Spec umgesetzt wird. Es schwächt keine Anforderung ab. Wo Apple eine Grenze setzt, steht die Grenze hier mit Beleg in `PLATTFORM.md`, und die Spec-Anforderung wird über den in der Spec selbst vorgesehenen Fallback erfüllt.

---

## 1. Leitentscheidungen

| Nr | Entscheidung | Begründung |
|---|---|---|
| A-01 | **Reiner Domänenkern als Swift Package `GearCore`** (keine UI, keine Persistenz, kein HealthKit, keine Systemuhr; `now` und `TimeZone` werden übergeben). | Spec 10.4 (reine Domain-Services). Alle 14 Pflicht-Unit-Tests laufen mit `swift test` in Sekunden, ohne Simulator. Vorbild CarbStock (`CarbStockCore`). |
| A-02 | **Ledger ist abgeleitet, nie Quelle der Wahrheit.** Quelle der Wahrheit sind: Aktivitäten, Segmente, Zuordnungen, Montagen, Wartungen, Lebenszyklus-Ereignisse. `UsageLedgerEntry` und Summen werden daraus deterministisch erzeugt. | Spec 4.5, 5.2, 13 (Datenkonsistenz). |
| A-03 | **Ein einziger Schreiber:** `PersistenceActor` (`@ModelActor`). Alle Änderungen laufen als fachliche Befehle (`Command`) durch ihn, jeder Befehl ist eine Transaktion inkl. Ledger-Neuberechnung. | Spec 10.4 (actor-sichere Grenze, keine unkontrollierten ModelContext-Zugriffe). Verhindert Doppel-Commits aus Notification, Live Activity und UI gleichzeitig. |
| A-04 | **Seiteneffekte erst nach Commit** (Outbox): Benachrichtigungen planen/entfernen, Live Activity aktualisieren, HealthKit-Anker speichern. | Spec 6.1 Punkt 6 (Anker erst nach persistentem Commit), 7.1 (Posteingang ist Wahrheit). |
| A-05 | **Kein App-Group-Datenbankzugriff in V1.** Die Live-Activity-Oberfläche rendert nur `ContentState`; `LiveActivityIntent.perform()` läuft im App-Prozess (belegt, PLATTFORM F-08) und nutzt den `PersistenceActor`. App Group erst, wenn Home-Screen-Widgets kommen (Spec 16, vertagt). | Spec 10.4 („nur benötigte, kleine App-Group-Daten“), vermeidet konkurrierende Container. |
| A-06 | **Keine Drittanbieter-Pakete.** Testdaten-Generatoren, JSON-Schema-Prüfung usw. selbst im Kern. | Spec 10.2 Dependency Policy. |
| A-07 | **Zeit:** Persistenz als absolute `Date`; Montage-Intervalle halb offen `[startedAt, endedAt)`. Eine Aktivität gehört zu einer Montage, wenn ihr `startAt` im Intervall liegt. Zeitzone nur für Anzeige und Tagesmuster-Regeln. | Spec 4.3, 10.4, 12 (Uhr/Zeitzone). Eindeutige Regel für den Wechsel „gestern vs. heute“. |
| A-08 | **Einheiten:** Meter (`Double`), Sekunden (`Double`), Anzahl (`Int`), Geld in Minor Units (`Int`) + ISO-Währungscode. Fehlende Werte sind `nil`, nie `0`. | Spec 5, 5.2, 13 (sichere Anzeige). |
| A-09 | **XcodeGen** (`project.yml`), `.xcodeproj` nicht einchecken. | Wie CarbStock; Umbenennung nach Namensentscheidung ist eine Zeile. |

---

## 2. Targets und Ordner

```text
<repo>/
├── project.yml                     # XcodeGen (erst ab M2, wenn Name/Bundle-ID stehen)
├── Packages/GearCore/              # SwiftPM, macOS+iOS, swift test (ab M1, namensunabhängig)
│   ├── Sources/GearCore/
│   │   ├── Model/                  # Werttypen: GearItem, Installation, Activity, Segment, Assignment, …
│   │   ├── Catalog/                # SportCatalog, Vorlagen, HK-Mapping-Tabelle (rawValue-basiert)
│   │   ├── Installation/           # InstallationGraph: Validierung, Zeitauflösung
│   │   ├── Usage/                  # LedgerBuilder, UsageQuery (Lebensdauer/seit Einbau/seit Wartung)
│   │   ├── Assignment/             # AssignmentEngine, Rule-Auswertung, Begründung
│   │   ├── Inbox/                  # PendingAssignment-Zustandsmaschine (Reducer)
│   │   ├── Maintenance/            # MaintenanceEvaluator, Intervall/Messwert/Prognose getrennt
│   │   ├── Import/                 # ImportReconciler (Upsert/Löschung/Ersatz/Merge-Vorschlag)
│   │   └── Backup/                 # BackupDocument v1 (Codable), Validator, ImportPlan
│   └── Tests/GearCoreTests/        # T-01…T-14 + Eigenschaftstests
├── App/
│   ├── App/                        # @main, AppDependencies, Navigation (3 Tabs + Einstellungen)
│   ├── Persistence/                # SwiftData @Model, VersionedSchema, MigrationPlan, PersistenceActor, Mapper
│   ├── Integrations/
│   │   ├── HealthKit/              # HealthImportService, HKWorkoutMapper, Autorisierung
│   │   ├── Notifications/          # Kategorien, Planer, Delegate, Ruhezeiten
│   │   └── LiveActivities/         # Controller (start/update/end), Attribute
│   ├── Intents/                    # AppIntents inkl. LiveActivityIntent (in App + Extension kompiliert)
│   ├── Features/                   # Onboarding, Dashboard, Equipment, AssignmentInbox, History, Maintenance, Settings
│   └── Shared/                     # Komponenten, Formatierung („Keine Daten“), Accessibility
├── Widgets/                        # WidgetKit-Extension nur für die Live Activity
├── AppTests/                       # Swift Testing: Persistence, Befehle, Migration, Mapper
├── UITests/                        # XCUITest mit Fixture-Startargumenten
└── docs/
```

Die Spec-Modulaufteilung (10.3) bleibt inhaltlich erhalten; `Domain/` wird zum Paket `GearCore`, damit die Tests ohne App laufen.

---

## 3. Datenmodell

### 3.1 Quelle der Wahrheit vs. abgeleitet

| Art | Entitäten (Spec 5.1) |
|---|---|
| **Wahrheit (vom Nutzer oder Import)** | `GearItem`, `GearStatusChange` *(neu, s. u.)*, `Installation`, `GearPreset`, `GearPresetMember`, `SportProfile`, `ActivityRecord`, `ActivitySegment`, `ActivityGearAssignment`, `MaintenanceEvent`, `MaintenanceRule`, `AssignmentRule`, `AppSettings` |
| **Zustand von Abläufen** | `PendingAssignment`, `ImportCursor`, `NotificationRecord` |
| **Abgeleitet (jederzeit neu erzeugbar)** | `UsageLedgerEntry`, `GearUsageSummary` *(Cache, neu)* |

Ergänzungen gegenüber Spec 5.1 (keine Abschwächung, nur zur Erfüllung nötig):
- **`GearStatusChange` (`gearID`, `status`, `effectiveAt`)**: Spec 6.2 verlangt, Kandidaten abzuwerten, die *im Aktivitätszeitraum* eingelagert/ausgemustert waren. Ein einzelnes Feld `status` kann das historisch nicht beantworten. `GearItem.status` bleibt als aktueller Wert (Cache des letzten Wechsels).
- **`GearUsageSummary`**: denormalisierte Summen je Gegenstand für schnelle Listen (Spec 13 Performance), nie alleinige Wahrheit (Spec 5.1 Hinweis).
- **`ActivityRecord`** zusätzlich: `sourceBundleID?`, `sourceName?`, `isIndoor: Bool?` (nur wenn Metadaten belegt, Spec 3.3), `revision` (für veraltete Notifications), `missingInSourceSince?` (s. 5.4).
- **`PendingAssignment`** zusätzlich: `proposalRevision` (Zähler, s. 6.2).
- **`MaintenanceEvent.affectsKinds`** nicht nötig: `kind` genügt; „seit letzter Wartung des Typs“ filtert nach `kind`.

### 3.2 SwiftData-Regeln

- Stabile `UUID`-IDs als normale Attribute; Beziehungen zwischen Entitäten **über IDs**, nicht über SwiftData-Relationships mit Kaskade (Spec 5.1 Hinweis: komplexe Ableitungen nicht der Kaskade überlassen). Ausnahme erlaubt: rein besitzende 1:n-Beziehungen ohne fachliche Logik (z. B. `GearPreset` → `GearPresetMember`).
- Eindeutigkeit (`sourceID`, Montageregeln, eine aktive Montage) wird im `PersistenceActor` per Abfrage + Kernvalidierung geprüft, nicht nur per `@Attribute(.unique)` (Upsert-Semantik von `.unique` wäre stilles Überschreiben).
- `VersionedSchema` ab dem ersten Commit (`SchemaV1`), `SchemaMigrationPlan` mit einer Testmigration `SchemaV1 → SchemaV1_1` nur im Testziel (Spec 14.2). Vor dem ersten TestFlight-Build darf V1 frei geändert werden; ab dann nur über Migration.
- Speicherort: App-Sandbox (Application Support), Dateischutz `completeUntilFirstUserAuthentication` (Standard), damit Notification-Aktionen und Live-Activity-Intents bei gesperrtem Gerät schreiben können (Beleg und Abwägung: PLATTFORM.md).
- Fotos (`imagePath`) als Dateien unter Application Support/`Media/<gearID>.heic`, im DB-Modell nur relativer Pfad.
- Ein `ModelContainer` pro Prozess; UI liest über `@Query`/Main-Context, schreibt nie direkt.

### 3.3 Invarianten (vom Kern geprüft, vom Actor erzwungen)

| Nr | Invariante | Spec |
|---|---|---|
| I-01 | Je Kind-`GearItem` höchstens eine Montage, deren Intervall einen Zeitpunkt t enthält (keine Überlappung, auch nicht rückdatiert). | 4.3 |
| I-02 | Montagegraph zu jedem Zeitpunkt azyklisch (Prüfung über alle Intervallgrenzen, nicht nur „jetzt“). | 4.3, T-13 |
| I-03 | `endedAt > startedAt`; Montage nicht vor `purchaseDate` (Warnung, nicht Sperre, falls Kaufdatum unbekannt/geschätzt). | 4.3 |
| I-04 | Je (Aktivität, Segment, Gegenstand) höchstens ein Ledger-Eintrag; vererbte und direkte Zuordnung desselben Teils ergeben **einen** Eintrag. | 4.3, 5.2, T-01, T-03 |
| I-05 | Eine Aktivität mit Segmenten wird auf Segmentebene zugeordnet *oder* auf Aktivitätsebene, nicht beides für denselben Gegenstand. | 5.2 (Annahme P-02) |
| I-06 | `distanceMeters == nil` bleibt `nil` in Ledger und Summe; Summe über Teilmengen mit `nil` zeigt „x km (unvollständig)“ statt still weniger. | 5.2, T-08, T-09 |
| I-07 | Je `HKWorkout.uuid` genau ein `ActivityRecord`. | 5.2, 12, T-05 |
| I-08 | Gelöschte Aktivität (`deletedAt != nil`) erzeugt keine Ledger-Einträge; ihr Posteingangseintrag ist `obsolete`. | 11, 12, T-07 |
| I-09 | `PendingAssignment`-Übergänge nur gemäß Zustandsmaschine; Endzustände (`resolved`, `dismissed`, `obsolete`) sind gegen erneute Aktion idempotent. | 7.1, T-10 |
| I-10 | Ledger aus inkrementeller Aktualisierung == Ledger aus vollständigem Neuaufbau (Eigenschaftstest). | 13 |

---

## 4. Nutzungsberechnung (UsageCalculator / LedgerBuilder)

**Eingaben:** Aktivitäten (+Segmente), direkte Zuordnungen, Montagen, Lebenszyklus-Historie. **Ausgabe:** Ledger-Einträge.

Algorithmus je Aktivität `a` (bzw. Segment `s`) mit Zeitpunkt `t = startAt`:
1. Menge `D` = direkt zugeordnete Gegenstände (inkl. aus Preset expandierter Mitglieder, die als einzelne Zuordnungen gespeichert sind).
2. Für jeden `g ∈ D`: alle Nachfahren von `g` im Montagegraphen zum Zeitpunkt `t` hinzufügen (transitiv, z. B. Fahrrad → Laufrad → Reifen).
3. Menge deduplizieren (I-04) → je Gegenstand ein Eintrag mit `distanceMeters` (nur wenn gemessen; Segment: nur Segmentdistanz, sonst `nil`, keine Verteilung nach Dauer), `durationSeconds`, `uses = 1`, `derivationVersion`.
4. Keine Vererbung zwischen unabhängigen Gegenständen (Fahrrad ⇒ Helm nie automatisch, Spec 5.2).

**Abfragen (`UsageQuery`):**
- *Lebensdauer:* Summe aller Einträge des Gegenstands.
- *Seit Einbau:* Summe der Einträge mit `t ≥ startedAt` der **aktuellen** Montage; nicht montiert → „nicht verbaut“ (kein Wert).
- *Seit letzter Wartung (kind):* Summe der Einträge mit `t > performedAt` des letzten Ereignisses dieser Art. Wartung setzt nur diesen Wert zurück (T-11).
- *Kalenderalter:* ab `purchaseDate`, sonst ab erster Montage/Nutzung, gekennzeichnet.
- Jede Metrik liefert `Measured(value, isComplete)`, `NoData` oder `Estimate(…)` – die UI kann „0 km“ nur zeigen, wenn wirklich 0 gemessen wurde.

**Neuberechnung:** V1 baut nach jedem Befehl das Ledger **der betroffenen Gegenstände** neu (Gegenstand + Vorfahren/Nachfahren über alle betroffenen Zeitfenster); als Sicherheitsnetz gibt es `rebuildAll()` (Einstellungen > Daten prüfen, nach Migration, nach Backup-Import). Ziel aus Spec 13: 10.000 Aktivitäten, 1.000 Wartungen ohne spürbare Blockierung → `rebuildAll()` läuft im Actor, nie auf dem Main-Thread; Performance-Test in M9 legt Grenzwerte fest (Vorschlag: < 2 s auf iPhone 15-Klasse für `rebuildAll`, < 100 ms für einen Einzelbefehl).

---

## 5. HealthKit-Import

### 5.1 Komponenten
- `HealthWorkoutSource` (Protokoll): `requestAuthorization`, `fetchChanges(anchor) -> (added: [WorkoutDTO], deleted: [UUID], newAnchor)`, `observe(handler)`. Echte Implementierung mit `HKAnchoredObjectQuery`/`HKObserverQuery`; Fake für Tests.
- `HKWorkoutMapper`: `HKWorkout` → `WorkoutDTO` (UUID, Typ-rawValue, Start/Ende, Dauer, Distanz über `statistics(for:)` mit dem Distanztyp der Sportart – `totalDistance` ist deprecated, PLATTFORM F-06 –, Indoor nur wenn `HKMetadataKeyIndoorWorkout` gesetzt, `workoutActivities` als Segmente, Quelle aus `HKSourceRevision`).
- `ImportReconciler` (Kern, rein): bekannte Datensätze + Batch → Operationen `insert / update / tombstone / proposeMerge / carryOver`.
- `HealthImportService` (App): steuert Abfragen, ruft `PersistenceActor.apply(importBatch:)` und speichert den Anker **im selben Commit** wie die Datensätze (`ImportCursor`), danach Engine-Lauf und Outbox.

### 5.2 Auslöser
1. Onboarding/Einstellungen: Erstimport für gewählten Zeitraum (Vorgabe 90 Tage, Option „alle“).
2. `HKObserverQuery` mit Background Delivery für den Workout-Typ, Registrierung bei **jedem** App-Start in `didFinishLaunching` (App-Delegate-Adapter), `enableBackgroundDelivery` bei jedem Start erneut; im Handler Anchored Query, Commit, dann Completion-Handler – **in jedem Pfad, auch bei Fehler**, sonst schaltet HealthKit nach drei Fehlschlägen ab (PLATTFORM F-02).
3. Jeder App-Start und Wechsel in den Vordergrund: Anchored Query (Konsistenzabgleich, Spec 6.1 Punkt 5).
4. Gerät war gesperrt / Health-Datenbank nicht verfügbar: Fehler wird nicht verschluckt, sondern als „Import ausstehend“ gemerkt; erneuter Versuch bei `protectedDataDidBecomeAvailable` und beim nächsten Vordergrund.
5. Optional `BGAppRefreshTask` als zusätzlicher, nicht garantierter Anstoß.

### 5.3 Idempotenz und Absturzsicherheit
- Gleicher Batch zweimal → keine Änderung (T-05). Absturz vor Commit → Anker unverändert → Batch kommt erneut → Reconciler erkennt bestehende UUIDs.
- Änderungen an einem Workout: Liefert HealthKit dieselbe UUID mit neuen Werten, wird aktualisiert (T-06). Bildet die Quelle eine Änderung als *Löschen + Neuanlage* ab (übliches HealthKit-Verhalten, s. PLATTFORM.md), schlägt der Reconciler „Übernahme der Zuordnung“ nur bei sehr starker eindeutiger Übereinstimmung automatisch vor (gleiche Quelle, gleicher Typ, Start/Ende nahezu identisch, im selben Batch, genau ein Kandidat); sonst Posteingang mit Hinweis. Spec 5.2: nie nur wegen Zeitüberschneidung zusammenführen.
- Überlappende Aktivitäten verschiedener Quellen bleiben getrennt; Zusammenführen nur als Nutzeroption (Spec 5.2, 6.4).

### 5.4 Löschungen und fehlende Berechtigung
- Gelöscht wird **nur** auf Grund eines `HKDeletedObject` (oder Nutzeraktion). Ein leeres Abfrageergebnis bedeutet nicht „gelöscht“ und nicht „Zugriff verweigert“ (Spec 6.1 Punkt 7, 11).
- Der optionale Voll-Abgleich (Einstellungen > Neu synchronisieren) markiert nicht mehr auffindbare Workouts nur als `missingInSourceSince` und zeigt sie zur Prüfung; keine automatische Löschung, keine Diagnose „Zugriff verweigert“.
- Löschen einer Aktivität entfernt Ledger-Beiträge, nie das Ausrüstungsobjekt (Spec 11). Vom Nutzer gelöschte Health-Aktivitäten (`removedByUser`) hebt kein späterer Import auf.

---

## 6. Zuordnung, Posteingang, Benachrichtigung, Live Activity

### 6.1 AssignmentEngine (Kern)
Eingabe: Aktivität, Kandidaten (aktive Ausrüstung, Status-Historie, Montagen), Presets, Regeln, Zusammenfassung früherer bestätigter Zuordnungen, Zeitzone. Ausgabe:
```swift
enum AssignmentDecision {
  case autoAssign(gear: [UUID], reason: Reason, confidence: Confidence) // nur .explicit oder regelbasiert eindeutig
  case propose(primary: [UUID], alternatives: [[UUID]], reason: Reason, confidence: Confidence)
  case choose(candidates: [UUID], reason: Reason)   // mehrere gleich plausibel, keine Empfehlung erzwingen
  case noGear                                        // „Ohne Ausrüstung“, keine Benachrichtigung
}
```
Reihenfolge exakt nach Spec 6.2; Konfidenz-Enum `explicit/high/medium/low/none`, keine Prozentzahl. Eingelagerte/ausgemusterte/noch nicht gekaufte Gegenstände (laut `GearStatusChange` zum Zeitpunkt `t`) werden nie automatisch gewählt (T-12). Regeln wirken nur auf neue Importe, nie still auf abgeschlossene Aktivitäten (Spec 6.3).

### 6.2 Posteingang (Wahrheit) und Anzeigen
- Zustandsmaschine als Reducer im Kern: `unresolved → suggested → resolved`, dazu `dismissed`, `ignored`, `obsolete`.
- Jede Änderung am Vorschlag erhöht `proposalRevision`. Notification-`userInfo` und Live-Activity-Buttons tragen `(pendingID, proposalRevision)`. Bei Ausführung lädt der Actor den Eintrag neu: anderer Revisionsstand oder Endzustand → keine Buchung, Anzeige wird aktualisiert/entfernt, ggf. Posteingang öffnen (Spec 7.2, 12, T-10).
- Benachrichtigungen: stabiler Identifier je Pending (ersetzen statt stapeln), ab 2 offenen eine Sammelmeldung, Ruhezeiten → Zustellung zum Ende der Ruhezeit, Stufen `aus / nur Zuordnung / Zuordnung + Wartung`, Erstanfrage der Berechtigung erst kontextbezogen (erste offene Zuordnung oder erste Wartungsregel).
- Notification-Aktionen in dieser Reihenfolge, weil bei wenig Platz nur zwei sichtbar sind (PLATTFORM F-10): „Vorschlag übernehmen“ (Hintergrund, ohne Entsperren, P-06), „Andere auswählen“ (`.foreground`, Deep Link), „Später“.
- Live Activity: höchstens **eine** Aktivität „Offene Zuordnungen“. Start nur im Vordergrund oder per `LiveActivityIntent` (PLATTFORM F-07); ein Start direkt aus dem HealthKit-Hintergrundweckruf ist ohne APNs nicht vorgesehen; Updates/Ende nach jedem Commit, der den Posteingang ändert; Ablauf lässt den Posteingang unberührt. Inhalt: Sportsymbol, Anzahl, jüngste Aktivität mit Dauer/Distanz, ≤ 2 Kandidaten-Buttons, „Weitere“ (Deep Link). Keine Route, kein Ort, keine Gesundheitswerte außer Dauer/Distanz.
- Fallback ist Normalfall: Kein Ablauf hängt von Notification-Berechtigung oder Live Activity ab (Spec 7.3).

---

## 7. Datensicherung (Spec 11, T-14)
- `BackupDocument` v1: `formatVersion`, `appSchemaVersion`, `exportedAt`, alle Wahrheits-Entitäten (nicht das Ledger, es wird nach Import neu gebaut), optional Fotos als `media`-Liste (relativer Pfad + Base64) in derselben `.json`-Datei; kein ZIP (M8).
- Import: Validierung (Version, Referenzen, Invarianten I-01…I-09) → Vorschau (Anzahl je Typ, Konflikte) → Modus „Ersetzen“ oder „Zusammenführen nach ID“ → bei „Ersetzen“ und vorhandenem eigenem Bestand eine Rückfrage → ein Commit (Ledger neu, Health-Anker verworfen) → Fotos schreiben und aufräumen.
- Export-Hinweis „unverschlüsselt, enthält Trainingsdaten“. HealthKit-abgeleitete Daten verlassen das Gerät nur durch ausdrückliche Nutzeraktion.

---

## 8. Fehler sichtbar machen
- `OSLog` mit Kategorien (`import`, `assignment`, `ledger`, `notify`, `liveactivity`, `backup`), keine Gesundheitswerte im Log in Release-Builds (`privacy: .private`).
- Einstellungen > „Import-Status“: letzter erfolgreicher Abgleich, letzter Fehler in Klartext, ausstehende Wiederholung. Keine verschluckten Importfehler (Spec 10.4).
