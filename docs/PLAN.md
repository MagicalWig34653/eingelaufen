# Umsetzungsplan (Planungsstand)

**Stand:** 21.11.2026 · Spec `docs/SPEC.md` v1.0 (unverändert übernommen) · Architektur `docs/ARCHITEKTUR.md` · Apple-Vorgaben `docs/PLATTFORM.md`
**Arbeitstitel:** GearFlow, ausdrücklich **vorläufig**. Kein Produktname, keine Bundle-ID, kein App-Store-Connect-Eintrag festgelegt.
**Todolino:** Unterprojekt „GearFlow (Arbeitstitel – Name vorläufig)“ unter Vibecoding, `1F2204B9-850F-4A39-8A56-7232BE9C754F`, Repo-Schlüssel `local/sportausruestung`.

---

## 1. Umfang V1 (aus der Spec, ohne Abstriche)

V1 ist erst fertig, wenn der MVP-Satz aus Spec 19 vollständig gilt: beliebige Sportausrüstung aller 12 Kategorien schnell anlegen, Apple-Health-Aktivitäten ohne Handarbeit importieren, passende Gegenstände **einschließlich verbauter Komponenten** automatisch belasten, unklare Fälle bequem bestätigen, Wartungen und Wechsel historisch korrekt erfassen, vollständig offline, ohne Konto oder Backend.

Nicht in V1 (Spec 0.2, 16): Cloud-Sync, Watch-App, Home-Screen-Widgets, Strava/Garmin-API, ML, Barcode/Foto-Erkennung, Abo.

Die Plattformgrenzen (keine Echtzeitgarantie für Hintergrundimport, Live-Activity-Startkontexte, Anzahl Notification-Aktionen) stehen schon in der Spec selbst und werden **nicht** als Abschwächung behandelt: Die Spec verlangt dafür den Fallback (Posteingang + lokale Benachrichtigung), und dieser wird als vollwertiger Hauptweg gebaut und getestet.

---

## 2. Zuständigkeiten

| Rolle | Wer | Zuständig für |
|---|---|---|
| Produktentscheidungen | **Lino** | Name, Bundle-ID, App-Store-Connect, Veröffentlichung, Repo-Sichtbarkeit/Lizenz, Gerätetests auf eigenem iPhone, alles mit Außenwirkung |
| Steuerung | **Brain** (Orchestrator) | Session starten, Budget, Reihenfolge, Fragen bündeln, Merges nach `main` gemäß Brain-Regeln |
| Projektleitung | Projekt-Hauptsession (Sonnet; Opus nur für Architektur-Reviews, M3/M7-Spikes) | zerlegt Meilensteine, startet Worker, prüft, hält `docs/STATUS.md` aktuell |
| Worker | Sonnet-Agenten, je Karte ein Worktree | Implementierung test-first, keine Merges |
| Prüfung | Verifier-Agent (Sonnet) | Tests, Simulator-Screenshots hell/dunkel/große Schrift, Diff gegen Invarianten |

Kein Codex (Auftrag). Keine Deploys, keine App-Store-Einreichung, keine Nachricht an Apple durch Agenten. TestFlight erst, wenn Lino Name/Bundle-ID und ASC-Eintrag freigegeben hat; dann gelten die üblichen TestFlight-Regeln des Brains (nur interne Gruppe).

---

## 3. Meilensteine

Abhängigkeiten in Klammern. „Namensunabhängig“ heißt: kann vor E-01 starten, ohne Bundle-ID, Xcode-Projekt oder Signierung.

### M0 Entscheidungen und Projektstart
- E-01 Name + Bundle-ID (Lino), E-02 Deployment Target, E-03 Repo/Lizenz (siehe Abschnitt 6).
- Danach: Ordner ggf. umbenennen, `CLAUDE.md`, `project.yml` mit endgültigen Bezeichnern.
- **DoD:** E-01…E-03 beantwortet und in `docs/STATUS.md` eingetragen.

