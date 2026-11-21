# Apple-Plattformvorgaben (geprüft 21.11.2026)

Quelle: offizielle Apple-Dokumentation (developer.apple.com, App Review Guidelines), Recherche durch einen Sonnet-Agenten, ausgewertet von Opus. Belegtabellen mit URLs und Belegqualität (W wörtlich, S sinngemäß, N nicht gefunden) stehen unten. Vor jedem Meilenstein gegen die tatsächliche Ziel-iOS- und Xcode-Version erneut prüfen (Spec 18).

## Auswirkungen auf Architektur und Plan

| Nr | Befund (Beleg) | Umsetzung |
|---|---|---|
| F-01 | Background Delivery braucht Entitlement `com.apple.developer.healthkit.background-delivery` (W). Frequenz `immediate` für Workouts auf iOS **nicht dokumentiert** (N); manche Typen werden still auf stündlich begrenzt (W). | Entitlement in M3. Texte und Tests gehen von „irgendwann“ aus. Spike S-1 misst die echte Verzögerung. Keine Echtzeitzusage (Spec 6.1). |
| F-02 | Observer-Queries in `didFinishLaunching` registrieren, Completion-Handler **immer** aufrufen; nach drei Fehlschlägen stellt HealthKit die Zustellung ein (W). | `HealthImportService.start()` als erster Schritt im App-Delegate (SwiftUI `@UIApplicationDelegateAdaptor`); Completion-Handler auch im Fehlerfall; bei jedem Start `enableBackgroundDelivery` erneut. Test: Handler-Aufruf in allen Pfaden (Fake). |
| F-03 | Gesperrtes Gerät: Lesen im Hintergrund kann mit `errorDatabaseInaccessible` scheitern (W); ob HealthKit nach dem Entsperren erneut weckt, ist offen (N). | „Import ausstehend“ merken, bei `UIApplication.protectedDataDidBecomeAvailableNotification`, Vordergrund und App-Start nachholen (ARCHITEKTUR 5.2). Completion-Handler trotzdem aufrufen (F-02). |
| F-04 | Verweigerter Lesezugriff ist nicht erkennbar; „keine Daten“ und „verweigert“ sehen gleich aus (W). Limited Access: `getEarliestAuthorizedSampleDate` (W). | Neutrale Texte („Keine Trainings sichtbar – Zugriff in Health prüfen“), nie „verweigert“ (Spec 6.1/11). Frühestes erlaubtes Datum in den Einstellungen anzeigen. |
| F-05 | `HKDeletedObject` ist nur temporär verfügbar (W). `HKWorkout` ist unveränderlich (W); „Änderung = Löschen + Neuanlage mit neuer UUID“ nur abgeleitet (S). | Observer + Anchored Query als Pflichtweg; Ersatz-Erkennung P-05; Voll-Abgleich markiert nur `missingInSourceSince`, löscht nie (ARCHITEKTUR 5.4). T-06 testet beide Fälle (gleiche UUID mit neuen Werten, Ersatz mit neuer UUID). |
| F-06 | `HKWorkout.totalDistance` ist deprecated (Doku-Stand 27.3); Ersatz `statistics(for:)` (iOS 16+), `nil` ohne Werte (W). `workoutActivities` modelliert Multisport (W). | Mapper wählt den Distanztyp je Sportart (z. B. `distanceCycling`, `distanceWalkingRunning`, `distanceSwimming`, `distanceDownhillSnowSports`, `distancePaddleSports`, `distanceRowing`, `distanceCrossCountrySkiing`); kein Treffer → `nil`. Segmente aus `workoutActivities`, Distanz je Segment nur aus deren Statistik. |
| F-07 | Live Activity: Start nur im Vordergrund **oder** über ein `LiveActivityIntent`; Update/Ende im Hintergrund erlaubt (W). Ein Start aus HealthKit-Background-Delivery ohne APNs ist nicht vorgesehen (S). | Start bei Vordergrund (wenn offene Zuordnungen existieren und LA erlaubt), danach Updates/Ende aus jedem Hintergrund-Commit (Import-Wake, Notification-Aktion). Zusätzlicher zulässiger Startweg in S-2 prüfen: `LiveActivityIntent` über Kurzbefehl/Steuerelement. Hauptweg bleibt die Benachrichtigung (Spec 7.3). |
| F-08 | `LiveActivityIntent.perform()` läuft im App-Prozess, App wird ohne Öffnen gestartet; Intent-Typen gehören in App- **und** Extension-Target (W). Buttons sind bei gesperrtem Gerät inaktiv (W). | Bestätigt A-05: kein App-Group-Store nötig, Intent schreibt über `PersistenceActor`. |
| F-09 | Live-Activity-Grenzen: 8 h aktiv + bis 4 h Sperrbildschirm, 4 KB Daten, Nutzer kann abschalten (`areActivitiesEnabled`) (W). | ContentState klein (IDs, Kurztexte, ≤ 2 Kandidaten); vor `request` Berechtigung prüfen; Ende spätestens bei leerem Posteingang. |
| F-10 | Notification-Aktionen: bei wenig Platz höchstens **zwei** sichtbar, sonst bis 10 (W). Aktion ohne `.foreground` startet die App im Hintergrund, Zeitbudget undokumentiert (W/N). `.authenticationRequired` verlangt Entsperren (W). | Reihenfolge: „Vorschlag übernehmen“, „Andere auswählen“ (foreground, Deep Link), dann „Später“. Bestätigen ist eine kurze Transaktion ohne HealthKit-Zugriff. Abwägung Entsperren siehe P-06 unten. |
| F-11 | Provisional Authorization liefert nur still ins Mitteilungszentrum (W). | Reguläre Berechtigung kontextbezogen (Spec S01); provisional nicht als Ersatz. |
| F-12 | `BGAppRefreshTask`: ca. 30 s, kein garantierter Zeitpunkt, ein Request gleichzeitig; `submit` ab 27.0 deprecated (W). | Nur Zusatzanstoß für Abgleich und Wartungserinnerungen; API je nach Deployment Target wählen. |
| F-13 | App Review 5.1.3(ii): „may not store personal health information in iCloud“ (W). | V1 unkritisch. **Wichtig für die vertagte CloudKit-Option (Spec 10.6/16):** Workout-abgeleitete Daten fallen voraussichtlich darunter; ein späterer Sync braucht vorab eine Klärung, was synchronisiert werden darf. Export bleibt ausdrückliche Nutzeraktion. |
| F-14 | Privacy Manifest für App **und** Extension; UserDefaults `CA92.1`, Datei-Zeitstempel `C617.1`; Datenschutzerklärung für HealthKit-Apps Pflicht (W). `NSHealthShareUsageDescription` zum Lesen (W); ob `NSHealthUpdateUsageDescription` bei reinem Lesen entfallen darf, ist nicht ausdrücklich belegt (N). | M9-Checkliste. Nur Lese-Key setzen; in M3 prüfen, ob das ohne Absturz/Review-Hinweis geht. Datenschutzerklärung vorbereiten (Lino veröffentlicht). |
| F-15 | SwiftData: `VersionedSchema`/`SchemaMigrationPlan` (W); prozessübergreifende Konsistenz App/Extension nicht dokumentiert (N). | Bestätigt A-03/A-05: ein Prozess, ein Schreiber. |

