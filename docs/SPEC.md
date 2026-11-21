# SPEC.md — Sportausrüstung & Verschleiß

> **Status:** Product & Technical Specification · v1.0 · 21.11.2026  
> **Arbeitstitel:** GearFlow (vorläufig, kein festgelegter Produktname)  
> **Plattform:** iPhone / iOS · vollständig nativ in Swift  
> **Leitmotiv:** **Einfach. Intuitiv. Automatisch.**

---

## 0. Zusammenfassung

GearFlow ist eine **lokale, offlinefähige iOS-App zur Verwaltung von Sportausrüstung, Komponenten, Wartungen und Nutzung**. Sie importiert Trainingseinheiten aus Apple Health, ordnet sie möglichst automatisch der passenden Ausrüstung zu und aktualisiert Nutzungs- und Wartungsstände. Nur wenn die Zuordnung nicht zuverlässig möglich ist, wird eine kurze Bestätigung angefordert — bevorzugt per interaktiver Benachrichtigung, im zulässigen Kontext zusätzlich über eine Live Activity.

Der Nutzer muss **nicht vor oder nach jedem Training eine App öffnen**. Gleichzeitig können interessierte Nutzer Fahrräder bis auf einzelne Bauteile und andere Sportausrüstung nach Bedarf detailliert verwalten. **Alle wesentlichen Sportarten sind ab der ersten Version als Kategorien verfügbar**; spezialisierte Ausrüstungsvorlagen und Metriken unterscheiden sich je nach Sportart.

### 0.1 Unverhandelbare Vorgaben

1. **100 % native Swift-Entwicklung:** SwiftUI, SwiftData, HealthKit, ActivityKit, WidgetKit, App Intents, UserNotifications; keine Web-Oberfläche, kein JavaScript/React-Native/Flutter, kein eigener Server.
2. **Local-first:** sämtliche App-Daten liegen standardmäßig auf dem Gerät; nutzbar ohne Internet und ohne Benutzerkonto.
3. **Automatisierung vor Eingabe:** neue Aktivitäten importieren, Duplikate vermeiden, Ausrüstung vorschlagen, Nutzungsstände automatisch aktualisieren.
4. **Minimale Interaktion:** normale Aktivität = null Eingaben; unklare Aktivität = idealerweise ein Tap; Wartung = wenige Taps.
5. **Breite Sportartenunterstützung ab Tag 1:** keine Fahrrad-only-App; die Tiefe der Komponentenmodelle darf je Kategorie variieren.
6. **Ausstehende Zuordnungen:** zentraler Posteingang, lokale Benachrichtigungen und — wenn technisch zulässig — Live Activities.
7. **Ehrliche Daten:** gemessener Verschleiß, Wartungsintervall und Prognose müssen klar voneinander getrennt sein.
8. **Kein Vendor-Lock-in:** lokaler Datenexport und Wiederherstellung.

### 0.2 Nicht-Ziele der ersten Version

- Kein Community-Feed, soziales Netzwerk, Marketplace, Gamification oder Abo-System.
- Keine eigenen Trainingstracker, GPS-Daueraufzeichnung, Navigations- oder Sensoraufzeichnung.
- Keine „magische KI“, die ein tatsächlich verwendetes Fahrrad oder Schuhe ohne Datenbasis garantiert erkennt.
- Keine direkte Strava-/Garmin-/TrainingPeaks-API-Integration, solange kein sicherer, erlaubter und backendfreier Authentifizierungsweg definiert wurde. Aktivitäten dieser Dienste können **über Apple Health** einfließen, sofern der jeweilige Dienst sie dort schreibt.
- Keine verpflichtende Cloud-Synchronisierung oder Registrierung.
- Keine automatische Behauptung, ein Bauteil sei sicher oder unsicher: Wartungshinweise sind Empfehlungen, keine technische Zustandsprüfung.

---

## 1. Produktprinzipien / UX

### 1.1 Die fünf Regeln

- **Unsichtbar, solange alles läuft:** automatisch gebuchte Aktivitäten erzeugen keine Erfolgsbenachrichtigung.
- **Nur relevante Entscheidungen zeigen:** offene Zuordnungen, anstehende Wartung, seltene Probleme; keine permanente Aufforderung zum Ausfüllen.
- **Progressive Disclosure:** ein Paar Schuhe kann mit einem Namen starten; ein Fahrrad kann optional in Kette, Kassette, Reifen, Bremsbeläge usw. zerlegt werden.
- **Jeder Fehler korrigierbar:** Zuordnung, Kilometerstand, Einbaudatum oder Wartung lassen sich rückwirkend ändern; alle abgeleiteten Summen werden konsistent neu berechnet.
- **Keine falsche Präzision:** statt „61 % verschlissen“ lieber „1.840 km seit Einbau · Intervall 2.500–3.500 km“ oder ein explizit als Schätzung bezeichnetes Signal.

### 1.2 Navigationsstruktur

**Drei Haupttabs:**

1. **Übersicht** — Status, ausstehende Zuordnungen, Wartungshinweise, zuletzt verwendete Ausrüstung und letzte Aktivität.
2. **Ausrüstung** — Kategorien, Gegenstände, Komponenten, Details, Schnellaktionen, Archiv.
3. **Verlauf** — Trainings, Zuordnungen, Wartungen, Wechsel, Filter und nach Zeitraum aggregierte Nutzungsdaten.

**Einstellungen** über eine Schaltfläche oben rechts, kein vierter Tab.

### 1.3 Verhalten bei leerem Zustand

- Keine leeren Statistiken oder roten Warnungen.
- CTA „Erstes Ausrüstungsteil hinzufügen“; optional „Aktivitäten aus Apple Health importieren“.
- Funktioniert mit rein manuellen Daten, falls HealthKit nicht gewünscht oder nicht verfügbar ist.
- Für jede Sportart gibt es eine passende, sehr kurze Ausrüstungsvorlage.

### 1.4 Bedienung und Barrierefreiheit

- Systemnahe SwiftUI-Controls, SF Symbols, Dynamic Type, VoiceOver, hohe Kontraste, Hell/Dunkel.
- Farben niemals als einziges Statussignal.
- Systemlokalisierung zunächst **de-DE und en-US**; Metrik in km/m, Zeit in Minuten/Stunden, Geldbeträge mit ISO-Währungscode.
- Große Touch-Ziele, klare Beschriftungen, keine Pflicht-Textfelder außer Bezeichnung bei freiem Eintrag.
- Keine Modal-Kaskaden. Quick Actions als `confirmationDialog`, Kontextmenü oder Sheet.

---

## 2. Zielgruppen und zentrale Anwendungsfälle

### 2.1 Persona: Gelegenheitsläufer

Besitzt zwei Paar Laufschuhe. Nach jedem Lauf soll automatisch das übliche Paar verbucht werden. Bei Unklarheit genügt ein Tap. Die App zeigt Laufleistung und individuelle Historie.