### M1 Domänenkern `GearCore` (namensunabhängig, sofort startbar)
- Werttypen aller Wahrheits-Entitäten, `SportCatalog` mit **allen 12 Kategorien**, Unterkategorien, Kurzvorlagen je Sportart, Fahrrad-Komponentenvorlagen (Kette, Kassette, Laufradsatz, Reifen, Bremsbeläge …) mit als „Startwert“ gekennzeichneten, editierbaren Intervallen.
- HK-Mapping-Tabelle `HKWorkoutActivityType.rawValue → SportCategory/Subtype` vollständig; unbekannte Typen → „Sonstige“.
- `InstallationGraph` (I-01…I-03), `LedgerBuilder` + `UsageQuery` (I-04, I-06, I-10), `ImportReconciler` (I-07, I-08), Inbox-Reducer (I-09), `AssignmentEngine`, `MaintenanceEvaluator`, `BackupDocument` + Validator.
- Tests: T-01…T-14 auf Kernebene (siehe Abschnitt 4), Eigenschaftstest „inkrementell == Neuaufbau“ mit festem Seed.
- Parallelisierbar in 3 Worker-Karten: (a) Katalog+Mapping, (b) Montage+Ledger+Usage, (c) Engine+Inbox+Reconciler+Backup. (b) zuerst, weil (c) darauf aufbaut.
- **DoD:** `swift test` grün, jede Spec-Pflicht-ID T-xx hat mindestens einen benannten Test, Abdeckung des Kerns ≥ 90 % Zeilen.

### M2 App-Fundament (M0, M1)
- XcodeGen-Projekt, 3 Tabs + Einstellungen-Button, Design-Tokens, Dynamic Type/Dark Mode von Anfang an.
- `SchemaV1` vollständig für **alle** Entitäten (damit M3–M8 parallel ohne Schemakonflikt arbeiten), `PersistenceActor`, Befehlsschicht, Outbox, Mapper Kern↔SwiftData.
- Ausrüstung anlegen (Vorlage → Name → Speichern), bearbeiten, Lebenszyklus, Archiv; leerer Zustand ohne Statistiken (Spec 1.3); Onboarding-Gerüst (3 Schritte, Health-Schritt zunächst „Später“).
- Manuelle Aktivität anlegen inkl. Zuordnung (Spec 6.4) – macht die App ohne HealthKit nutzbar.
- **DoD (= Spec Phase 0):** komplette Ausrüstung lokal anlegen/archivieren, mehrere Sportarten nutzbar, App-Tests + erste UI-Tests grün, Screenshots hell/dunkel/XXL geprüft.

### M3 HealthKit-Import (M2) – Spike zuerst
- **Spike S-1 (Gerät, Lino):** Background Delivery für Workouts auf echtem iPhone: Zustellung nach Workout-Ende, bei gesperrtem Gerät, nach Kill, nach Neustart; Messprotokoll in `docs/spikes/`.
- Autorisierung (nur lesen, nur nötige Typen), Onboarding-Schritt 2 mit Zeitraumwahl, Erstimport, Observer + Background Delivery, Anchored Query, Vordergrund-Abgleich, Gesperrt-Fall, Löschungen, Ersatz-Erkennung, Import-Status in Einstellungen, neutrale Texte ohne Fehldiagnose.
- **DoD:** T-05…T-08 gegen Fake-Quelle grün; Integrationsliste 14.2 „Observer + anchored requery; mehrfaches Resume und Kill/Launch“ auf Gerät protokolliert.

### M4 Zuordnung und Posteingang (M2, M3 für Echtdaten; Engine aus M1)
- Engine-Anbindung nach Import, Presets, `AssignmentRule` inkl. „Für ähnliche Aktivitäten merken“, Regelansicht in Einstellungen.
- Posteingang S05 (Vorschlag bestätigen, Ändern, Multi-Select in einem Dialog, „Nicht zuordnen“), Korrektur aus Verlauf (US-07), Übersicht S02 mit offenen Zuordnungen.
- **DoD (= Spec Phase 1):** neues Training wird automatisch zugeordnet oder reproduzierbar vorgelegt; keine doppelten Nutzungsbeiträge; UI-Tests „zwei Fahrräder, eine offene Aktivität, ein Tap“ und „Fahrrad + Helm + Schuhe“ grün.