**P-06 (Dateischutz, Entscheidung):** Der Store bleibt bei `completeUntilFirstUserAuthentication`, die Aktion „Vorschlag übernehmen“ läuft **ohne** `.authenticationRequired`. Grund: Spec 13 verlangt den Ein-Tap-Fall, die Aktion schreibt nur die eigene Datenbank (kein HealthKit), und der Sperrbildschirm zeigt ohnehin nur Sportart, Dauer und Ausrüstungsname. Umkehrbar: Wird stärkerer Schutz gewünscht, bekommen Aktionen `.authenticationRequired` und der Store `complete`; dann entfällt der Ein-Tap bei gesperrtem Gerät.

## Offene Punkte für die Gerätespikes
- S-1: tatsächliche Verzögerung von Background Delivery für Workouts (Watch, iPhone, Drittquelle), Verhalten nach Force-Quit und Neustart, Wiederaufnahme nach Entsperren.
- S-1: Darf `NSHealthUpdateUsageDescription` fehlen, wenn nur gelesen wird?
- S-2: Start einer Live Activity per `LiveActivityIntent` aus Kurzbefehl/Steuerelement; Laufzeit für `Activity.update` nach HealthKit-Wake und nach Notification-Aktion.
- S-2: Zeitbudget der Notification-Aktion im Hintergrund (Messung mit OSLog-Signposts).

---

# Belegtabellen (Recherche-Rohfassung)


Quellen: ausschließlich developer.apple.com. Abgerufen über die JSON-Fassung der Doku (`https://developer.apple.com/tutorials/data/documentation/<pfad>.json`); die URLs unten sind die normalen Doku-URLs `https://developer.apple.com/documentation/<pfad>`.
Belegqualität: **W** = wörtlich/nahezu wörtlich belegt, **S** = sinngemäß/abgeleitet aus Doku, **N** = in der offiziellen Doku nicht gefunden.
Hinweis: Die abgerufene Doku zeigt teils Deprecation-Stände "27.0/27.3" (Beta-/aktueller Stand); iOS-26-Aussagen daher mit Versionsangabe der Seite.

### A HealthKit

#### 1. Background Delivery

| Aussage | Quelle | Beleg |
|---|---|---|
| Ab iOS 15/watchOS 8 muss das Entitlement `com.apple.developer.healthkit.background-delivery` gesetzt sein; ohne fehlt, scheitert `enableBackgroundDelivery` mit `errorAuthorizationDenied`. | /documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:) | W |
| Entitlement-Seite: Boolean, "observer queries receive updates while running in the background", Default `false`, iOS 15+. | /documentation/bundleresources/entitlements/com.apple.developer.healthkit.background-delivery | W |
| HealthKit weckt die App, wenn ein Prozess Samples des Typs speichert oder löscht; höchstens einmal pro Zeitraum der Frequenz. Manche Typen sind auf hourly begrenzt, "enforced transparently". Beispiel: `stepCount` auf iOS hourly. | gleiche Seite | W |
| Frequenz `immediate` für **HKWorkoutType auf iOS**: Die Doku nennt `immediate` nur als Ausnahmeliste für **watchOS** (Herzfrequenz-Events, vo2Max, Handwashing usw.); Workouts stehen nicht darin. Ob iOS für Workouts `immediate` oder hourly liefert, ist **nicht dokumentiert**. | gleiche Seite | N (für Workout/iOS) |
| Observer-Queries sind im `application(_:didFinishLaunchingWithOptions:)` aufzusetzen; HealthKit ruft beim Start den Update-Handler passender Observer sofort auf. | gleiche Seite | W |
| Der Completion-Handler der Observer-Query muss nach Verarbeitung aufgerufen werden. Sonst Backoff-Algorithmus mit wachsender Verzögerung; nach drei Fehlschlägen nimmt HealthKit an, die App kann keine Daten empfangen, und stellt Background Updates ein. | gleiche Seite + /documentation/healthkit/hkobserverquerycompletionhandler | W |
| Zustellung bei beendeter App: "HealthKit wakes your app" / "As soon as your app launches" legt nahe, dass die App im Hintergrund gestartet wird; ausdrücklich "App wurde vom User beendet (Force-Quit)" wird nicht behandelt. | gleiche Seite | S (Force-Quit: N) |
| Background Queries gehen nicht im Simulator, nur am Gerät. | gleiche Seite, HKObserverQuery | W |
| Observer liefert bei Löschungen keine Liste; dafür ist im Handler eine `HKAnchoredObjectQuery` zu starten. | /documentation/healthkit/hkdeletedobject | W |
| Der Observer-Update-Handler wird auch bei Änderungen durch andere Apps/Geräte ausgelöst ("respond to changes made by other apps and devices"). | /documentation/healthkit/hkobserverquery | W |

