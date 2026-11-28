#if DEBUG
import Foundation
import os
import GearCore

/// Skriptbare Quelle für App- und UI-Tests (nur Debug): berührt nie HealthKit. Der Anker zählt die schon
/// gelieferten Batches; `errors` werden der Reihe nach vor dem nächsten Batch geworfen.
actor DebugHealthSource: HealthWorkoutSource {
    private let batches: [ImportBatch]
    private var errors: [HealthSourceError]
    private let authorizationError: HealthSourceError?
    /// Hält die erste Abfrage fest, bis der UI-Test sie freigibt (`DebugHealthSource.releaseName`): Lade- und Wartezustände
    /// bleiben so lange sichtbar, wie der Test sie braucht, unabhängig von der Last des Rechners. Ohne Freigabe endet das
    /// Warten nach `maxHold`, damit ein von Hand gestarteter Lauf nicht hängen bleibt.
    private let isHeld: Bool
    private let maxHold: Duration = .seconds(120)
    /// Wird vom C-Rückruf der Darwin-Mitteilung gesetzt (läuft auf beliebigem Thread, darum das Schloss).
    private static let releaseFlag = OSAllocatedUnfairLock(initialState: false)
    private(set) var authorizationRequests = 0
    private(set) var isObserved = false

    init(batches: [ImportBatch], errors: [HealthSourceError] = [], authorizationError: HealthSourceError? = nil,
         held: Bool = false) {
        self.batches = batches
        self.errors = errors
        self.authorizationError = authorizationError
        self.isHeld = held
        // Schon beim Erzeugen anmelden: Eine Freigabe vor der ersten Abfrage darf nicht verloren gehen.
        if held {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
                DebugHealthSource.releaseFlag.withLock { $0 = true }
            }, Self.releaseName as CFString, nil, .deliverImmediately)
        }
    }

    /// Darwin-Mitteilung, mit der der UI-Test (anderer Prozess, gleicher Simulator) das Festhalten beendet.
    static let releaseName = "de.linolaske.eingelaufen.uitest.releaseHealth"

    private func hold() async throws {
        guard isHeld else { return }
        let deadline = ContinuousClock.now + maxHold
        while !Self.releaseFlag.withLock({ $0 }) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    func requestAuthorization() async throws {
        authorizationRequests += 1
        if let authorizationError { throw authorizationError }
    }

    func fetchChanges(since: Date?, anchor: Data?) async throws -> WorkoutChanges {
        try await hold()
        if !errors.isEmpty { throw errors.removeFirst() }
        let i = anchor.flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
        guard i < batches.count else { return WorkoutChanges(batch: ImportBatch(), anchor: anchor) }
        return WorkoutChanges(batch: batches[i], anchor: Data(String(i + 1).utf8))
    }

    func startObserving(_ handler: @escaping ObserverHandler) async throws { isObserved = true }

    /// Szenarien der UI-Tests (`-UITestHealth <name>`).
    static func scenario(_ name: String?) -> DebugHealthSource {
        func workout(_ id: String, _ category: SportCategory, day: Double, minutes: Double, km: Double) -> IncomingWorkout {
            let start = Fixtures.at(day: day)
            return IncomingWorkout(sourceID: id, sportType: category.defaultSportType, startAt: start,
                                   endAt: start.addingTimeInterval(minutes * 60), distanceMeters: km * 1_000,
                                   durationSeconds: minutes * 60, sourceName: "Testuhr")
        }
        let ride = workout("ui-ride", .cycling, day: 2, minutes: 95, km: 42.3)
        let run = workout("ui-run", .running, day: 4, minutes: 40, km: 7.5)
        return switch name {
        case "workouts":
            DebugHealthSource(batches: [ImportBatch(upserts: [ride, run]), ImportBatch(deletedSourceIDs: [run.sourceID])])
        case "locked":
            DebugHealthSource(batches: [ImportBatch(upserts: [ride])], errors: [.databaseInaccessible])
        case "error":
            DebugHealthSource(batches: [], errors: [.failed("test")])
        case "later":
            DebugHealthSource(batches: [ImportBatch(), ImportBatch(upserts: [ride])])
        case "slow":
            DebugHealthSource(batches: [ImportBatch(upserts: [ride])], held: true)
        case "slow-error":
            DebugHealthSource(batches: [], errors: [.failed("test")], held: true)
        case "unavailable":
            DebugHealthSource(batches: [], authorizationError: .unavailable)
        default:
            DebugHealthSource(batches: [])
        }
    }
}
#endif