### M5 Komponenten und Wartung (M2; parallel zu M3/M4)
- Komponenten hinzufügen mit Starter-Vorlagen, montieren/ausbauen/umbauen/ersetzen (Spec 4.4), Historie bleibt aufrufbar, rückdatierter Umbau.
- Wartung S07: Schnellaktionsleiste (alle 7 Typen), sofort speichern, optional Datum/Messwert/Kosten/Notiz; „Ausrüstung gewartet“ ohne Komponente.
- `MaintenanceRule` je Gegenstand (Distanz, Dauer, Anzahl, Kalender, Messgrenze, optional „frühester Wert“), drei getrennte Statusarten (Intervall / Messwert / Prognose mit Kennzeichnung „Schätzung“), max. 3 Hinweise auf der Übersicht.
- **DoD (= Spec Phase 2):** Kettenwechsel historisch konsistent (T-02), Wartung in ≤ 3 Aktionen ab Detail (Spec 13, als UI-Test gezählt), UI-Test „Komponente tauschen, alte Historie aufrufen“.

### M6 Lokale Benachrichtigungen (M4, M5)
- Kategorien/Aktionen („Vorschlag übernehmen“, „Andere auswählen“, „Später“; bei Mehrdeutigkeit „Ausrüstung wählen“), Ausführung idempotent über `(pendingID, proposalRevision)`, Bündelung, Ruhezeiten, Stufen, kontextbezogene Berechtigungsanfrage.
- Wartungserinnerungen nur für aktivierte Regeln, Cooldown 7 Tage, Text „Prüfen“, Deep Link zur Wartung.
- **DoD:** T-10 im Kern und im App-Test (doppelte Aktion, veraltete Aktion nach Bearbeitung); App ohne Berechtigung vollständig bedienbar (UI-Test).

### M7 Live Activity (M6) – Spike zuerst
- **Spike S-2 (Gerät):** zulässige Startkontexte und Hintergrund-Updates gemäß PLATTFORM.md praktisch prüfen, auf Ziel-iOS-Version.
- Widget-Extension (nur Live Activity), `ActivityAttributes`, kompakte/erweiterte/Sperrbildschirm-Darstellung, `LiveActivityIntent`-Buttons für ≤ 2 Kandidaten, Start/Update/Ende-Controller nach Commit, Fallback-Nachweis.
- **DoD (= Spec Phase 3):** Benachrichtigungsfreigabe optional, offene Zuordnungen gehen nie verloren, wiederholte Aktionen sicher; Integrationsliste 14.2 „Live Activity: Vordergrundstart, erlaubter Intent-Start, Ablauf, Fehlerfallback und Auflösung“ protokolliert.

### M8 Datensicherung und Löschen (M4, M5)
- Export (JSON v1, optional ZIP mit Fotos) über FileExporter/Share Sheet mit Hinweis, Import mit Validierung, Vorschau, Konfliktbehandlung; „Alle App-Daten löschen“; einzelne Aktivitäten/Ausrüstung löschen.
- **DoD:** T-14 (Kern + App-Rundreise mit Fotos), Migrationstest SchemaV1 → Testschema grün.

### M9 Produktreife (alle)
- Verlauf S06 (Timeline, Filter Sport/Zeitraum/Ausrüstung/Ereignistyp, Aggregation), Kostenansicht (Kosten/km nur mit Distanz).
- Lokalisierung de-DE + en-US vollständig (String Catalog), Accessibility-Audit (`performAccessibilityAudit`) aller Kernscreens, VoiceOver-Durchgang manuell, Performance-Tests 10.000 Aktivitäten/1.000 Wartungen mit festgelegten Grenzwerten.
- Privacy Manifest, Texte für HealthKit-Begründung, Vorbereitung App-Privacy-Angaben und Review-Notizen (nur als Dokument; Eintragen macht Lino).
- **DoD (= Spec Phase 4):** offline durchgängig, Datenwiederherstellung geprüft, alle Kernflows automatisiert getestet, keine Netzwerk-/Backend-Abhängigkeit (Test: Build ohne Netzwerk-Entitlement-Nutzung, keine `URLSession` außerhalb Debug).

### Gerätetest-Runde G (Lino, nach M4, M7, M9)
- Echte Workouts (Apple Watch/iPhone, ggf. Drittquelle, die nach Health schreibt), Sperrbildschirm, Ruhezeiten, Live Activity. Spec 14.2: Simulator nicht alleinige Validierung.

**Reihenfolge kritischer Pfad:** M0 → M1 → M2 → M3 → M4 → M6 → M7 → M9. M5 und M8 laufen parallel dazu.