#### 2. Gesperrtes Gerät

| Aussage | Quelle | Beleg |
|---|---|---|
| Das Gerät verschlüsselt den HealthKit-Store bei Sperre; "your app may not be able to read data from the store when it runs in the background". Schreiben bleibt möglich (zwischengespeichert, Merge nach Entsperren). | /documentation/healthkit/protecting-user-privacy | W |
| `HKError.Code.errorDatabaseInaccessible`: "HealthKit data is unavailable because it's protected and the device is locked"; Fehler tritt auf, wenn die App bei gesperrtem Gerät abfragt. | /documentation/healthkit/hkerror/code/errordatabaseinaccessible | W |
| Konsequenz: Background-Delivery-Weckruf bei gesperrtem Gerät kann zwar kommen, der Read-Zugriff darf scheitern. Dokumentiert ist nur die Fehlersituation; die Doku sagt nicht, ob dann ein erneuter Weckruf nach dem Entsperren erfolgt. Der Import muss daher idempotent per Anchor nachholen (App-Start, Entsperren, Foreground). | – | S (Nachhol-Verhalten: N) |
| `isProtectedDataAvailable`/Protected-Data-Notifications für HealthKit: unter den erwarteten Pfaden in der Doku-JSON nicht auffindbar (404). Ggf. `UIApplication.protectedDataDidBecomeAvailableNotification` nutzen; hier nicht verifiziert. | – | N |

#### 3. Leseberechtigung

| Aussage | Quelle | Beleg |
|---|---|---|
| Die App kann nicht erfahren, ob Lesezugriff verweigert wurde; verweigert = "es sieht aus, als gäbe es keine Daten dieses Typs". `authorizationStatus(for:)` betrifft nur Schreibzugriff. | /documentation/healthkit/protecting-user-privacy, /documentation/healthkit/hkhealthstore/authorizationstatus(for:) | W |
| Bei Limited Access (begrenztes Zeitfenster) lässt sich das früheste erlaubte Datum abfragen (`getEarliestAuthorizedSampleDate(for:completion:)`), aber "full access" und "denied" sind für die App nicht unterscheidbar. | /documentation/healthkit/authorizing-access-to-health-data | W (Methodenname aus Referenzliste der HKHealthStore-Seite) |
| `getRequestStatusForAuthorization(toShare:read:completion:)` (iOS 12+): zeigt, ob das System das Berechtigungsblatt zeigen würde (also ob schon gefragt wurde). Es sagt nichts über Gewährt/Verweigert. | /documentation/healthkit/hkhealthstore/getrequeststatusforauthorization(toshare:read:completion:) | W (Abstract), Schlussfolgerung S |
| Pflicht-Info.plist: `NSHealthShareUsageDescription` zum Lesen, `NSHealthUpdateUsageDescription` zum Schreiben; ohne Beschreibung Absturz beim Authorization-Request. Doku: "Xcode requires separate custom messages for reading and writing". Ob `NSHealthUpdateUsageDescription` bei reinem Lesen entfallen kann, steht nicht ausdrücklich da (Formulierung: "to read" / "to write"). | /documentation/healthkit/protecting-user-privacy, /documentation/healthkit/authorizing-access-to-health-data | W / S (reines Lesen ohne Update-Key: N, nicht ausdrücklich bestätigt) |
| Capability "HealthKit" in Xcode; Xcode fügt `healthkit` zu Required Device Capabilities hinzu. "Clinical Health Records" nur bei Bedarf (Rejection-Risiko). `isHealthDataAvailable()` vor jedem Aufruf prüfen. | /documentation/healthkit/setting-up-healthkit | W |
| Datenschutzerklärung ist für jede HealthKit-App Pflicht; HealthKit-Daten nicht für Werbung, nicht an Dritte ohne Zustimmung, nicht verkaufen. | /documentation/healthkit/protecting-user-privacy | W |

#### 4. HKAnchoredObjectQuery, Workouts