### 2.2 Persona: Rennradfahrer

Besitzt mehrere Fahrräder. Will Fahrradkilometer sowie Kette, Reifen, Kassette und Bremsbeläge getrennt verfolgen, Wartungen protokollieren und Teile zwischen Fahrrädern umbauen.

### 2.3 Persona: Multisport

Nutzt Sportschuhe, Fahrrad, Schwimmausrüstung, Outdoor-Zubehör und Fitnessgeräte. Erwartet eine gemeinsame Bibliothek, aber keine riesige Setup-Prozedur.

### 2.4 Kern-User-Stories

- **US-01:** Als Nutzer möchte ich nach der erstmaligen Einrichtung absolvierte Trainings automatisch übernehmen, ohne jedes Training manuell einzutragen.
- **US-02:** Als Nutzer möchte ich, dass übliche Ausrüstung automatisch gewählt wird und unklare Zuordnungen per einem Tap bestätigt werden.
- **US-03:** Als Nutzer möchte ich mehrere Gegenstände gleichzeitig einer Aktivität zuordnen können (z. B. Fahrrad + Radschuhe + Helm).
- **US-04:** Als Nutzer möchte ich Komponenten montieren, demontieren, tauschen und lagern können, ohne ihre bisherige Historie zu verlieren.
- **US-05:** Als Nutzer möchte ich eine Wartung schnell erfassen können, ohne dafür die gesamte Aktivitätshistorie bearbeiten zu müssen.
- **US-06:** Als Nutzer möchte ich sehen, wie viel eine Komponente seit Einbau bzw. seit der letzten Wartung genutzt wurde.
- **US-07:** Als Nutzer möchte ich falsche Zuordnungen rückwirkend korrigieren können; die Berechnung muss sich automatisch berichtigen.
- **US-08:** Als Nutzer möchte ich Erinnerungen dosiert einstellen und die App auch ohne Benachrichtigungsfreigabe verwenden können.
- **US-09:** Als Nutzer möchte ich ein Backup exportieren und auf einem anderen Gerät wiederherstellen können.

---

## 3. Unterstützte Sportarten und Ausrüstung

### 3.1 Grundprinzip

**Sportart ≠ Ausrüstungstyp ≠ Nutzungsmetrik.** Ein Training kann mehrere Ausrüstungsgegenstände beanspruchen, und ein Gegenstand kann für mehrere Sportarten freigegeben sein.

Jede Sportart besitzt eine Kategorie, optionale Unterkategorien, ein Sportart-Mapping zu HealthKit und Ausrüstungsvorlagen. Unbekannte HealthKit-Aktivitätstypen landen in „Weitere“ statt verworfen zu werden.

### 3.2 Kategorien ab v1

| Kategorie | Beispiele/Untertypen | Standard-Ausrüstung | Typische Metriken |
| --- | --- | --- | --- |
| Radsport | Rennrad, Gravel, MTB, City, Indoor | Fahrrad, Schuhe, Helm, Kleidung, Teile | Distanz, Zeit, Nutzungen |
| Laufen | Straße, Trail, Laufband | Laufschuhe, Bekleidung, Zubehör | Distanz, Zeit, Nutzungen |
| Gehen & Wandern | Spaziergang, Trekking, Hiking | Wanderschuhe, Stöcke, Rucksack | Distanz, Zeit, Nutzungen |
| Schwimmen | Pool, Freiwasser | Brille, Badebekleidung, Flossen | Distanz, Zeit, Nutzungen |
| Fitness & Kraft | Studio, Kraft, funktionell, Yoga | Schuhe, Matte, Gürtel, Zubehör | Zeit, Nutzungen |
| Wintersport | Ski, Langlauf, Snowboard | Ski, Board, Boots, Helm | Distanz, Zeit, Nutzungen, Alter |
| Ballsport | Fußball, Basketball, Handball, Volleyball | Schuhe, Ball, Schützer | Zeit, Nutzungen |
| Schlägersport | Tennis, Badminton, Squash, Padel | Schläger, Schuhe, Bespannung | Zeit, Nutzungen |
| Wasser- & Paddelsport | Rudern, Kajak, SUP, Surfen | Board, Paddel, Kleidung | Distanz, Zeit, Nutzungen |
| Triathlon/Multisport | kombinierte Trainings | Kombination passender Ausrüstung | Segmentabhängig |
| Klettern & Bergsport | Indoor, Outdoor | Kletterschuhe, Chalkbag, Equipment | Zeit, Nutzungen, Alter |
| Sonstige | beliebige HealthKit-Kategorie | frei definierbar | konfigurierbar |

**Hinweis:** Erstunterstützung bedeutet: Kategorie, Anlage, Vorlagen, Zuordnung und geeignete Metriken funktionieren. Eine Speziallogik für jede einzelne Unterdisziplin ist **nicht** Voraussetzung für v1.

### 3.3 Sportarten-Mapping

- Adapter `HKWorkoutActivityType -> SportCategory/Subtype` als zentral testbare Tabelle.
- Indoor/Outdoor nur übernehmen, wenn Metadaten oder Quelle das belastbar liefern; nicht aus Distanz allein behaupten.
- Bei Multisport / Segmenten die Aufteilung je nach tatsächlichen HealthKit-Daten übernehmen; sonst Gesamtdauer und manuelle Segmentzuordnung anbieten.
- Nicht vorhandene Distanz niemals künstlich schätzen.

---

## 4. Ausrüstung, Komponenten und Lebenszyklus

### 4.1 Begriffe

- **Ausrüstungsgegenstand (`GearItem`):** individuell verfolgter Gegenstand, etwa „Canyon Endurace“, „Nike Laufschuhpaar“ oder „Tennisschläger“.
- **Komponente:** ebenfalls ein `GearItem`, das zeitweise in einem übergeordneten Gegenstand verbaut sein kann; kein zweites, getrenntes Datensystem.
- **Montage (`Installation`):** zeitlich begrenzte Parent-Child-Beziehung, z. B. Kette auf Fahrrad A. Historie bleibt auch nach Ausbau erhalten.
- **Ausrüstungsset (`GearPreset`):** optionale Gruppierung häufiger Gegenstände, z. B. Rennrad + Radschuhe + Helm. **Keine physische Montage**.
- **Aktivitätszuordnung (`ActivityGearAssignment`):** Zuordnung zwischen Aktivität bzw. Segment und selbstständig verwendeter Ausrüstung.
- **Wartungsereignis (`MaintenanceEvent`):** Wachsen, Reinigen, Prüfen, Messen, Wechseln etc.
- **Nutzungsereignis (`UsageLedgerEntry`):** nachvollziehbarer Beitrag einer Aktivität zu einem Gegenstand. Wird deterministisch hergeleitet und kann neu aufgebaut werden.

### 4.2 Lebenszyklusstatus