---

## 4. Testmatrix (Spec 14 vollständig)

| Spec | Inhalt | Ebene | Meilenstein |
|---|---|---|---|
| T-01 | Training + Fahrrad + montierte Kette → je genau einmal | Kern | M1 |
| T-02 | Kettenwechsel im Zeitraum: vorher alte, nachher neue Kette | Kern + UI | M1, M5 |
| T-03 | Direkte + vererbte Kette → keine Doppelzählung | Kern | M1 |
| T-04 | Korrektur A → B: A sinkt, B steigt | Kern + App | M1, M4 |
| T-05 | Idempotenter Import gleiche UUID | Kern + App (Fake-Quelle) | M1, M3 |
| T-06 | Geändertes Training aktualisiert Dauer/Distanz (gleiche UUID und Ersatz-Fall) | Kern + App | M1, M3 |
| T-07 | Gelöschtes Training entfernt Ledger-Einträge, schließt Posteingang | Kern + App | M1, M3 |
| T-08 | Multisport ohne Segmentdistanz → keine erfundene Distanz | Kern | M1 |
| T-09 | `nil` bleibt `nil`, Anzeige „Keine Daten“ | Kern + UI-Snapshot | M1, M2 |
| T-10 | Wiederholte Notification-Aktion wirkt höchstens einmal | Kern + App | M1, M6 |
| T-11 | Wartung setzt nur „seit Wartung“ zurück | Kern | M1 |
| T-12 | Eingelagerter Gegenstand nicht automatisch | Kern | M1 |
| T-13 | Montagekreise / überlappende Montagen verhindert | Kern | M1 |
| T-14 | Backup erhält IDs, Chronologie, Montagen, Regeln, Wartung | Kern + App | M1, M8 |
| I-10 | Inkrementell == Neuaufbau (zufällige Befehlsfolgen) | Kern | M1 |
| 14.2 | Echte HealthKit-Rechte, Observer, Kill/Launch | Gerät | M3, G |
| 14.2 | Notification-Kategorien, Actions, Deep Links, Intents | App + Gerät | M6 |
| 14.2 | Live Activity alle Abläufe | Gerät | M7 |
| 14.2 | Schema-Upgrade Testmigration | App | M2, M8 |
| 14.3 | Onboarding mit/ohne HealthKit, 3 Tabs, Vorlagen, 1-Tap, Mehrfachzuordnung, Tausch, Dark/XXL/VoiceOver | UI | M2–M9 |
| 13 | Performance 10k/1k | App (measure) | M9 |

Testinfrastruktur: Kern mit Swift Testing; App-Tests mit In-Memory-Container (`-InMemoryStore`); UI-Tests mit Startargument `-UITestFixture <name>` (Fixtures im Kern definiert, damit Kern- und UI-Tests dieselben Daten nutzen); HealthKit nur über `HealthWorkoutSource`-Fake in Tests. Testdaten in Health schreiben nur in einem Debug-Schema auf dem Simulator, nie im Release (würde Schreibberechtigung erfordern, Spec 6.4).

---

## 5. Planungsannahmen (umkehrbar, im Code als Kommentar mit Spec-Verweis)

| Nr | Annahme | Warum |
|---|---|---|
| P-01 | Zugehörigkeit zu einer Montage über `startAt` der Aktivität, Intervalle halb offen. | Spec 4.3 verlangt eindeutige zeitliche Wirksamkeit; Teilewechsel mitten im Training ist praktisch irrelevant. |
| P-02 | Multisport: Zuordnung entweder auf Segment- oder Aktivitätsebene je Gegenstand; derselbe Gegenstand in zwei Segmenten = zwei Ledger-Einträge (verschiedene Segmente), nie doppelt im selben Segment. | Spec 4.3 „pro Komponente und Aktivität max. einmal“ ist für Segmente nicht eindeutig; diese Lesart verhindert Doppelzählung und erfindet keine Distanz. **Bei Spec-Revision bestätigen lassen.** |
| P-03 | „Seit Einbau“ bezieht sich auf die aktuelle Montage; frühere Montagen zählen in die Lebensdauer. | Spec 5.3. |
| P-04 | Lebenszyklus-Historie (`GearStatusChange`) als zusätzliche Entität. | Nötig für Spec 6.2 (Status im Aktivitätszeitraum). |
| P-05 | Ersatz-Erkennung bei Löschen+Neuanlage nur bei genau einem Kandidaten gleicher Quelle/Typ/Zeit im selben Batch; sonst Posteingang. | Spec 5.2 (nur sehr starke eindeutige Übereinstimmung). |
| P-06 | Dateischutz `completeUntilFirstUserAuthentication`. | Notification-/Intent-Aktionen auf gesperrtem Gerät müssen schreiben können; Abwägung in PLATTFORM.md. |
| P-07 | Startintervalle aus Vorlagen sind Spannen („2.500–3.500 km, Startwert“), nie Prozent-Verschleiß. | Spec 1.1, 8.2. Konkrete Zahlen nur mit Quelle oder als Platzhalter, den der Nutzer setzt. |
| P-08 | iPad: läuft als skalierte iPhone-Oberfläche, keine eigene Optimierung in V1. | Spec 10.1 „opportunistisch“. |

