import Testing
import Foundation
@testable import GearCore

private let shoes = id(1), bike = id(2)
private let swim = SportType(rawValue: 46)
private let multisport = SportType(rawValue: 82)

private func item(_ n: UUID, _ category: SportCategory) -> GearItem {
    GearItem(id: n, name: "G\(n.uuidString.suffix(2))", createdAt: day(0), category: category)
}

private func oneShoe() -> GearDataset {
    var d = GearDataset()
    d.gear = [item(shoes, .running)]
    return d
}

private func workout(_ sourceID: String, day n: Int, hours: Double = 1, distance: Double? = 10_000,
                     sport: SportType = run, bundle: String? = "com.example.watch",
                     segments: [IncomingSegment] = []) -> IncomingWorkout {
    IncomingWorkout(sourceID: sourceID, sportType: sport, startAt: day(n),
                    endAt: day(n).addingTimeInterval(hours * 3_600), distanceMeters: distance,
                    durationSeconds: hours * 3_600, sourceBundleID: bundle, sourceName: "Uhr", segments: segments)
}

private func part(_ sport: SportType, day n: Int, from: Double, to: Double, distance: Double? = nil) -> IncomingSegment {
    IncomingSegment(sportType: sport, startAt: day(n).addingTimeInterval(from * 60),
                    endAt: day(n).addingTimeInterval(to * 60), distanceMeters: distance)
}

private func setup(_ dataset: GearDataset = oneShoe(), enabled: Bool = true, since: Date? = nil)
    -> (FakeHealthSource, MemoryImportStore, HealthImporter) {
    let source = FakeHealthSource()
    let store = MemoryImportStore(dataset: dataset, enabled: enabled, since: since)
    return (source, store, HealthImporter(source: source, store: store, now: { day(30) }))
}

private func ledger(_ d: GearDataset) -> [UsageLedgerEntry] { LedgerBuilder.build(d.ledgerInput).entries }
private func live(_ d: GearDataset) -> [ActivityRecord] { d.activities.filter { $0.deletedAt == nil } }

@Suite("HealthImporter gegen Fake-Quelle (M3: T-05, T-06, T-07, T-08)")
struct HealthImporterTests {

    // MARK: T-05

    @Test("T-05: Wiederholte Abgleiche, auch ohne Anker, ändern Anzahl und Nutzungsbeiträge nicht")
    func t05_repeatedSyncIsIdempotent() async {
        let (source, store, importer) = setup()
        await source.put(workout("W1", day: 1), workout("W2", day: 2))
        #expect(await importer.sync() == .success(ImportSummary(inserted: 2)))
        let first = await store.dataset
        #expect(await importer.sync() == .success(ImportSummary()))
        await store.resetAnchor()
        #expect(await importer.sync() == .success(ImportSummary()))
        let after = await store.dataset
        #expect(after == first && live(after).count == 2)
        #expect(ledger(after).count == 2)
        #expect(await source.anchorsSeen == [nil, Data("2".utf8), nil])
    }

    @Test("T-05: Absturz vor dem Commit lässt den Anker stehen; die Wiederholung bucht genau einmal")
    func t05_failedCommitKeepsAnchor() async {
        let (source, store, importer) = setup()
        await source.put(workout("W1", day: 1))
        await store.setCommitFailure(true)
        #expect(await importer.sync() == .failure(.storeError))
        #expect(await store.state.anchor == nil)
        #expect(await store.state.retryPending)
        await store.setCommitFailure(false)
        #expect(await importer.sync() == .success(ImportSummary(inserted: 1)))
        let d = await store.dataset
        #expect(live(d).count == 1 && ledger(d).count == 1)
        #expect(await store.state.anchor != nil)
        #expect(await store.state.lastFailure == nil)
    }