| Aussage | Quelle | Beleg |
|---|---|---|
| Anchored Query liefert Anker "of the last sample or deleted object"; Folgeabfragen mit diesem Anker liefern nur neuere gespeicherte/gelöschte Objekte. Anchor `nil` = Snapshot. Anchor-Persistenz selbst (`NSKeyedArchiver`, `HKQueryAnchor` ist `NSSecureCoding`) ist hier nicht in den abgerufenen Seiten ausgeführt. | /documentation/healthkit/hkanchoredobjectquery | W (Anchor), S (Archivierung) |
| `HKDeletedObject` wird per Anchored Query geliefert, aber "deleted objects are temporary; the system may remove them at any time". Garantie für alle Löschungen nur über Observer + Background Delivery + Anchored Query im Handler. | /documentation/healthkit/hkdeletedobject | W |
| `HKWorkout` ist "mostly immutable"; Eigenschaften nicht änderbar, man kann nur Samples hinzufügen. | /documentation/healthkit/hkworkout | W |
| "Workout nachträglich geändert" = Löschen + Neuanlage mit neuer UUID: **nicht dokumentiert**. Aus der Unveränderlichkeit folgt S: Änderungen an Metadaten/Typ/Zeit sind nur durch Löschen und neu Speichern möglich (neue UUID, da neues Objekt). Zugehörige Samples dürfen nachträglich ergänzt werden (UUID bleibt). Eine App kann das nur anhand `HKDeletedObject` + neuem Sample erkennen. Eine Zuordnung "alt → neu" ist nicht dokumentiert. | – | S (Mechanismus), N (explizite Aussage) |
| `HKWorkout.totalDistance` und `totalEnergyBurned` sind deprecated (laut Doku-JSON "deprecatedAt 27.3", Hinweis: `statistics(for:)` mit passendem `HKQuantityType` nutzen). Die Initialisierer mit `totalDistance`/`totalEnergyBurned` sind ebenfalls deprecated. | /documentation/healthkit/hkworkout/totaldistance (JSON-Metadaten) | W (JSON-Metadaten) |
| `HKWorkout.statistics(for:)` ab iOS 16: liefert `HKStatistics` aus den dem Workout zugeordneten Quantity-Samples; `nil`, wenn keine passenden Werte. `allStatistics` ebenfalls vorhanden. | /documentation/healthkit/hkworkout/statistics(for:) | W |
| `HKMetadataKeyIndoorWorkout`: Bool, true = drinnen. | /documentation/healthkit/hkmetadatakeyindoorworkout | W |
| `workoutActivities` (iOS 16+): Jedes `HKWorkout` hat mindestens eine `HKWorkoutActivity`; Multisport/Intervalle werden darüber modelliert (Aktivitäten dürfen nicht überlappen, müssen nicht die ganze Dauer abdecken). Filter über `predicateForWorkoutActivities(workoutActivityType:)`; ein `swimBikeRun`-Workout kann Running-Aktivität enthalten. | /documentation/healthkit/hkworkout/workoutactivities, /documentation/healthkit/dividing-a-healthkit-workout-into-activities | W |
| `HKSourceRevision`: Quelle (`HKSource`) plus Version, OS, Produkttyp; nur bei aus dem Store gelesenen Objekten gesetzt. | /documentation/healthkit/hksourcerevision | W |
| `HKWorkoutActivityType`: Die Doku-Seite listet rund 87 Referenzeinträge (u. a. cycling, running, hiking, walking, swimming, rowing, climbing, snowboarding, skatingSports, surfingSports, paddleSports). Eine vollständige Liste war per JSON nicht sauber zu extrahieren; für Mapping-Tabelle direkt in Xcode 26/27 SDK prüfen. | /documentation/healthkit/hkworkoutactivitytype | S |
| Workouts verändern Move/Exercise-Ringe nur mit zugeordneten Active-Energy-Samples (watchOS) bzw. automatisch (iOS). Für die Planung unerheblich. | /documentation/healthkit/hkworkout | W |

#### 5. App Review Guideline 5.1.3 (Health)

| Aussage | Quelle | Beleg |
|---|---|---|
| Wortlaut 5.1.3(ii): "Apps must not write false or inaccurate data into HealthKit or any other medical research or health management apps, and may not store personal health information in iCloud." | https://developer.apple.com/app-store/review/guidelines/ (5.1.3) | W |
| 5.1.3(i): Keine Nutzung/Weitergabe an Dritte von Gesundheits-/Fitnessdaten (inkl. HealthKit, Motion and Fitness) für Werbung, Marketing oder sonstiges Data-Mining, außer zur Verbesserung des Gesundheitsmanagements bzw. Forschung und nur mit Erlaubnis; "You must disclose the specific health data that you are collecting from the device." | gleiche Seite | W |
| Relevanz CloudKit-Sync: Workout-Zuordnungen (Workout-UUID, Typ, Dauer, Distanz, Datum) sind aus HealthKit abgeleitete Gesundheits-/Fitnessdaten. Ein CloudKit/iCloud-Sync dieser Daten läuft in Reibung mit "may not store personal health information in iCloud". Wie Apple "personal health information" im Fitness-Kontext (reine Ausrüstungs-Kilometer) auslegt, ist **nicht dokumentiert**. Das ist eine Reviewer-Auslegungsfrage. Risikoarm: nur Ausrüstungsdaten ohne Workout-Rohdaten syncen. | – | S (Auslegung N) |
| Relevanz JSON-Export: Die Guideline verbietet iCloud-Speicherung; ein vom Nutzer ausgelöster Export (Share Sheet/Dateien) ist darin nicht genannt. Landet die Datei per Nutzerwahl in iCloud Drive, ist das Nutzerentscheidung; dokumentiert wird das nicht. | – | S / N |
| Der Rest von 5.1.3 und der Abschnitt hinter Zeichen 100000 der Guideline-Seite wurden nicht geprüft; für 5.1.1 (Data Collection and Storage) wurde in den gelesenen Teilen keine iCloud-Erwähnung gefunden. | – | Lücke |