`active`, `stored`, `retired`, `sold`, `disposed`, `lost`, `archived`.

- **Aktiv:** grundsätzlich zuweisbar.
- **Eingelagert:** bleibt sichtbar, wird nicht automatisch vorgeschlagen, sofern nicht ausdrücklich ausgewählt.
- **Ausgemustert/Verkauft:** bleibt für Historie erhalten, keine neuen automatischen Zuordnungen.
- **Archiviert:** standardmäßig ausgeblendet, aber nicht gelöscht.

### 4.3 Montage/Ausbau/Umbau

- Eine physische Komponente darf im gleichen Zeitraum **höchstens eine aktive Montage** haben.
- Keine zyklischen Hierarchien (Fahrrad → Laufrad → Reifen ist zulässig; Fahrrad → ... → Fahrrad nicht).
- Eine Umbuchung beendet die bisherige Montage und startet die neue; das Komponenten-Objekt und seine Lebensdauer bleiben bestehen.
- Zeitliche Wirksamkeit ist entscheidend: eine Aktivität von gestern darf bei einem heutigen Kettenwechsel **nicht** der neuen Kette gutgeschrieben werden.
- Eine Komponente darf auf mehreren Hierarchieebenen hängen. Nutzungsbeiträge werden **pro Komponente und Aktivität maximal einmal** gebucht.

### 4.4 Neue Teile / Austausch

„Kette ersetzen“ bedeutet: alte Montage beenden, altes Teil optional einlagern/ausmustern, **neues GearItem** aus Vorlage oder Duplikat erzeugen, neue Montage starten. Der Verschleiß der alten Kette wird nicht auf null zurückgesetzt.

### 4.5 Zeitliche Änderungen

Bei rückdatiertem Umbau, geänderter Aktivität oder gelöschter Zuordnung werden die betroffenen Nutzungsaggregate aus den zugrunde liegenden Daten **neu berechnet**. Es gibt keinen destruktiven globalen Kilometerzähler als einzige Quelle der Wahrheit.

---

## 5. Datenmodell (v1 — konzeptionell)

**Persistenz:** SwiftData (`@Model`) mit separaten Domain-Modellen/DTOs. Bezeichner als stabile `UUID`; Datum als `Date` (UTC-semantisch gespeichert); Zahlen in Basiseinheiten (Meter, Sekunden, Anzahl). Schema-Versionierung mit geplanter Migration.

### 5.1 Entitäten

| Entität | Wesentliche Felder | Zweck |
| --- | --- | --- |
| `GearItem` | `id`, `name`, `category`, `subtype`, `brand?`, `model?`, `imagePath?`, `purchaseDate?`, `purchasePriceMinor?`, `currency?`, `status`, `createdAt` | Alle einzeln verfolgten Gegenstände/Teile |
| `Installation` | `id`, `parentGearID`, `childGearID`, `startedAt`, `endedAt?`, `notes?` | Historisierte Montage, auch Umbau |
| `GearPreset` | `id`, `name`, `sportTypes`, `isEnabled` | Wiederkehrende Ausrüstungssets |
| `GearPresetMember` | `presetID`, `gearID`, `role` | Zuordnung zum Set |
| `SportProfile` | `id`, `sportType`, `enabled`, `defaultPresetID?`, `notificationPreference` | Individuelle Sportarten-Präferenzen |
| `ActivityRecord` | `id`, `source`, `sourceID?`, `sportType`, `startAt`, `endAt`, `distanceMeters?`, `durationSeconds`, `importHash?`, `deletedAt?` | Kanonisches Training |
| `ActivitySegment` | `id`, `activityID`, `sportType`, `startAt`, `endAt`, `distanceMeters?` | Optionale Multisport-Segmente |
| `ActivityGearAssignment` | `id`, `activityID`, `segmentID?`, `gearID`, `origin`, `confidence?`, `confirmedAt?`, `createdAt` | Gear-to-Workout many-to-many |
| `PendingAssignment` | `id`, `activityID`, `state`, `proposedGearIDs`, `createdAt`, `lastPromptAt?`, `resolution` | Ausnahme-Posteingang |
| `MaintenanceEvent` | `id`, `gearID`, `kind`, `performedAt`, `usageSnapshot?`, `measurement?`, `costMinor?`, `notes?` | Wartung, Inspektion und Messungen |
| `MaintenanceRule` | `id`, `gearID`, `kind`, `metric`, `intervalValue`, `warningLeadValue?`, `enabled` | Individuelle Intervallhinweise |
| `UsageLedgerEntry` | `id`, `activityID`, `segmentID?`, `gearID`, `distanceMeters?`, `durationSeconds?`, `uses`, `derivationVersion` | Reproduzierbare Nutzung pro Gegenstand |
| `AssignmentRule` | `id`, `sportType`, `kind`, `conditions`, `gearIDs`, `priority`, `enabled` | Regeln für automatische Zuordnung |
| `ImportCursor` | `source`, `anchorData?`, `lastSyncAt`, `reconcileState` | HealthKit-Importstatus |
| `NotificationRecord` | `id`, `relatedID`, `type`, `sentAt`, `resolvedAt?` | Deduplizierung, Ruhezeiten |
| `AppSettings` | `units`, `languageOverride?`, `reminders`, `quietHours`, `healthImportStartAt`, `onboardingVersion` | Geräteeinstellungen |

**Implementierungshinweis:** Physische Beziehungen und Fremdschlüssel-IDs im Modell müssen konsistent gehandhabt werden. Für komplexe Ableitungen nicht ausschließlich SwiftData-Kaskadierung verwenden. Denormalisierte Cache-Werte sind erlaubt, aber nie alleinige Wahrheit.

### 5.2 Zusätzliche Datenregeln

- Es kann mehrere `ActivityGearAssignment`-Einträge pro Aktivität geben.
- Zuordnung einer **übergeordneten Ausrüstung** schreibt Nutzung auf alle zum Aktivitätszeitpunkt montierten Unterkomponenten fort. Direkt zugeordnete Kinder werden nicht doppelt gezählt.
- **Keine automatische Vererbung zwischen unabhängig getragenen Gegenständen:** ein Fahrrad impliziert nicht automatisch Helm oder Schuhe. Dafür sind Presets oder explizite Gewohnheitsregeln zuständig.
- Distanz und Nutzungsdauer folgen dem dokumentierten Messwert; fehlt die Distanz, ist `nil` korrekt, nicht `0`.
- Präzise Distanz je Multisport-Segment wird nur übernommen, wenn vorhanden; keine pauschale Verteilung nach Dauer.
- Änderungen werden als fachliche Ereignisse verarbeitet; `UsageLedgerEntry` kann jederzeit neu erzeugt werden.
- `sourceID` bei HealthKit = `HKWorkout.uuid`; Änderungen/Löschungen berücksichtigen.
- Bei mehreren Quellen innerhalb HealthKit dieselbe Trainingseinheit nicht nur wegen Zeitüberschneidung automatisch zusammenführen. Erst exakte Identität oder sehr starke eindeutige Übereinstimmung; sonst Nutzeroption zum Zusammenführen anbieten.
- Mehrere tatsächliche Aktivitäten mit überlappender Zeit können legitim sein; niemals heuristisch löschen.