    @Test("T-05: Gleichzeitige Auslöser laufen nacheinander und buchen einmal")
    func t05_concurrentTriggersAreSerialized() async {
        let (source, store, importer) = setup()
        await source.put(workout("W1", day: 1))
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 { group.addTask { _ = await importer.sync() } }
        }
        #expect(await source.maxInFlight == 1)
        #expect(await source.anchorsSeen.count == 5)
        #expect(live(await store.dataset).count == 1)
    }

    @Test("Quellkennung und Quellname werden gespeichert")
    func sourceIsStored() async {
        let (source, store, importer) = setup()
        await source.put(workout("W1", day: 1))
        _ = await importer.sync()
        let a = await store.dataset.activities.first
        #expect(a?.sourceBundleID == "com.example.watch" && a?.sourceName == "Uhr")
    }

    // MARK: T-06

    @Test("T-06: Gleiche UUID mit neuen Werten aktualisiert Dauer und Distanz im Ledger")
    func t06_changedWorkout() async {
        let (source, store, importer) = setup()
        await source.put(workout("W1", day: 1))
        _ = await importer.sync()
        await source.put(workout("W1", day: 1, hours: 2, distance: 21_000))
        #expect(await importer.sync() == .success(ImportSummary(updated: 1)))
        let d = await store.dataset
        #expect(live(d).count == 1)
        #expect(ledger(d).map(\.distanceMeters) == [21_000])
        #expect(ledger(d).map(\.durationSeconds) == [7_200])
    }

    @Test("T-06 Ersatz: Löschen + Neuanlage derselben Quelle übernimmt die Zuordnung")
    func t06_replacementSameSource() async {
        var data = GearDataset()
        data.gear = [item(shoes, .running), item(id(9), .running)]
        data.assignmentRules = [AssignmentRule(sportType: run, gearIDs: [shoes])]
        let (source, store, importer) = setup(data)
        await source.put(workout("W1", day: 1))
        _ = await importer.sync()
        await source.delete("W1")
        await source.put(workout("W1-neu", day: 1, distance: 10_200))
        #expect(await importer.sync() == .success(ImportSummary(inserted: 1, removed: 1)))
        let d = await store.dataset
        #expect(live(d).map(\.sourceID) == ["W1-neu"])
        #expect(ledger(d).map(\.gearID) == [shoes])
        #expect(d.pendings.isEmpty)
    }

    @Test("T-06 Ersatz: Eine andere Quelle ist kein Ersatz, auch bei gleichem Zeitraum (P-05)")
    func t06_otherSourceIsNoReplacement() async throws {
        var data = oneShoe()
        data.gear.append(item(id(9), .running))
        let (source, store, importer) = setup(data)
        await source.put(workout("W1", day: 1))
        _ = await importer.sync()
        var d = await store.dataset
        d.assignments = [ActivityGearAssignment(activityID: try #require(d.activities.first).id, gearID: shoes)]
        d.pendings = []
        await store.replace(d)

        await source.delete("W1")
        await source.put(workout("W2", day: 1, bundle: "com.example.other"))
        _ = await importer.sync()
        let after = await store.dataset
        let new = try #require(live(after).first)
        #expect(!after.assignments.contains { $0.activityID == new.id }, "keine stille Übernahme")
        #expect(ledger(after).isEmpty)
        #expect(after.pendings.filter { $0.activityID == new.id }.count == 1)
    }

    @Test("T-06 Segmente: Update erhält Segment-IDs und deren Zuordnung, neue Distanz wirkt")
    func t06_segmentsUpdate() async throws {
        var data = GearDataset(); data.gear = [item(bike, .cycling)]
        let (source, store, importer) = setup(data)
        func triathlon(rideKm: Double) -> IncomingWorkout {
            workout("T1", day: 1, distance: nil, sport: multisport,
                    segments: [part(swim, day: 1, from: 0, to: 20), part(cycling, day: 1, from: 20, to: 60, distance: rideKm)])
        }
        await source.put(triathlon(rideKm: 20_000))
        _ = await importer.sync()
        var d = await store.dataset
        let ride = try #require(d.segments.first { $0.sportType == cycling })
        d.assignments = [ActivityGearAssignment(activityID: try #require(d.activities.first).id, segmentID: ride.id, gearID: bike)]
        await store.replace(d)

        await source.put(triathlon(rideKm: 22_000))
        #expect(await importer.sync() == .success(ImportSummary(updated: 1)))
        let after = await store.dataset
        #expect(after.segments.count == 2)
        #expect(after.segments.first { $0.sportType == cycling }?.id == ride.id)
        #expect(ledger(after).map(\.distanceMeters) == [22_000])
    }

    @Test("T-06 Segmente: Fällt ein Segment weg, verschwinden Segment und seine Zuordnung")
    func t06_segmentRemoved() async throws {
        var data = GearDataset(); data.gear = [item(bike, .cycling)]
        let (source, store, importer) = setup(data)
        await source.put(workout("T1", day: 1, distance: nil, sport: multisport,
                                 segments: [part(swim, day: 1, from: 0, to: 20), part(cycling, day: 1, from: 20, to: 60)]))
        _ = await importer.sync()
        var d = await store.dataset
        let ride = try #require(d.segments.first { $0.sportType == cycling })
        d.assignments = [ActivityGearAssignment(activityID: try #require(d.activities.first).id, segmentID: ride.id, gearID: bike)]
        await store.replace(d)
        await source.put(workout("T1", day: 1, distance: nil, sport: multisport,
                                 segments: [part(swim, day: 1, from: 0, to: 20), part(run, day: 1, from: 20, to: 60)]))
        _ = await importer.sync()
        let after = await store.dataset
        #expect(Set(after.segments.map(\.sportType)) == [swim, run])
        #expect(after.assignments.isEmpty && ledger(after).isEmpty)
    }

    @Test("T-06 Ersatz mit Segmenten: Die Segmentzuordnung wandert zum passenden neuen Segment")
    func t06_replacementCarriesSegments() async throws {
        var data = GearDataset(); data.gear = [item(bike, .cycling)]
        let (source, store, importer) = setup(data)
        let parts = [part(swim, day: 1, from: 0, to: 20), part(cycling, day: 1, from: 20, to: 60, distance: 20_000)]
        await source.put(workout("T1", day: 1, distance: nil, sport: multisport, segments: parts))
        _ = await importer.sync()
        var d = await store.dataset
        let ride = try #require(d.segments.first { $0.sportType == cycling })
        d.assignments = [ActivityGearAssignment(activityID: try #require(d.activities.first).id, segmentID: ride.id, gearID: bike)]
        d.pendings = []
        await store.replace(d)
        await source.delete("T1")
        await source.put(workout("T1-neu", day: 1, distance: nil, sport: multisport, segments: parts))
        _ = await importer.sync()
        let after = await store.dataset
        let new = try #require(live(after).first)
        let newRide = try #require(after.segments.first { $0.activityID == new.id && $0.sportType == cycling })
        let entries = ledger(after)
        #expect(entries.count == 1)
        #expect(entries.first?.activityID == new.id && entries.first?.segmentID == newRide.id)
    }

    // MARK: T-07

    @Test("T-07: Gemeldete Löschung entfernt Ledger-Einträge und schließt den Posteingang, nicht die Ausrüstung")
    func t07_deletion() async {
        var data = oneShoe()
        data.gear.append(item(id(9), .running))
        data.assignmentRules = [AssignmentRule(sportType: cycling, gearIDs: [shoes])]
        let (source, store, importer) = setup(data)
        await source.put(workout("W1", day: 1), workout("R1", day: 2, sport: cycling))
        _ = await importer.sync()
        #expect(ledger(await store.dataset).count == 1)
        #expect(await store.dataset.pendings.count == 1)
        await source.delete("W1", "R1")
        #expect(await importer.sync() == .success(ImportSummary(removed: 2)))
        let d = await store.dataset
        #expect(live(d).isEmpty && ledger(d).isEmpty)
        #expect(d.pendings.map(\.state) == [.obsolete])
        #expect(d.gear.count == 2)
    }

    @Test("T-07: Leere Antworten löschen nie (SPEC 11, 6.1 Punkt 7)")
    func t07_emptyResultDeletesNothing() async {
        let (source, store, importer) = setup()
        await source.put(workout("W1", day: 1))
        _ = await importer.sync()
        await store.enable(since: day(10))
        await store.resetAnchor()
        #expect(await importer.sync() == .success(ImportSummary()))
        #expect(live(await store.dataset).count == 1)
    }

    // MARK: T-08

    @Test("T-08: Multisport ohne Segmentdistanz → keine erfundene Distanz, keine Verteilung nach Dauer")
    func t08_multisportWithoutSegmentDistance() async throws {
        var data = GearDataset(); data.gear = [item(bike, .cycling)]
        let (source, store, importer) = setup(data)
        await source.put(workout("T1", day: 1, distance: 40_000, sport: multisport,
                                 segments: [part(swim, day: 1, from: 0, to: 20), part(cycling, day: 1, from: 20, to: 60)]))
        _ = await importer.sync()
        var d = await store.dataset
        #expect(d.segments.count == 2)
        #expect(d.segments.allSatisfy { $0.distanceMeters == nil })
        let ride = try #require(d.segments.first { $0.sportType == cycling })
        d.assignments = [ActivityGearAssignment(activityID: try #require(d.activities.first).id, segmentID: ride.id, gearID: bike)]
        let entry = try #require(ledger(d).first)
        #expect(entry.distanceMeters == nil && entry.durationSeconds == 2_400)
    }

    @Test("T-08: Segmente entstehen nur bei verschiedenen Sportarten, sortiert nach Beginn; Intervalle bleiben eine Aktivität")
    func t08_segmentNormalization() {
        let a = part(swim, day: 1, from: 0, to: 20), b = part(cycling, day: 1, from: 20, to: 60)
        #expect(IncomingWorkout.multisportSegments([b, a]) == [a, b])
        #expect(IncomingWorkout.multisportSegments([a]) == [])
        #expect(IncomingWorkout.multisportSegments([part(run, day: 1, from: 0, to: 10), part(run, day: 1, from: 10, to: 20)]) == [])
    }

    // MARK: Verbindung, Zeitraum, Sperre

    @Test("Ohne Verbindung wird Health nicht angefasst")
    func disabledDoesNothing() async {
        let (source, _, importer) = setup(enabled: false)
        await importer.start()
        #expect(await importer.sync() == .disabled)
        #expect(await source.anchorsSeen.isEmpty)
        #expect(await source.observerRegistrations == 0)
    }

    @Test("Der gewählte Zeitraum geht an die Quelle; ältere Trainings kommen nicht")
    func windowIsPassed() async {
        let (source, store, importer) = setup(since: day(10))
        await source.put(workout("alt", day: 1), workout("neu", day: 20))
        _ = await importer.sync()
        #expect(await source.sinceSeen == [day(10)])
        #expect(live(await store.dataset).map(\.sourceID) == ["neu"])
    }

    @Test("Zeitraumwahl: Vorgabe 90 Tage, „alle“ ohne Startdatum")
    func importWindow() {
        #expect(ImportWindow.standard == .days90)
        #expect(ImportWindow.allCases == [.days30, .days90, .days365, .all])
        #expect(ImportWindow.days90.startDate(now: day(100)) == day(10))
        #expect(ImportWindow.all.startDate(now: day(100)) == nil)
        #expect(ImportWindow.allCases.allSatisfy { ImportWindow(days: $0.days) == $0 })
    }

    @Test("Gesperrt: Import bleibt ausstehend und läuft nach dem Entsperren nach")
    func lockedIsRetried() async {
        let (source, store, importer) = setup()
        await source.put(workout("W1", day: 1))
        await source.fail(with: .databaseInaccessible)
        #expect(await importer.sync() == .failure(.locked))
        #expect(await store.state.retryPending)
        #expect(await store.state.anchor == nil)
        await source.fail(with: nil)
        #expect(await importer.retryIfPending() == .success(ImportSummary(inserted: 1)))
        #expect(await importer.retryIfPending() == nil, "nichts mehr ausstehend")
    }

    @Test("Nicht verfügbar und sonstige Fehler werden gemerkt, nicht verschluckt")
    func otherFailures() async {
        let (source, store, importer) = setup()
        await source.fail(with: .unavailable)
        #expect(await importer.sync() == .failure(.unavailable))
        #expect(await store.state.lastFailure == .unavailable)
        #expect(await !store.state.retryPending)
        await source.fail(with: .failed("x"))
        #expect(await importer.sync() == .failure(.sourceError))
        #expect(await store.state.retryPending)
        await store.setStateFailure(true)
        #expect(await importer.sync() == .failure(.storeError))
    }

    @Test("Verbinden fragt zuerst die Leseberechtigung an")
    func authorization() async throws {
        let (source, _, importer) = setup(enabled: false)
        try await importer.requestAuthorization()
        #expect(await source.authorizationRequests == 1)
    }

    // MARK: Observer (Completion-Handler in allen Pfaden, F-02)

    @Test("Start registriert den Observer einmal je Prozess und gleicht ab")
    func startObservesOnce() async {
        let (source, store, importer) = setup()
        await source.put(workout("W1", day: 1))
        await importer.start()
        await importer.start()
        #expect(await source.observerRegistrations == 1)
        #expect(live(await store.dataset).count == 1)
    }

    @Test("Observer: Weckruf gleicht ab und ruft den Completion-Handler")
    func observerSyncs() async {
        let (source, store, importer) = setup()
        await importer.start()
        await source.put(workout("W1", day: 1))
        #expect(await source.fireObserver())
        #expect(live(await store.dataset).count == 1)
    }

    @Test("Observer: Completion-Handler auch bei Observer-Fehler, Sperre, Quellfehler und Speicherfehler")
    func observerCompletesOnEveryPath() async {
        let (source, store, importer) = setup()
        await importer.start()
        // Jeder Aufruf kehrt nur zurück, wenn der Completion-Handler gerufen wurde.
        #expect(await source.fireObserver(error: .databaseInaccessible))
        #expect(await store.state.lastFailure == .locked)
        #expect(await source.fireObserver(error: .failed("x")))
        #expect(await store.state.lastFailure == .sourceError)
        await source.fail(with: .databaseInaccessible)
        #expect(await source.fireObserver())
        await source.fail(with: nil)
        await store.setCommitFailure(true)
        await source.put(workout("W1", day: 1))
        #expect(await source.fireObserver())
        #expect(await store.state.lastFailure == .storeError)
        await store.setStateFailure(true)
        #expect(await source.fireObserver())
    }

    @Test("Registrierung fehlgeschlagen: beim nächsten Start erneut")
    func observerRegistrationRetried() async {
        let (source, _, importer) = setup()
        await source.fail(with: .unavailable)
        await importer.start()
        await source.fail(with: nil)
        await importer.start()
        #expect(await source.observerRegistrations == 2)
        #expect(await source.fireObserver())
    }

    // MARK: Status ohne Fehldiagnose

    @Test("Status: leere Ergebnisse heißen „keine Trainings sichtbar“, nie verweigert")
    func status() {
        var s = ImportState(isEnabled: false)
        #expect(ImportStatus.evaluate(s, workoutCount: 0) == .notConnected)
        s.isEnabled = true
        #expect(ImportStatus.evaluate(s, workoutCount: 0) == .waiting)
        s.lastSuccessAt = day(1)
        #expect(ImportStatus.evaluate(s, workoutCount: 0) == .noWorkoutsVisible)
        #expect(ImportStatus.evaluate(s, workoutCount: 3) == .upToDate)
        s.lastFailure = .locked
        s.retryPending = true
        #expect(ImportStatus.evaluate(s, workoutCount: 3) == .pendingUnlock)
        s.lastFailure = .sourceError
        #expect(ImportStatus.evaluate(s, workoutCount: 3) == .failed(.sourceError))
    }

    @Test("Distanztyp je Sportart (F-06); ohne passenden Typ keine Distanz")
    func distanceKinds() {
        let expected: [Int: WorkoutDistanceKind] = [
            13: .cycling, 74: .cycling, 37: .walkingRunning, 52: .walkingRunning, 24: .walkingRunning,
            70: .wheelchair, 71: .wheelchair, 46: .swimming, 61: .downhillSnowSports, 67: .downhillSnowSports,
            60: .crossCountrySkiing, 31: .paddleSports, 35: .rowing, 39: .skatingSports,
        ]
        for (raw, kind) in expected { #expect(WorkoutDistanceKind.of(SportType(rawValue: raw)) == kind, "Typ \(raw)") }
        for raw in [20, 50, 82, 83, 3000, 99_999] { #expect(WorkoutDistanceKind.of(SportType(rawValue: raw)) == nil) }
    }
}