### B Hintergrundausführung

#### 6. BGTaskScheduler

| Aussage | Quelle | Beleg |
|---|---|---|
| `BGAppRefreshTask` für kurze Refreshes; benötigt `fetch` in UIBackgroundModes. Das System entscheidet über den Startzeitpunkt und gibt "up to 30 seconds"; danach `setTaskCompleted(success:)`, sonst Beendigung. | /documentation/backgroundtasks/bgapprefreshtask, /documentation/backgroundtasks/choosing-background-strategies-for-your-app | W |
| `earliestBeginDate`: System garantiert den Start zu diesem Datum nicht, nur dass nicht früher gestartet wird. | /documentation/backgroundtasks/bgtaskrequest/earliestbegindate | W |
| Limits: gleichzeitig 1 Refresh-Task und 10 Processing-Tasks geplant; mehr führt zu `tooManyPendingTaskRequests`. Ein erneutes Submit ersetzt den ausstehenden Request. `submit(_:)` ist ab 27.0 deprecated zugunsten `submitTaskRequest(_:completionHandler:)`. | /documentation/backgroundtasks/bgtaskscheduler/submit(_:) | W |
| Info.plist `BGTaskSchedulerPermittedIdentifiers` (Array, Reverse-DNS) nötig; `register` liefert `false`, wenn die ID fehlt. Jede ID braucht einen Handler; Registrierung vor Ende von `applicationDidFinishLaunching`; doppelte Registrierung beendet die App. | /documentation/bundleresources/information-property-list/bgtaskschedulerpermittedidentifiers, /documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:) | W |
| Debug: Start per Debugger nur am Gerät; die privaten Funktionen dürfen nicht im App-Store-Build stehen. | /documentation/backgroundtasks/starting-and-terminating-tasks-during-development | W |
| `BGContinuedProcessingTask` (iOS 26): startet im Vordergrund auf Nutzeraktion, läuft im Hintergrund weiter, System zeigt dafür eine Live Activity mit Cancel; für lange Jobs (Export, Thumbnails), nicht für ereignisgetriebene Aufwachung; Bundle-ID-Prefix im Identifier. Für diese App **nicht passend** (kein Nutzer-getriggerter Langläufer). | /documentation/backgroundtasks/bgcontinuedprocessingtask, /documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados | W |
| Eine feste Häufigkeit/Garantie für Refresh-Tasks nennt die Doku nicht. | – | N |

### C Lokale Notifications

#### 7. Aktionen und Kategorien

| Aussage | Quelle | Beleg |
|---|---|---|
| Anzeige: "When the system has unlimited space, the system displays up to 10 actions. When the system has limited space, the system displays at most two actions." | /documentation/usernotifications/unnotificationcategory | W |
| Aktion ohne `.foreground`: "the system launches your app in the background and calls the delegate's `userNotificationCenter(_:didReceive:withCompletionHandler:)`". Completion-Handler am Ende aufrufen. Konkrete Zeitbudget-Angabe (Sekunden): **nicht dokumentiert**. | /documentation/usernotifications/handling-notifications-and-notification-related-actions | W (Start im Hintergrund), N (Zeit) |
| Kategorien müssen beim Start deklariert werden (`setNotificationCategories`); Delegate muss früh gesetzt sein, sonst werden Aktionen nicht behandelt. | /documentation/usernotifications/declaring-your-actionable-notification-types | W |
| `.authenticationRequired`: "The action can be performed only on an unlocked device"; System fordert zum Entsperren auf, danach wird die App informiert. Sinnvoll, wenn Daten bei gesperrtem Gerät verschlüsselt sind (z. B. HealthKit, SwiftData mit Data Protection). | /documentation/usernotifications/unnotificationactionoptions/authenticationrequired | W |
| `.foreground` bringt App in den Vordergrund (ggf. Entsperren); nicht verwenden, nur um die App nach vorn zu holen. | .../unnotificationactionoptions/foreground | W |
| `threadIdentifier` gruppiert zusammengehörige Notifications. | /documentation/usernotifications/unnotificationcontent/threadidentifier | W |
| `UNNotificationActionIcon` ab iOS 15 (SF Symbols/Template-Bild). | /documentation/usernotifications/unnotificationactionicon | W (Existenz/Version) |
| Textaktion: `UNTextInputNotificationAction`, Text im Response. | /documentation/usernotifications/untextinputnotificationaction | W |
| Provisional Authorization: Option `.provisional` ohne Prompt; Notifications werden still nur im Notification Center geliefert, mit Keep/Turn-Off-Buttons; kein Sound/Banner/Lock Screen. Folgerung: für eine Rückfrage-Notification, die der Nutzer sehen muss, ist provisional ungeeignet. Vor dem Planen immer `getNotificationSettings` prüfen. | /documentation/usernotifications/asking-permission-to-use-notifications | W |
| Interaktive Aktionen bei gesperrtem Gerät mit `authenticationRequired` benötigen Entsperren; bei Doppeltipp auf der Watch wird die erste nicht destruktive Aktion ausgeführt. | UNNotificationCategory-Seite | W |

### D Live Activities / ActivityKit

#### 8. Start

