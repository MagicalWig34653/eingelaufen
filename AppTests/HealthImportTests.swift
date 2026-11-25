import Foundation
import GearCore
import HealthKit
import SwiftData
import Testing
@testable import Eingelaufen

private let run = SportCategory.running.defaultSportType
private let cycling = SportCategory.cycling.defaultSportType
private let swim = SportType(rawValue: 46)

private func workout(_ id: String, day n: Double, distance: Double? = 10_000, sport: SportType = run,
                     segments: [IncomingSegment] = []) -> IncomingWorkout {
    IncomingWorkout(sourceID: id, sportType: sport, startAt: day(n), endAt: day(n).addingTimeInterval(3_600),
                    distanceMeters: distance, durationSeconds: 3_600, sourceBundleID: "com.example.watch",
                    sourceName: "Uhr", segments: segments)
}

private func batch(_ workouts: IncomingWorkout..., deleted: [String] = []) -> ImportBatch {
    ImportBatch(upserts: workouts, deletedSourceIDs: deleted)
}

/// Verbundener Speicher mit einem Laufschuh und der Regel „Läufe zählen für diesen Schuh“.
private func connected(_ container: ModelContainer? = nil, rule: Bool = true) async throws -> (PersistenceActor, UUID) {
    let p = if let container { PersistenceActor(modelContainer: container) } else { try makePersistence() }
    let shoe = GearItem(name: "Pegasus", createdAt: day(-200), category: .running)
    var d = GearDataset()
    d.gear = [shoe]
    d.statusChanges = [GearStatusChange(gearID: shoe.id, status: .active, effectiveAt: day(-200))]
    if rule { d.assignmentRules = [AssignmentRule(sportType: run, gearIDs: [shoe.id])] }
    try await p.load(d)
    _ = try await p.apply(.connectHealth(.days90), now: t0)
    return (p, shoe.id)
}

private func importer(_ p: PersistenceActor, _ source: DebugHealthSource) -> HealthImporter {
    HealthImporter(source: source, store: p, now: { day(30) })
}

@Suite struct HealthImportTests {
    // MARK: Verbindung und Zeitraum

    @Test func connectingStoresWindowAndFixedStart() async throws {
        let p = try makePersistence()
        #expect(try await p.importState().isEnabled == false)
        _ = try await p.apply(.connectHealth(.days90), now: t0)
        let s = try await p.settings()
        #expect(s.healthChoice == .connected && s.importWindowDays == 90 && s.healthImportStartAt == day(-90))
        let state = try await p.importState()
        #expect(state.isEnabled && state.since == day(-90) && state.anchor == nil)
    }

    @Test func allWorkoutsHaveNoStartDate() async throws {
        let p = try makePersistence()
        _ = try await p.apply(.connectHealth(.all), now: t0)
        #expect(try await p.settings().importWindowDays == 0)
        #expect(try await p.importState().since == nil)
        #expect(try await p.importState().isEnabled)
    }

    @Test func sameWindowKeepsAnchorChangedWindowResetsIt() async throws {
        let (p, _) = try await connected()
        await importer(p, DebugHealthSource(batches: [batch(workout("W1", day: 1))])).sync()
        let anchor = try await p.importState().anchor
        #expect(anchor != nil)
        _ = try await p.apply(.connectHealth(.days90), now: day(5))
        #expect(try await p.importState().anchor == anchor)
        #expect(try await p.importState().since == day(-90))
        _ = try await p.apply(.connectHealth(.days365), now: day(5))
        #expect(try await p.importState().anchor == nil)
        #expect(try await p.importState().since == day(-360))
        #expect(try await p.dataset().activities.count == 1, "ein anderer Zeitraum löscht nichts")
    }

    @Test func onboardingWithHealthStoresTheChosenWindow() async throws {
        let p = try makePersistence()
        _ = try await p.apply(.completeOnboarding(OnboardingChoice(categories: [.running], health: .connected,
                                                                   importWindow: .days30)), now: t0)
        let s = try await p.settings()
        #expect(s.onboardingCompleted && s.healthChoice == .connected && s.importWindowDays == 30)
        #expect(s.healthImportStartAt == day(-30))
    }