### 5.3 Nutzungsmetriken

`distanceMeters`, `durationSeconds`, `usageCount`, `calendarAgeDays`, `measurement` (z. B. Kettenlängung in %), optional `elevationGainMeters` wenn verlässlich vorhanden.

Jeder Gegenstand hat **null bis mehrere** aktivierte Metriken. Nicht alle Metriken werden bei jeder Sportart geliefert. Nutzungswerte können sein:

- **Lebensdauer:** Summe aller historisch belegten Nutzungen.
- **Seit Einbau:** kumuliert ab relevanter Montage.
- **Seit letzter Wartung des Typs:** kumuliert seit dem betreffenden Wartungsereignis.
- **Schätzung:** kenntlich gemachte, durch Regel/Heuristik erzeugte Information.

---

## 6. Aktivitäten importieren und zuordnen

### 6.1 Datenquelle: HealthKit

MVP-Eingang: `HKWorkout` und die für Workouts nötigen Informationen. Optional `HKWorkoutRoute` nur bei späterer begründeter Funktion; **keine Route und keine genauen Standortdaten für v1 erforderlich**.

Technischer Ablauf:

1. Explizite HealthKit-Leseberechtigung für Trainings anfordern.
2. Bei Onboarding einen **vom Nutzer gewählten Importzeitraum** anbieten (Vorgabe: letzte 90 Tage; „alle verfügbaren“ als Option).
3. `HKAnchoredObjectQuery` für initiale und inkrementelle Änderungen einschließlich gelöschter Einträge.
4. `HKObserverQuery` mit Background Delivery zur Benachrichtigung über Änderungen, soweit das System dies ermöglicht; danach Anchored Query zur tatsächlichen Ermittlung ausführen.
5. Bei jedem App-Start und App-Foreground einen Konsistenzabgleich anstoßen.
6. Import idempotent durchführen; Anker erst nach erfolgreichem persistentem Commit speichern. Bei Absturz wird der Import sicher wiederholt.
7. HealthKit-Berechtigungen können jederzeit eingeschränkt werden; App darf nicht aus „keine Daten sichtbar“ automatisch auf explizite Ablehnung schließen.

**Keine Echtzeitgarantie:** iOS legt Ausführungszeit und Hintergrundzustellung fest. Die App darf niemals garantieren, dass binnen Sekunden nach Workout-Ende eine Zuordnungsbenachrichtigung erscheint.

### 6.2 Algorithmus: Zuordnungs-Engine

Schritte:

1. Sportart erkennen, mögliche Kandidaten aus aktiver Ausrüstung und zugehörigen Presets ermitteln.
2. **Explizite Information priorisieren:** vorhandene fest zugewiesene Ausrüstung, bestätigte Nutzervorgabe, feste Zuordnungsregel.
3. Regeln auswerten: Sportart, Indoor/Outdoor falls belegt, übliche Ausrüstung, zurückliegende bestätigte Zuordnungen, Tagesmuster optional **ohne Standortüberwachung**.
4. Kombinationen aus unabhängigen Gegenständen (z. B. Fahrrad + Radschuhe + Helm) über Presets/Regeln vorschlagen.
5. Resultat mit erläuterbarer Begründung und Konfidenz zurückgeben.
6. Automatisch verbuchen oder `PendingAssignment` erzeugen.

**Empfohlene Entscheidungspolitik für v1:**

- Eine **explizite Default-Regel** oder ein eindeutig passendes Preset darf ohne Nachfrage angewendet werden.
- Bei mehreren Kandidaten nur automatisieren, wenn das Ergebnis aus verlässlichen Regeln eindeutig ist; reine heuristische Konfidenz niemals als Gewissheit ausgeben.
- Beim ersten Training einer Sportart mit mehreren passenden Gegenständen einmalig nachfragen; nach Bestätigung optional „Für ähnliche Aktivitäten merken“ anbieten.
- Falls überhaupt keine Ausrüstung vorhanden ist: Aktivität trotzdem importieren, als „Ohne Ausrüstung“ markieren und *keine* lästigen Benachrichtigungen schicken.
- Wenn Kandidat im Aktivitätszeitraum eingelagert/ausgemustert oder noch nicht gekauft/montiert war: Vorschlag abwerten oder ausschließen; explizite historische Auswahl erlauben.

Konfidenz-Enums (initial ohne ML): `explicit`, `high`, `medium`, `low`, `none`. Eine etwaige numerische Wahrscheinlichkeit wird v1 **nicht** behauptet.

### 6.3 Korrektur und Lernen

- Bei „Falsch“ wird die Zuordnung rückwirkend ersetzt; die Nutzung des alten Gegenstands sinkt, die des neuen steigt.
- „Für ähnliche Aktivitäten merken“ erstellt eine nachvollziehbare `AssignmentRule`. Diese kann in Einstellungen angesehen/deaktiviert werden.
- Automatische Regel darf nicht stillschweigend neue, unerwartete Gegenstände zu bereits abgeschlossenen Aktivitäten hinzufügen.
- Korrektur in `Verlauf > Aktivität > Ausrüstung` jederzeit möglich.

### 6.4 Manuelle Aktivitäten

- Anlegen mit Sportart, Start/Datum, Dauer, optional Distanz, Ausrüstung; keine HealthKit-Schreibberechtigung nötig.
- Manuelle Einträge können dieselbe Zuweisungs- und Wartungslogik durchlaufen.
- Bei später erkanntem entsprechendem HealthKit-Training Zusammenführung explizit vorschlagen statt zu doppeln.

---

## 7. Offene Zuordnungen, Benachrichtigungen und Live Activities

### 7.1 Zustandsmaschine

`unresolved` → `suggested` → `resolved`  
Zusätzliche Übergänge: `dismissed` (bewusst ohne Ausrüstung), `ignored` (weiter im Posteingang), `obsolete` (Training gelöscht/zusammengeführt).

Persistente Posteingangs-Einträge sind **immer** die Quelle der Wahrheit. Notification und Live Activity zeigen nur den Zustand an.

### 7.2 Lokale Benachrichtigungen

`UserNotifications` mit registrierten `UNNotificationCategory`/`UNNotificationAction`:

- Bei einer klaren Empfehlung: **„Vorschlag übernehmen“**, **„Andere auswählen“**, optional „Später“.
- Bei mehreren gleich plausiblen Kandidaten: „Ausrüstung wählen“ statt eine falsche Empfehlung zu forcieren.
- Die Vorschlagsaktion referenziert eine **stabile `PendingAssignment.id`**; beim Ausführen wird der Zustand erneut aus der lokalen Datenbank geladen (Schutz vor veralteten Notifications).
- Aktion muss idempotent sein; bei bereits erledigter Zuordnung keine doppelte Belastung.
- Benachrichtigungen bündeln: mehrere offene Aktivitäten möglichst als eine Zusammenfassung statt einer Flut von Alerts.
- Ruhezeiten und wählbare Stufen: `aus`, `nur Zuordnung`, `Zuordnung + Wartung`.
- Ohne Notification-Berechtigung bleibt der App-Posteingang vollständig funktional.

**Einschränkung:** Notification-Aktionsbeschriftungen und -anzahl sind vom System begrenzt. Keine garantierte dynamische Liste beliebig vieler Fahrräder direkt als Aktionsbuttons. Die einfache Standardaktion bestätigt eine **vorher berechnete Empfehlung**; bei Mehrdeutigkeit öffnet „Auswählen“ den richtigen Bildschirm.

### 7.3 Live Activity

**Zweck:** vorübergehend sichtbarer Hinweis auf *aktuell zu klärende* Zuordnungen mit 1-Tap-Aktionen, passend für Sperrbildschirm/Dynamic Island. **Kein dauerhafter Mehrtages-Posteingang.**

Darstellung:

- Kompakt: Sportartsymbol + Anzahl offener Zuordnungen.
- Expanded/Lock Screen: jüngste Aktivität, Distanz/Dauer soweit verfügbar, höchstens zwei priorisierte Kandidaten, „Weitere“.
- Ein Action-Tap ruft einen geeigneten `AppIntent` auf, der lokal persistiert und den sichtbaren Zustand aktualisiert, soweit Ausführung und Datenzugriff zulässig sind.
- Bei Abschluss Ende/Aktualisierung der Live Activity; beim Ablauf bleiben offene Zuordnungen im Posteingang.
- Datenschutz: keine genauen Routen, Standorte, Gesundheitsdiagnosen oder unnötigen Details auf dem Lock Screen.

**Technische Produktgrenze (entscheidend):**

- Ohne APNs/Backend kann die App **nicht beliebig bei jedem im Hintergrund eingehenden HealthKit-Workout eine neue Live Activity starten**.
- Start nur in erlaubten Kontexten (z. B. App im Vordergrund oder zulässiger `LiveActivityIntent`-Ablauf; Kompatibilität der konkret gewählten iOS-Version testen).
- Live Activities haben systemseitige Laufzeit- und Sichtbarkeitsgrenzen (typisch aktiv bis 8 Stunden, auf Sperrbildschirm höchstens 12 Stunden inkl. Nachlauf). Nicht als persistente offene Aufgabe missbrauchen.
- **Fallback ist zwingend:** lokale Benachrichtigung + „Offene Zuordnungen“-Ansicht. Keine Ausführung darf auf Live Activity angewiesen sein.

### 7.4 Wartungserinnerungen

- Erinnerungen nur für **aktivierte Regeln**.
- Auslösearten: Nutzungsintervall überschritten, feste Zeit seit Wartung, manuell hinterlegte Prüfung.
- Wiederholung erst nach sinnvoller Cooldown-Zeit (Vorgabe 7 Tage) oder nach deutlichem neuem Ereignis.
- Hinweis „Prüfen“ statt „Jetzt zwingend ersetzen“.
- Wartung kann direkt aus der Benachrichtigung über Deeplink geöffnet werden.

---

## 8. Wartungen und Verschleißlogik

### 8.1 Schnellaktionen

Ab v1 verfügbare Ereignistypen:

- Gereinigt
- Geschmiert / gewachst
- Geprüft
- Verschleiß gemessen
- Teil eingebaut / ausgebaut / ersetzt
- Repariert
- Frei definierte Wartung

Wartungsvorgang: `GearItem öffnen → Schnellaktion → Speichern`. Datum = jetzt; optional rückdatieren; optionale Notiz, Messwert, Kosten.

### 8.2 Intervall ≠ tatsächlicher Verschleiß

Die UI unterscheidet **drei Statusarten**:

1. **Intervallstatus:** z. B. „Kette seit letzter Schmierung: 320 km · eigenes Intervall 350 km“.
2. **Messwert:** z. B. „Kettenlängung zuletzt gemessen: 0,50 % am 12.11.“.
3. **Prognose:** nur wenn ausreichend Daten vorliegen; z. B. „Bei bisherigem Nutzungsverlauf voraussichtlich bald prüfen“ und Kennzeichnung als Schätzung.

Keine generischen, produktspezifisch erfundenen Lebensdauern als Tatsachen. Vorschläge aus Templates sind editierbar, konservativ und deutlich als Startwerte gekennzeichnet; bei sicherheitskritischen Teilen grundsätzlich Prüfung statt automatischem Freigabesignal.

### 8.3 Intervalle

Konfigurierbar pro Gegenstand/Komponente: Distanz, Nutzungsdauer, Nutzungsanzahl, Kalenderintervall oder individueller Messgrenzwert. Kombinationsregeln „frühester fälliger Wert“ sind optional.

### 8.4 Komponentenwechsel

Der Komponentenwechsel erfasst eine neue Instanz und eine neue Montage. Alte Komponenten- und Kostenhistorie bleibt sichtbar. Der Nutzer kann Kaufbeleg/Foto und Einkaufspreis später ergänzen.

### 8.5 Kosten

v1 optionales Feld für Kaufpreis und Wartungskosten. Basis-Auswertungen: Gesamtkosten pro Gegenstand, Kosten pro Kilometer **nur wenn nutzbare Distanz vorhanden**. Keine Prognose auf Grundlage unvollständiger Kosten ohne Hinweis.

---

## 9. Screens und Interaktionsabläufe

### S01 — Onboarding (max. drei Schritte)

1. Sportarten auswählen; alle wesentlichen Kategorien wählbar, Mehrfachauswahl möglich.
2. Apple Health verbinden oder „Später“.
3. Erstes Ausrüstungsteil per Vorlagen-Assistent hinzufügen oder „Später“.

**Kein Account, keine Newsletter-Frage, keine Pflicht-Kreditkarte.** Notifications **kontextbezogen** anfragen, erst wenn der Nutzen verständlich wird (nicht alles beim allerersten Start).

### S02 — Übersicht

- Kompakte Status-Zusammenfassung.
- Offene Zuordnungen prominent, falls vorhanden; sonst kein leerer Block.
- Maximal drei priorisierte Wartungshinweise.
- Zuletzt verwendete Ausrüstung und letzte Aktivität.
- Plus-Aktion für Ausrüstung/manuelle Aktivität.

### S03 — Ausrüstungsliste