| Aussage | Quelle | Beleg |
|---|---|---|
| "You can update or end a Live Activity while your app is in the background, but you can only start a Live Activity while the app is in the foreground, unless you adopt AppIntents and start the Live Activity using a LiveActivityIntent." | /documentation/activitykit/activity | W |
| Wiederholt: "In general, your app needs to be in the foreground to start a Live Activity. You can update or end ... in the background — for example, by using BackgroundTasks. However, you can start a Live Activity while your app is in the background by using an app intent that conforms to LiveActivityIntent. For example, you might create a control that people place in Control Center." | /documentation/activitykit/displaying-live-data-with-live-activities | W |
| Ohne APNs aus HealthKit Background Delivery starten: **nach Doku nicht möglich**, da die Start-Ausnahme nur über `LiveActivityIntent` (nutzergetriggert, z. B. Control/Button) besteht. Background Delivery ist kein App Intent. Push-to-start (`pushToStartTokenUpdates`) benötigt APNs. Die Doku erwähnt keinen dritten Weg. | beide Seiten oben + .../starting-and-updating-live-activities-with-activitykit-push-notifications | S (Folgerung), Push-to-start W |
| `LiveActivityIntent` (iOS 17+): "To gain permission for starting Live Activities, conform to this protocol... When the system performs the intent, the system launches your app process without opening the app, performs the intent, and starts the Live Activity." Beispiel: Control im Kontrollzentrum. | /documentation/appintents/liveactivityintent | W |
| `LiveActivityStartingIntent` (iOS 16.1) ist deprecated seit 17.0: "Use LiveActivityIntent instead." | /documentation/appintents/liveactivitystartingintent | W |
| iOS 26: `Activity.request(attributes:content:pushType:style:alertConfiguration:start:)` zum Planen auf ein Datum: gilt weiter im Vordergrund; auch hier "you can't do this while your app is in the background, unless ... LiveActivityIntent". Geplante Activities zählen zum Limit gleichzeitiger Activities; `AlertConfiguration` ist Pflicht. Ein geplanter Start wird "even if the app is in the background" ausgeführt, aber die Planung muss vorher im Vordergrund oder per Intent erfolgen. | /documentation/activitykit/activity/request(attributes:content:pushtype:style:alertconfiguration:start:) | W |
| Eine Notification-Aktion (UNNotificationAction ohne foreground) als erlaubter Start-Weg: nicht in der Doku genannt. Ob dort `Activity.request` gelingt, ist **nicht dokumentiert** (eher nein, da App dort im Hintergrund läuft und kein LiveActivityIntent vorliegt). | – | N |

#### 9. LiveActivityIntent / interaktive Buttons

| Aussage | Quelle | Beleg |
|---|---|---|
| Bei `LiveActivityIntent` (und `AudioPlaybackIntent`) läuft der Intent im **Prozess der App**, nicht in der Extension. Die Hauptapp muss die Intent-Typen enthalten (Target-Mitgliedschaft in App und Widget-Extension). | /documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities | W |
| Der App-Prozess wird dafür gestartet, ohne die App zu öffnen (siehe Zitat oben bei LiveActivityIntent). | /documentation/appintents/liveactivityintent | W |
| Buttons/Toggles in Live Activities über `Button(intent:)`/`Toggle(isOn:intent:)`; nur in Lock-Screen- und Expanded-Darstellung; bei gesperrtem Gerät inaktiv ("the system doesn't perform actions unless a person authenticates and unlocks"). In CarPlay führen sie keine Aktionen aus. | adding-interactivity... und displaying-live-data... | W |
| Seit iOS 17 (Protokoll `LiveActivityIntent` introduced 17.0). | /documentation/appintents/liveactivityintent | W |
| `openAppWhenRun` ist ab iOS 26 deprecated; `supportedModes` ersetzt es. | /documentation/appintents/appintent/openappwhenrun | W |

#### 10. Grenzen

| Aussage | Quelle | Beleg |
|---|---|---|
| Max. 8 Stunden aktiv; danach automatisch beendet und aus der Dynamic Island entfernt; bleibt bis zu 4 weitere Stunden auf dem Lock Screen (max. 12 h gesamt). | /documentation/activitykit/displaying-live-data-with-live-activities | W |
| Statische + dynamische Daten (inkl. Updates und Push) zusammen max. 4 KB. | gleiche Seite | W |
| Live Activity hat keinen Netzwerk-/Standardzugriff und eigene Sandbox. | gleiche Seite | W |
| `Activity.update(_:)` und `end(_:dismissalPolicy:)` aus dem Hintergrund erlaubt "for example, by using BackgroundTasks" (also nur, wenn die App überhaupt Laufzeit bekommt); Updates an beendete Activities werden ignoriert. Beim Ende finalen Content mitgeben. | /documentation/activitykit/activity/update(_:), .../end(_:dismissalpolicy:) | W |
| Updates aus der Hintergrund-Delivery-Weckung (HealthKit): Laufzeitfenster dort nicht dokumentiert; Doku nennt nur BackgroundTasks als Beispiel. | – | N |
| `NSSupportsLiveActivities` = YES in der Info.plist der App (iOS 16.1+). Widget-Extension mit `ActivityConfiguration` nötig. | /documentation/bundleresources/information-property-list/nssupportsliveactivities, displaying-live-data... | W |
| `ActivityAuthorizationInfo().areActivitiesEnabled` (synchron) bzw. `activityEnablementUpdates`; Nutzer kann Live Activities pro App in den Einstellungen deaktivieren; `request` wirft dann `ActivityAuthorizationError` (z. B. `denied`). | /documentation/activitykit/activityauthorizationinfo | W |
| Frequenz-Budget: Dokumentiert ist nur ein stündliches Budget für ActivityKit-**Push**-Notifications (`apns-priority` 5/10; `NSSupportsFrequentLiveActivityUpdates` für höhere Rate). Für lokale Updates per `Activity.update` ist kein Budget dokumentiert. | /documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications | W (Push), N (lokal) |
| Die Anzahl gleichzeitiger Live Activities ist begrenzt ("system limits the number of simultaneous ongoing Live Activities"), ohne genaue Zahl; Dynamic Island zeigt je nach Gerät bis zu zwei. | request(...start:)-Seite, displaying-live-data... | W (Existenz), N (Zahl) |