---

## 6. Offene Entscheidungen für Lino

| Nr | Frage | Empfehlung | Blockiert |
|---|---|---|---|
| E-01 | Produktname und Bundle-ID | **Entschieden (Verfahren):** Agent recherchiert 3–5 Vorschläge mit Kollisionsprüfung, Lino wählt. Recherche liegt vor: `docs/NAMENSRECHERCHE.md`. Bundle-Präfix analog `de.linolaske.<name>`. **Offen: Linos Wahl.** | M2 (Xcode-Projekt, Signierung), alles danach |
| E-02 | Deployment Target | **Entschieden 21.11.2026: iOS 26+.** | M2 |
| E-03 | Repo: lokal, GitHub privat oder öffentlich (AGPLv3 wie CarbStock) | **Entschieden 21.11.2026: GitHub privat bis der Name steht.** Umgesetzt: privates Repo `MagicalWig34653/sportausruestung`. Öffentlich/Lizenz erst nach der Namenswahl neu entscheiden. | – |
| E-04 | Gerätetests S-1/S-2 auf Linos iPhone (+ Watch für echte Workouts) | Ja, nach M3 bzw. M7, je ca. 1–2 Tage Alltag. | M3/M7-Abnahme |

Hinweis für eine spätere Spec-Fassung (keine V1-Frage): App Review 5.1.3(ii) verbietet, „personal health information in iCloud“ zu speichern (PLATTFORM F-13). Die in Spec 10.6/16 vertagte CloudKit-Option muss das vorab klären.

Bewusst **keine** Frage an Lino (Arbeitsentscheidungen oben, P-xx). Beziehung zu CarbStock: CarbStock M9c plant ebenfalls Apple-Health-Workouts. Kein gemeinsamer Code in V1 (verschiedene Apps, verschiedene Datenmodelle); Erkenntnisse aus S-1 werden geteilt.

---

## 7. Risiken

| Risiko | Wirkung | Gegenmaßnahme |
|---|---|---|
| Background Delivery kommt spät/selten | Ein-Tap-Benachrichtigung erscheint verzögert | Vordergrund-Abgleich, Posteingang, ehrliche Texte; Spike S-1 misst real |
| Health-Daten bei gesperrtem Gerät nicht lesbar | Hintergrundimport scheitert | Fehler merken, bei Entsperren wiederholen (ARCHITEKTUR 5.2) |
| Live Activity ohne Server nicht aus dem Hintergrund startbar | Kein LA beim ersten neuen Workout nach langer Pause | LA nur aus zulässigen Kontexten, Notification als Hauptweg (Spec 7.3) |
| SwiftData-Eigenheiten (Concurrency, Migration) | Datenverlust/Abstürze | ein Schreiber, IDs statt Kaskaden, Migrationstest früh, Ledger neu baubar |
| Doppelzählung bei komplexen Montagen | falsche km | Invarianten + Eigenschaftstest I-10 |
| Name kommt spät | M2 wartet | M1 ist namensunabhängig und groß genug für den Start |
| Platte des Macs rot (21.11.: 22,5 GB) | Xcode-Builds blockieren andere Projekte | M1 nur `swift test`; Simulator-Arbeit erst bei Platte ≥ Gelb, DerivedData im Repo-`build/` |