- Kategorien/Filter, Suchfeld, favorisierte Gegenstände.
- Karten zeigen Bild/Symbol, Name, wichtigste **passende** Nutzungsmetrik, nächsten Wartungshinweis.
- Plus → Kategorie → Vorlage oder frei hinzufügen; maximal Name erforderlich.
- Keine gesamte Komponentenstruktur direkt in der Listenansicht.

### S04 — Ausrüstungsdetail

- Header: Name, Typ, Status, Bild, wichtigste Metrik.
- Kontextaktionen: Wartung, Montage/Teilewechsel, Aktivität zuordnen, Bearbeiten.
- Abschnitte: Nutzungsstand, Komponenten (falls vorhanden), Wartung, Historie, Kosten (optional).
- Bei Fahrrad „Komponenten hinzufügen“ mit Starter-Vorlagen (Kette, Kassette, Laufradsätze, Reifen, Bremsen) ohne Pflicht, alles auszufüllen.

### S05 — Zuordnungs-Posteingang

- Liste ungeklärter Aktivitäten; pro Karte Sport, Datum, Dauer/Distanz und ein klar markierter Vorschlag.
- Primäraktion **„Vorschlag bestätigen“**, sekundär „Ändern“.
- Multi-Select bei Aktivität: mehrere Ausrüstungsteile in **einem** Dialog auswählen, einzelne Rollen/Preset anbieten.
- „Nicht zuordnen“ ist eine gültige Entscheidung.
- „Für ähnliche Aktivitäten merken“ nach erfolgreicher Bestätigung optional.

### S06 — Verlauf

- Chronologische, zusammengeführte Timeline von Aktivitäten, Wartungen, Montagen und Austauschen.
- Filter Sportart, Zeitraum, Ausrüstung, Ereignistyp.
- Aktivität öffnen → Zuordnungen anpassen und Änderungen prüfen.

### S07 — Wartung erfassen

- Schnellaktionsleiste, sofortiges Speichern ohne Formular möglich.
- Erweiterung für Datum, Messwerte, Kosten, Notizen.
- Wenn kein Teil existiert, reicht „Ausrüstung gewartet“ statt erzwungener Komponentenanlage.

### S08 — Einstellungen

- HealthKit-Importzeitraum/Neusynchronisieren, Benachrichtigungen, Live Activities (Informationsstatus; Systemberechtigung wird vom System geregelt), Regeln und Presets, Einheiten, Datensicherung, Datenschutz, Über die App.

---

## 10. Technische Architektur

### 10.1 Zielplattform

- **Empfohlen:** iOS 18 oder neuer (konkretes Deployment Target zu Projektbeginn festlegen, abhängig von benötigten APIs und Zielgeräten).
- Xcode + aktuelle stabile Swift-Toolchain.
- Swift 6 Concurrency und nachvollziehbare Actor-Grenzen.
- Native iPhone-App, unterstützte iPad-Darstellung opportunistisch; Apple Watch-App **nicht** Teil des MVP.
- Kein Third-Party-Backend, keine Laufzeitpflicht für irgendeinen externen Dienst.

### 10.2 Frameworks

| Bereich | Technologie |
| --- | --- |
| UI | SwiftUI, SF Symbols |
| Persistenz | SwiftData, lokale Dateien für Medien |
| Import | HealthKit |
| Live Activity | ActivityKit, WidgetKit Extension |
| Aktionen/Shortcuts | App Intents |
| Lokale Hinweise | UserNotifications |
| Hintergrund-Reconciliation | HKObserverQuery / HKAnchoredObjectQuery, bei Bedarf BackgroundTasks |
| Dateiexport | FileImporter/FileExporter, Codable, UniformTypeIdentifiers |
| Logging | OSLog |
| Tests | Swift Testing/XCTest, XCUITest |

**Dependency Policy:** First-party Apple-Frameworks als Standard, kein unnötiges Drittanbieterpaket. Kein Networking zur Basisfunktion erforderlich.

### 10.3 Modulaufteilung (Beispiel)

```text
GearFlow/
├── App/
│   ├── GearFlowApp.swift
│   ├── AppDependencies.swift
│   └── Navigation/
├── Domain/
│   ├── Models/
│   ├── SportCatalog/
│   ├── Assignment/
│   ├── Usage/
│   └── Maintenance/
├── Data/
│   ├── SwiftData/
│   ├── Repositories/
│   ├── Migration/
│   └── Backup/
├── Integrations/
│   ├── HealthKit/
│   ├── Notifications/
│   └── LiveActivities/
├── Features/
│   ├── Onboarding/
│   ├── Dashboard/
│   ├── Equipment/
│   ├── AssignmentInbox/
│   ├── History/
│   └── Settings/
├── Shared/
│   ├── Components/
│   ├── Formatting/
│   └── Accessibility/
├── GearFlowWidgets/
│   ├── AssignmentLiveActivity.swift
│   └── AssignmentIntents.swift
└── Tests/
    ├── DomainTests/
    ├── IntegrationTests/
    └── UITests/
```

### 10.4 Architekturregeln

- Feature-Views enthalten keine eigene HealthKit-Query-Logik und keine komplexe Nutzungsberechnung.
- Reine Swift-Domain-Services: `AssignmentEngine`, `UsageCalculator`, `MaintenanceEvaluator`, `SportCatalog`.
- `HealthImportService` verwaltet Abfragen und Konvertierung, `ActivityRepository` idempotente Speicherung.
- Schreibzugriffe auf SwiftData über klar definierte, actor-sichere Repository-/Persistence-Grenze.
- Widget-Extension und App Intents teilen nur benötigte, **kleine** App-Group-Daten bzw. greifen mit sicher geklärter Persistenzstrategie zu; keine unkontrollierten gleichzeitigen ModelContext-Zugriffe.
- **App Group** prüfen für gemeinsame Ablage/Status, insbesondere wenn Intents und Widgets Daten zur Zuordnung lesen. Datenbankzugriff und Migrationsstrategie explizit testen.
- Fehler propagieren und fachlich sichtbar machen; keine verschluckten Importfehler.
- Datums-/Zeitberechnung in UTC für Persistenz; Zeitzone nur für Anzeige und tageszeitliche Regeln.

### 10.5 Datenfluss

```text
Apple Health
   │
   ▼
HealthImportService ───► Normalizer / Idempotency
                               │
                               ▼
                         ActivityRepository
                               │
                               ▼
                         AssignmentEngine
                         │             │
                  eindeutige Regel    unklar
                         │             │
                         ▼             ▼
                    Assignments   PendingAssignment
                         │          │         │
                         │       Inbox      Notification
                         │                     │
                         │              Live Activity*
                         ▼
                  UsageCalculator
                         │
                         ▼
                 UsageLedger / Status
                         │
                         ▼
                  SwiftUI / Widgets

* Nur in systemseitig zulässigen Startkontexten.
```

### 10.6 Keine Daten-Synchronisationsillusion