### E SwiftData

#### 11. Store, Actor, Migration

| Aussage | Quelle | Beleg |
|---|---|---|
| App-Group-Store: `ModelConfiguration(... groupContainer:)` mit `.automatic` (primärer Group Container der App), `.identifier(_:)` oder `.none`. Erlaubt gemeinsamen Store für App und Widget-Extension. | /documentation/swiftdata/modelconfiguration/groupcontainer-swift.struct | W |
| `ModelActor`: "mutually-exclusive access to the attributes of a conforming model" (`@ModelActor`-Makro, `DefaultSerialModelExecutor`: führt Storage-Aufgaben auf isoliertem Context aus). Ein Context ist nicht thread-sicher; der Main-Context ist an den MainActor gebunden. | /documentation/swiftdata/modelactor, .../defaultserialmodelexecutor, .../modelcontext | W / S |
| Schema-Versionierung: `VersionedSchema` (Version + Modelle), `SchemaMigrationPlan` (Evolution zwischen Versionen), `MigrationStage` (lightweight/custom). | /documentation/swiftdata/versionedschema, .../schemamigrationplan, .../migrationstage | W (Abstracts) |
| CloudKit-Sync mit SwiftData: iCloud- und Background-Modes (Remote notifications)-Capability nötig; keine Unique Constraints und keine nicht-optionalen Relationships; CloudKit-Schema ist additiv (nach Promotion keine Löschungen/Typänderungen). Basis: `NSPersistentCloudKitContainer`. | /documentation/swiftdata/syncing-model-data-across-a-persons-devices | W |
| Kreuzprozess-Konsistenz (App + Widget schreiben/lesen denselben Store): wird in den abgerufenen Seiten nicht als Garantie beschrieben. Änderungen aus einem anderen Prozess erscheinen nicht automatisch in einem offenen Context; in der Doku nicht ausgeführt. Bekannte Einschränkungen jenseits CloudKit: in den abgerufenen Seiten **nicht gefunden**. Entwicklungsforen-/Praxisberichte nicht Teil der Recherche. | – | N |

### F Privacy

#### 12. Privacy Manifest

| Aussage | Quelle | Beleg |
|---|---|---|
| `PrivacyInfo.xcprivacy` (Pflichtname): Plist mit erhobenen Datentypen und genutzten Required-Reason-APIs; für Apps und SDKs. | /documentation/bundleresources/privacy-manifest-files | W |
| Seit 1. Mai 2024 werden Apps ohne Begründung für Required-Reason-APIs von App Store Connect nicht mehr akzeptiert. Einträge in `NSPrivacyAccessedAPITypes`; Begründung muss zur tatsächlichen Nutzung passen; keine Nutzung für Tracking. Jeder Executable/jede dynamische Bibliothek mit solcher API braucht ein Manifest in ihrem Bundle. | /documentation/bundleresources/describing-use-of-required-reason-api | W |
| Kategorie File Timestamp (`creationDate`, `modificationDate`, `contentModificationDateKey`, `stat` usw.): Reason `C617.1` = Zugriff auf Timestamps/Metadaten von Dateien im App-Container, App-Group-Container oder CloudKit-Container (relevant für SwiftData-Store im Group Container). `3B52.1` = vom Nutzer gewählte Dateien. | /documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons | W |
| Kategorie UserDefaults: Reason `CA92.1` = Lesen/Schreiben von Infos, die nur die App selbst nutzt. `1C8F.1` = nur für Apps/Extensions derselben App Group (Wortlaut: nur Informationen, die nur für Apps/Extensions derselben Group zugänglich sind). Ist der Zugriff aus der App **und** der Widget-Extension, braucht jede Bundle-Einheit mit Zugriff ihr eigenes Manifest. | gleiche Seite | W (1C8F.1 S) |
| Weitere Kategorien: System Boot Time (`35F9.1` u. a., `DDA9.1` nicht aus dem Gerät senden), Disk Space, Active Keyboard. Hier nicht relevant, solange nicht genutzt. | gleiche Seite | S |
| App-Privacy-Angaben (Nutrition Labels) sind ein separater App-Store-Connect-Schritt, wurden hier nicht geprüft. | – | Lücke |

### Folgen für die Planung