    @Test func onboardingWithLaterStaysDisconnected() async throws {
        let p = try makePersistence()
        _ = try await p.apply(.completeOnboarding(OnboardingChoice(categories: [], health: .later)), now: t0)
        #expect(try await p.importState().isEnabled == false)
        let source = DebugHealthSource(batches: [batch(workout("W1", day: 1))])
        #expect(await importer(p, source).sync() == .disabled)
        #expect(try await p.dataset().activities.isEmpty)
    }

    // MARK: T-05

    @Test func t05_reimportChangesNothingAndAnchorIsPersistedWithTheRecords() async throws {
        let container = try Stores.makeContainer(inMemory: true)
        let (p, shoe) = try await connected(container)
        let same = batch(workout("W1", day: 1), workout("W2", day: 2))
        // Zweimal derselbe Batch, wie nach einem Absturz vor dem Speichern des Ankers.
        let source = DebugHealthSource(batches: [same, same])
        let i = importer(p, source)
        #expect(await i.sync() == .success(ImportSummary(inserted: 2)))
        let reopened = PersistenceActor(modelContainer: container)
        #expect(try await reopened.importState().anchor != nil)
        #expect(try await reopened.importState().lastSuccessAt == day(30))
        let ledger = try await reopened.ledger()
        #expect(await i.sync() == .success(ImportSummary()))
        #expect(try await p.dataset().activities.count == 2)
        #expect(try await p.ledger() == ledger)
        #expect(try await p.usage(of: shoe) == UsageSummary(uses: 2, distanceMeters: .measured(20_000, isComplete: true),
                                                          durationSeconds: .measured(7_200, isComplete: true)))
    }

    @Test func importWritesOutboxAndSourceFields() async throws {
        let (p, _) = try await connected()
        await importer(p, DebugHealthSource(batches: [batch(workout("W1", day: 1))])).sync()
        let a = try #require(try await p.dataset().activities.first)
        #expect(a.source == .healthKit && a.sourceBundleID == "com.example.watch" && a.sourceName == "Uhr")
        #expect(try await p.outbox(pendingOnly: true).contains { $0.kind == .activityChanged && $0.subjectIDs.contains(a.id) })
    }

    /// Erstimport mit vielen Trainings geht den Weg „Ledger vollständig neu“ (mehr als 100 betroffene Aktivitäten).
    @Test func largeFirstImportCountsEveryWorkoutOnce() async throws {
        let (p, shoe) = try await connected()
        let many = (0..<150).map { workout("W\($0)", day: -Double($0) / 3, distance: 1_000) }
        let i = importer(p, DebugHealthSource(batches: [ImportBatch(upserts: many), batch(deleted: ["W0"])]))
        #expect(await i.sync() == .success(ImportSummary(inserted: 150)))
        #expect(try await p.ledger().count == 150)
        #expect(try await p.usage(of: shoe).distanceMeters == .measured(150_000, isComplete: true))
        await i.sync()
        #expect(try await p.usage(of: shoe).distanceMeters == .measured(149_000, isComplete: true))
        let incremental = try await p.ledger()
        try await p.rebuildAll()
        #expect(try await p.ledger() == incremental, "I-10")
    }

    // MARK: T-06

    @Test func t06_sameUUIDUpdatesUsage() async throws {
        let (p, shoe) = try await connected()
        let i = importer(p, DebugHealthSource(batches: [batch(workout("W1", day: 1)),
                                                        batch(workout("W1", day: 1, distance: 21_000))]))
        await i.sync()
        #expect(await i.sync() == .success(ImportSummary(updated: 1)))
        #expect(try await p.dataset().activities.map(\.distanceMeters) == [21_000])
        #expect(try await p.usage(of: shoe).distanceMeters == .measured(21_000, isComplete: true))
    }

    @Test func t06_replacementCountsOnce() async throws {
        let (p, shoe) = try await connected()
        let i = importer(p, DebugHealthSource(batches: [batch(workout("W1", day: 1)),
                                                        batch(workout("W1-neu", day: 1, distance: 10_400), deleted: ["W1"])]))
        await i.sync()
        #expect(await i.sync() == .success(ImportSummary(inserted: 1, removed: 1)))
        let d = try await p.dataset()
        #expect(d.activities.filter { $0.deletedAt == nil }.map(\.sourceID) == ["W1-neu"])
        #expect(try await p.usage(of: shoe) == UsageSummary(uses: 1, distanceMeters: .measured(10_400, isComplete: true),
                                                          durationSeconds: .measured(3_600, isComplete: true)))
    }

    // MARK: T-07

    @Test func t07_deletionRemovesUsageClosesInboxKeepsGear() async throws {
        let (p, shoe) = try await connected()
        let second = GearItem(name: "Rad A", createdAt: day(-200), category: .cycling)
        let third = GearItem(name: "Rad B", createdAt: day(-200), category: .cycling)
        _ = try await p.apply(.createGear(second), now: day(-200))
        _ = try await p.apply(.createGear(third), now: day(-200))
        let i = importer(p, DebugHealthSource(batches: [
            batch(workout("W1", day: 1), workout("R1", day: 2, sport: cycling)),
            batch(deleted: ["W1", "R1", "unbekannt"]),
        ]))
        await i.sync()
        #expect(try await p.dataset().pendings.count == 1)
        #expect(await i.sync() == .success(ImportSummary(removed: 2)))
        let d = try await p.dataset()
        #expect(d.activities.allSatisfy { $0.deletedAt != nil })
        #expect(d.pendings.map(\.state) == [.obsolete])
        #expect(d.gear.count == 3)
        #expect(try await p.ledger().isEmpty)
        // Kern-Konvention: ohne jeden Eintrag ist 0 eine wahre Messung (nichts war zu verbuchen).
        #expect(try await p.usage(of: shoe) == UsageSummary(uses: 0, distanceMeters: .measured(0, isComplete: true),
                                                          durationSeconds: .measured(0, isComplete: true)))
    }

    // MARK: T-08 und Segmente

    @Test func t08_segmentsArePersistedWithoutInventedDistance() async throws {
        let (p, _) = try await connected(rule: false)
        let parts = [IncomingSegment(sportType: swim, startAt: day(1), endAt: day(1).addingTimeInterval(1_200)),
                     IncomingSegment(sportType: cycling, startAt: day(1).addingTimeInterval(1_200),
                                     endAt: day(1).addingTimeInterval(3_600), distanceMeters: 20_000)]
        let multi = workout("T1", day: 1, distance: nil, sport: SportType(rawValue: 82), segments: parts)
        let fewer = workout("T1", day: 1, distance: nil, sport: SportType(rawValue: 82))
        let i = importer(p, DebugHealthSource(batches: [batch(multi), batch(fewer)]))
        await i.sync()
        var d = try await p.dataset()
        #expect(d.segments.count == 2)
        #expect(d.segments.first { $0.sportType == swim }?.distanceMeters == nil)
        #expect(d.activities.first?.distanceMeters == nil)
        await i.sync()
        d = try await p.dataset()
        #expect(d.segments.isEmpty, "weggefallene Segmente verschwinden")
    }

    // MARK: Gesperrt

    @Test func lockedDeviceIsRememberedAndRetried() async throws {
        let (p, _) = try await connected()
        let source = DebugHealthSource(batches: [batch(workout("W1", day: 1))], errors: [.databaseInaccessible])
        let i = importer(p, source)
        #expect(await i.sync() == .failure(.locked))
        var state = try await p.importState()
        #expect(state.retryPending && state.lastFailure == .locked && state.anchor == nil)
        #expect(await i.retryIfPending() == .success(ImportSummary(inserted: 1)))
        state = try await p.importState()
        #expect(!state.retryPending && state.lastFailure == nil && state.lastSuccessAt == day(30))
    }

    @Test func windowChangeDuringAnImportDoesNotStoreTheOldAnchor() async throws {
        let (p, _) = try await connected()
        let before = try await p.importState()
        // Während die Abfrage (alter Zeitraum) läuft, wählt der Nutzer „alle“.
        _ = try await p.apply(.connectHealth(.all), now: day(5))
        _ = try await p.commitImport(WorkoutChanges(batch: batch(workout("W1", day: 1)), anchor: Data("1".utf8)),
                                     since: before.since, now: day(5))
        #expect(try await p.dataset().activities.count == 1)
        #expect(try await p.importState().anchor == nil, "der neue Zeitraum wird vollständig abgefragt")
    }

    // MARK: Texte

    @Test func statusTextsNeverClaimDenial() {
        let all: [ImportStatus] = [.notConnected, .waiting, .pendingUnlock, .noWorkoutsVisible, .upToDate,
                                   .failed(.unavailable), .failed(.sourceError), .failed(.storeError)]
        for status in all {
            let text = HealthTexts.title(status) + " " + (HealthTexts.hint(status) ?? "")
            #expect(!HealthTexts.title(status).isEmpty)
            #expect(!text.lowercased().contains("verweigert") && !text.lowercased().contains("abgelehnt"))
        }
        #expect(HealthTexts.title(.noWorkoutsVisible) == "Keine Trainings sichtbar")
        #expect(HealthTexts.hint(.noWorkoutsVisible)?.contains("Health-App") == true)
        #expect(HealthTexts.title(.pendingUnlock) == "Import ausstehend")
    }

    // MARK: App-Modell

    @MainActor @Test func connectingInTheAppImportsRightAway() async throws {
        let source = DebugHealthSource(batches: [batch(workout("W1", day: 1))])
        let model = AppModel(container: try Stores.makeContainer(inMemory: true), healthSource: source)
        #expect(await model.connectHealth(.all))
        #expect(await source.authorizationRequests == 1)
        #expect(await source.isObserved)
        #expect(try await model.persistence.dataset().activities.count == 1)
    }

    @MainActor @Test func unavailableHealthDoesNotConnect() async throws {
        let source = DebugHealthSource(batches: [], authorizationError: .unavailable)
        let model = AppModel(container: try Stores.makeContainer(inMemory: true), healthSource: source)
        #expect(await model.connectHealth(.days90) == false)
        #expect(try await model.persistence.importState().isEnabled == false)
        #expect(model.healthError == "Apple Health ist auf diesem Gerät nicht verfügbar.")
        #expect(model.errorMessage == nil, "die Meldung gehört zur auslösenden Ansicht, nicht zur Wurzel unter dem Blatt")
    }

    // MARK: HealthKit-Anbindung

    /// F-14: Lese-Begründung, dazu die Schreib-Begründung, die App Store Connect bei HealthKit-Apps verlangen kann
    /// (ITMS-90683). Sie sagt ehrlich, dass nichts geschrieben wird.
    @Test func infoPlistExplainsHealthAccessAndSaysNothingIsWritten() {
        let share = Bundle.main.object(forInfoDictionaryKey: "NSHealthShareUsageDescription") as? String
        let update = Bundle.main.object(forInfoDictionaryKey: "NSHealthUpdateUsageDescription") as? String
        #expect(share?.contains("liest deine Trainings") == true)
        #expect(update?.contains("schreibt keine Daten") == true)
    }

    @Test func onlyWorkoutsAndDistancesAreRead() {
        let ids = Set(HealthKitWorkoutSource.readTypes.map(\.identifier))
        #expect(ids.contains(HKObjectType.workoutType().identifier))
        #expect(ids.count == 1 + WorkoutDistanceKind.allCases.count)
        #expect(ids.subtracting([HKObjectType.workoutType().identifier]).allSatisfy { $0.contains("Distance") })
    }

    @Test func mapperKeepsMissingDistanceAndIndoorUnknown() {
        let hk = HKWorkout(activityType: .cycling, start: day(1), end: day(1).addingTimeInterval(1_800))
        let w = HKWorkoutMapper.incoming(hk)
        #expect(w.sourceID == hk.uuid.uuidString)
        #expect(w.sportType == SportType(rawValue: 13))
        #expect(w.startAt == day(1) && w.durationSeconds == 1_800)
        #expect(w.distanceMeters == nil && w.isIndoor == nil && w.segments.isEmpty)
    }

    @Test func mapperReadsIndoorOnlyFromMetadata() {
        let hk = HKWorkout(activityType: .running, start: day(1), end: day(1).addingTimeInterval(600), workoutEvents: nil,
                           totalEnergyBurned: nil, totalDistance: nil, metadata: [HKMetadataKeyIndoorWorkout: true])
        #expect(HKWorkoutMapper.incoming(hk).isIndoor == true)
    }
}