v1 ist **Single-Device und lokal**. Es gibt **kein** automatisches Cross-Device-Sync-Versprechen. Eine spätere optionale private iCloud/CloudKit-Synchronisation wäre technisch ohne eigenes Backend möglich, würde die reine lokale Datenhaltung aber aufheben und erfordert ein separates Design für Konflikte/Identitäten. Keine iCloud-Abhängigkeit für MVP.

---

## 11. Datenschutz, Sicherheit und Datenportabilität

- Keine Registrierung, keine Analytics-SDKs, keine Werbung, kein externes Telemetriesystem.
- Gesundheitstraining ist sensibel: nur erforderliche HealthKit-Typen lesen; Zweck transparent erklären.
- v1 **keine** Speicherung oder Weitergabe von präzisen Routen, wenn zur Abnutzungszuordnung nicht nötig.
- HealthKit-Daten nicht an externe Server übermitteln; keine Cloud-Synchronisierung standardmäßig.
- Keine Behauptung „Health-Zugriff verweigert“, wenn ein leerer HealthKit-Query auch durch fehlende Daten bedingt sein kann.
- Nutzer kann App-Daten vollständig löschen, Ausrüstung und einzelne Aktivitäten manuell entfernen.
- Vollständiger lokaler Backup-Export als **versioniertes JSON** (optional ZIP-Paket mit Fotos) über Files/Share Sheet. Import mit Schema-Validierung, Preview und Konfliktbehandlung.
- Backup ist potenziell vertraulich; beim Export Hinweis auf unverschlüsselte Weitergabe. Optional verschlüsselter Export erst bei gesonderter Spezifikation.
- Datenbanken/Dateien bleiben im iOS-App-Sandbox-Modell; App-Group-Container nur wo erforderlich.
- Löschen einer HealthKit-Aktivität aus der Health-App muss beim nächsten Importabgleich die zugehörigen Nutzungsbeiträge entfernen, nicht das physische Ausrüstungsobjekt löschen.

---

## 12. Fehlerfälle und Zuverlässigkeit

| Fall | Erwartung |
| --- | --- |
| HealthKit nicht verfügbar | Reiner manueller Betrieb, keine Sackgasse |
| Zugriff nicht gewährt / keine Trainings sichtbar | Neutrale Erklärung, Einstellungen-Hinweis, keine falsche Diagnose |
| App im Hintergrund nicht geweckt | Import beim nächsten Start; keine verlorenen Workouts |
| Derselbe Workout mehrfach geliefert | Genau eine `ActivityRecord` pro eindeutiger Quell-ID |
| Workout nachträglich geändert | Aktualisierte Werte führen zu korrigierter Ausrüstungsnutzung |
| Workout in HealthKit gelöscht | Nutzungsledger revidieren, Zuordnungsposteingang schließen |
| Notification nach Bearbeitung angeklickt | Kein Doppel-Commit, veraltete Aktion sauber ignorieren |
| Live Activity darf nicht gestartet werden | Posteingang + normale lokale Benachrichtigung funktionieren |
| Teil rückwirkend eingebaut | Historische Nutzung nach Einbauzeitpunkt neu berechnen |
| Zwei Komponenten doppelt referenziert | Pro Aktivität und physischem Teil nur ein Nutzungsbeitrag |
| Distanz fehlt | Zeit/Nutzungen verwenden, kein erfundener Kilometerwert |
| Kein Netz | Alle Kernfunktionen bleiben bedienbar |
| Datenmigration schlägt fehl | Keine stillen Datenverluste; nachvollziehbare Wiederherstellungsstrategie |
| Systemuhr/Zeitzone ändert sich | Ereignisse zeitlich stabil; Anzeige lokal angepasst |

---

## 13. Messbare Produktanforderungen

Die Werte sind **Projektziele**, keine Garantie von iOS-/HealthKit-Ereigniszustellung.

- **Null-Interaktionsfall:** eindeutige Aktivität wird nach Import ohne Benutzereingriff zugeordnet und ihre Nutzung gezählt.
- **Ein-Tap-Fall:** klarer Vorschlag lässt sich per Notification, Inbox oder zulässiger Live Activity mit einer Aktion bestätigen.
- **Wartung:** bestehendes Teil öffnen und einfache Wartung in höchstens drei Nutzeraktionen speichern (ausgehend vom Detailbildschirm).
- **Ausrüstungserstellung:** Vorlage auswählen, Name bestätigen, speichern; keine Komponentenpflicht.
- **Import:** wiederholter Import desselben Datenbestands verändert die Anzahl importierter Aktivitäten/Nutzungsbeiträge nicht.
- **Datenkonsistenz:** nach jeder Korrektur stimmen aggregierte Lebensdauer-, seit-Einbau- und seit-Wartung-Werte mit dem rekonstruierten Ledger überein.
- **Offline:** keine Kernfunktion scheitert wegen fehlender Internetverbindung.
- **Barrierefreiheit:** Kernflows mit VoiceOver und großen Textgrößen erfolgreich ausführbar.
- **Performance-Ziel:** Übersicht und Ausrüstungsliste auf einem zeitgemäßen iPhone bei lokalem Bestand mit 10.000 Aktivitäten und 1.000 Wartungsereignissen ohne spürbare Blockierung; konkrete Grenzwerte in Performance-Tests festlegen.
- **Sichere Anzeige:** bei fehlenden Metriken „Keine Daten“, nicht falsche 0 km oder falscher Zustand „gut“.

---

## 14. Teststrategie

### 14.1 Unit-Tests (verpflichtend)

1. Ein Training + ein Fahrrad + montierte Kette → jeweils genau einmal verbucht.
2. Kette während eines Zeitraums ausgewechselt → Training vor Wechsel zählt nur für alte Kette, danach nur für neue.
3. Direkt zugeordnete Kette und vererbte Nutzung über Fahrrad → keine Doppelzählung.
4. Aktivitätszuordnung A → B korrigiert → Nutzung bei A sinkt und bei B steigt.
5. Idempotenter HealthKit-Import mit unverändertem Quell-UUID.
6. Reimport eines geänderten Trainings aktualisiert Dauer/Distanz.
7. Gelöschtes HealthKit-Training entfernt dessen Ledger-Einträge.
8. Eine Multisport-Aktivität ohne Segmentdistanz bekommt keine erfundene Segmentdistanz.
9. `nil`-Distanz bleibt `nil`, wird nicht als 0 km dargestellt.
10. Wiederholte Notification-Aktion wirkt höchstens einmal.
11. Wartung bei km X setzt nur den betreffenden „seit Wartung“-Wert zurück, nicht die Lebensdauer.
12. Ein eingelagerter Gegenstand wird nicht aus Gewohnheit automatisch zugewiesen.
13. Montagekreise und zeitlich überlappende Einzelmontagen werden verhindert.
14. Backup-Export/Import erhält Identitäten, Chronologie, Montagen, Regeln und Wartung.