1. **Wecken per HealthKit ist nicht garantiert zeitnah.** Background Delivery braucht Entitlement, die Frequenz ist systemseitig begrenzt, `immediate` ist für Workouts auf iOS nicht dokumentiert. Plane mit "irgendwann, evtl. stündlich" und zusätzlich Catch-up bei App-Start/Foreground per persistiertem Anchor.
2. **Observer-Query + Completion-Handler sind Pflicht.** Beim Start (`didFinishLaunching`) registrieren; Handler immer aufrufen, auch im Fehlerfall, sonst nach drei Fehlschlägen Abschaltung der Zustellung. Beim App-Start kontrollieren, ob Background Delivery noch aktiv ist, und `enableBackgroundDelivery` erneut anfordern.
3. **Gesperrtes Gerät ist ein dokumentierter Ausfallfall.** `errorDatabaseInaccessible`: Lesen im Hintergrund kann scheitern. Import idempotent halten (UUID/Anchor), Nachholen beim Entsperren/Öffnen; nicht davon ausgehen, dass HealthKit erneut weckt.
4. **Leseverweigerung ist nicht erkennbar.** "Keine Workouts" und "Zugriff verweigert" sehen gleich aus. UI braucht einen Hinweis/Hilfetext ("Keine Daten – Zugriff in Health prüfen"). Limited Access (Zeitfenster) separat per `getEarliestAuthorizedSampleDate` anzeigen.
5. **Änderung/Löschung von Workouts:** Workouts sind unveränderlich; "Nachträglich geändert" = Löschung + Neuanlage (nur abgeleitet, nicht dokumentiert). Zuordnung zu Ausrüstung muss mit Workout-UUID verknüpft sein, `HKDeletedObject` verarbeiten (nur temporär verfügbar, daher Observer+Anchored Query) und Verwaiste behandeln/erneut matchen (Heuristik über Zeit/Dauer/Quelle).
6. **`totalDistance`/`totalEnergyBurned` auf `HKWorkout` sind deprecated** (laut Doku-Stand 27.3). Für neue Entwicklung `statistics(for:)` (iOS 16+) mit dem passenden Distanz-Quantity-Type nutzen; `workoutActivities` für Multisport beachten.
7. **Live Activity aus dem Hintergrund ohne Server starten: nach Doku nicht vorgesehen.** Start nur im Vordergrund oder über `LiveActivityIntent` (nutzergetriggert, z. B. Control/Button, läuft ohne App-Öffnung). HealthKit-Wake kann höchstens `update`/`end` einer bestehenden Activity ausführen (mit Laufzeitrisiko). Fallback bei Workout-Ende: lokale Notification mit Aktionen; Live Activity erst nach Nutzerinteraktion (Tap/Intent).
8. **Notification-Aktionen:** Max. 2 Aktionen sichtbar bei wenig Platz (bis 10 sonst); ohne `.foreground` wird die App im Hintergrund gestartet (Zeitbudget undokumentiert, Arbeit kurz halten, Completion-Handler aufrufen). `.authenticationRequired` für Aktionen, die in SwiftData/HealthKit schreiben, damit das Gerät entsperrt ist. Textaktion möglich. Provisional liefert nur still ins Notification Center; für Rückfragen nicht ausreichend, besser reguläre Berechtigung nach Kontext erfragen.
9. **BGAppRefreshTask nur als Zusatzmaßnahme:** ~30 s, kein garantierter Zeitpunkt, 1 Refresh-Request gleichzeitig, `fetch` + `BGTaskSchedulerPermittedIdentifiers` nötig. `BGContinuedProcessingTask` (iOS 26) passt nicht zum Fall.
10. **Live-Activity-Grenzen einplanen:** 8 h aktiv, danach bis zu 4 h Lock Screen; ContentState+Attributes zusammen 4 KB; `areActivitiesEnabled` vor `request` prüfen; Nutzer kann pro App abschalten; Interaktionen sind bei gesperrtem Gerät inaktiv.
11. **SwiftData:** Gemeinsamer Store über App Group (`groupContainer`) dokumentiert; Schema von Anfang an mit `VersionedSchema` + `SchemaMigrationPlan` anlegen. Für späteren CloudKit-Sync früh CloudKit-kompatibel modellieren (keine Unique Constraints, Relationships optional), CloudKit-Schema ist additiv. Prozessübergreifende Aktualität (App/Widget/Intent) ist nicht garantiert dokumentiert, daher mit Tests prüfen.
12. **Compliance:** 5.1.3(ii) verbietet "personal health information in iCloud". Vor einem CloudKit-Sync juristisch/Review-seitig klären, was gesynct wird (nur Ausrüstungsdaten oder auch Workout-Bezüge). V1 ohne Sync ist unkritisch. JSON-Export als Nutzeraktion nicht ausdrücklich geregelt. Privacy Manifest mit UserDefaults (`CA92.1`/`1C8F.1`) und File Timestamp (`C617.1`) für App **und** Widget-Extension anlegen; Datenschutzerklärung für HealthKit-Apps ist Pflicht; Zweckbeschreibungen `NSHealthShareUsageDescription` (und `NSHealthUpdateUsageDescription` nur bei Schreibzugriff, nicht ausdrücklich bestätigt).

### Ehrliche Lücken (nicht belegt)

- `immediate`-Frequenz für HKWorkoutType auf iOS (nicht in der Doku).
- Verhalten bei Force-Quit durch den Nutzer; Zeitbudget nach Background-Delivery-Weckung; Aktion ohne `.foreground`: Sekundenbudget.
- Workout-Änderung als Löschen+Neuanlage mit neuer UUID (nur aus "immutable" abgeleitet).
- Ob `Activity.request` aus einem Notification-Action-Handler ohne `LiveActivityIntent` gelingt (Doku: nein im Hintergrund, keine ausdrückliche Aussage zu diesem Pfad).
- Lokales Update-Budget von Live Activities; genaue Zahl gleichzeitiger Activities.
- Prozessübergreifende SwiftData-Konsistenz, bekannte Einschränkungen außerhalb der CloudKit-Liste.
- Vollständige aktuelle `HKWorkoutActivityType`-Liste, restliche Teile der App Review Guidelines (nach Zeichen 100000), App-Privacy-Details in App Store Connect.
- Nutzungshinweis: Apple Developer Forums wurden nicht herangezogen.