### 14.2 Integrationstests

- Test mit echten HealthKit-Permissions auf realem Gerät (Simulator nicht als alleinige Validierung).
- Observer + anchored requery; mehrfaches Resume und Kill/Launch.
- Notification-Kategorie, Actions, Deep Links, App-Intent-Abläufe.
- Live Activity: Vordergrundstart, erlaubter Intent-Start, Ablauf, Fehlerfallback und Auflösung.
- Upgrade von SwiftData-Schema v1 auf eine Testmigration.

### 14.3 UI-Tests

- Onboarding mit/ohne HealthKit.
- Drei Haupttabs erreichbar und verständlich.
- Ausrüstung mit Vorlagen anlegen.
- Zwei Fahrräder, eine offene Aktivität, Bestätigung mit einem Tap.
- Mehrfachzuordnung von Fahrrad + Helm + Schuhen.
- Komponente tauschen, alte Historie weiterhin aufrufen.
- Dark Mode, Dynamic Type, VoiceOver.

---

## 15. Implementierungsphasen / Definition of Done

### Phase 0 — Fundament

- Xcode-Projekt, SwiftUI-Tab-Navigation, Design Tokens, SwiftData-Versionierung.
- Domain-Modelle für Gear, Installationen, Aktivitäten und Zuordnungen.
- Sportkatalog und Basistemplates für **alle v1-Sportkategorien**.
- Unit-Tests für Montage, Zeitintervalle und Nutzungsledger.

**DoD:** komplette Ausrüstung lokal anlegen/archivieren; mehrere Sportarten nutzbar; Basis-Tests grün.

### Phase 1 — Aktivitäten und Zuordnung

- HealthKit-Onboarding, Erstimport und Anchored/Observer-Mechanismus.
- Idempotenter Import inkl. Änderungen/Löschungen.
- Regelbasierte Assignment Engine, manuelle Zuordnung, Mehrfachzuordnung, Posteingang.
- Rückwirkende Neubewertung der Nutzungsstände.

**DoD:** ein neues Training kann automatisch zugeordnet oder reproduzierbar zur Prüfung vorgelegt werden. Es gibt keine doppelten Nutzungsbeiträge.

### Phase 2 — Wartung und Komponenten

- Teilevorlagen, Montage, Umbau, Austausch, Historie.
- Schnellaktionen, Messwerte, individuelle Wartungsintervalle.
- Wartungshinweise auf Dashboard und Detailseiten.

**DoD:** Wechsel einer Kette ist historisch konsistent; Wartung ist ohne Formularzwang erfassbar.

### Phase 3 — Proaktive UX

- Lokale, interaktive Benachrichtigungen; Ruhezeiten, Deduplizierung.
- ActivityKit/WidgetKit und App-Intents für zulässige Live-Activity-Abläufe.
- Nachweisbarer Fallback bei Hintergrund-/Live-Activity-Einschränkungen.

**DoD:** Benachrichtigungsfreigabe ist optional; offene Zuordnungen gehen nie verloren; wiederholte Aktionen sind sicher.

### Phase 4 — Produktreife

- Import/Export, Fehlerbehandlung, Performance, Lokalisierung, Accessibility.
- Tests auf realen Geräten; App-Store-Datenschutz- und HealthKit-Review-Check.
- Einfache Kostenansicht und Verlauf, sofern Daten vorhanden.

**DoD:** Offline-First durchgängig; Datenwiederherstellung geprüft; alle Kernflows testbar; keine Backend-Abhängigkeit.

---

## 16. Bewusst vertagte Erweiterungen

- Optionales CloudKit/iCloud-Sync mit Konfliktauflösung.
- Weitere Sportarten-spezifische Spezialmetriken.
- Automatische Ausrüstungsvorschläge aus On-Device-Lernverfahren/Core ML **erst nach** fundierter Datenerhebung und Evaluation.
- Barcode-/Fotoerkennung für Produktkataloge (würde ggf. Online-Produktdaten erfordern; nicht Kernfunktion).
- Siri/Shortcuts-Ausbau, Watch-App, Home-Screen-Widgets.
- Erweiterte Kostenrechnung, Belegverwaltung, Garantie- und Serviceunterlagen.
- Direkte Drittanbieter-APIs nach separater Prüfung von Authentifizierung, API-Regeln und Backendfreiheit.

---

## 17. Offene Entscheidungen (mit empfohlenen Defaults)

| Entscheidung | Vorgabe für Start |
| --- | --- |
| Produktname/Bundle ID | Arbeitstitel GearFlow; final später |
| Deployment Target | iOS 18+ prüfen und festschreiben |
| UI-Sprachen | Deutsch + Englisch |
| Erster HealthKit-Import | Letzte 90 Tage, änderbar |
| Zuordnungsautomatik | Explizite Regeln automatisch, Heuristik konservativ |
| Mitbenutzte Ausrüstung | Per Preset, nicht automatisch mit Fahrrad implizieren |
| Standardbenachrichtigungen | Nur offene Zuordnungen und aktivierte Wartungshinweise |
| Standard-Intervalle | Keine „echten Verschleißprognosen“ ohne Daten |
| Cloud Sync | Nicht in v1 |
| KI/ML | Nicht in v1 nötig |
| Datenschutz | Lokal, kein Tracking, kein Konto |

---

## 18. Technische Referenzen (primär Apple)

Die folgenden Quellen begründen Plattformgrenzen; bei Implementierung jeweils die Dokumentation der **tatsächlichen Ziel-iOS-Version und Xcode-Version** erneut prüfen.

- HealthKit — Observer Query / Background Delivery: https://developer.apple.com/documentation/healthkit/executing-observer-queries
- HealthKit — Anchored Object Query und Änderungen: https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery
- HealthKit — Zugriffsberechtigungen: https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
- HealthKit — Workout Activity Types: https://developer.apple.com/documentation/healthkit/hkworkoutactivitytype
- ActivityKit — Live Activities und Grenzen: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- App Intents — LiveActivityIntent: https://developer.apple.com/documentation/appintents/liveactivityintent
- UserNotifications — Actionable Notifications: https://developer.apple.com/documentation/usernotifications/handling-notifications-and-notification-related-actions
- SwiftData — ModelContainer: https://developer.apple.com/documentation/swiftdata/modelcontainer
- Strava — OAuth-Anforderungen (nicht MVP): https://developers.strava.com/docs/authentication/

---

## 19. Definition des fertigen MVP in einem Satz

**Ein Nutzer kann beliebige Sportausrüstung aus den wichtigsten Sportarten schnell anlegen, Aktivitäten aus Apple Health ohne Handarbeit importieren, passende Gegenstände einschließlich verbauter Komponenten automatisch belasten, unklare Fälle bequem bestätigen und Wartungen/Wechsel historisch korrekt erfassen — vollständig offline, ohne Account oder Backend.**
