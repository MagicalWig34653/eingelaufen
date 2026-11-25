#if DEBUG
import Foundation
import GearCore

/// Skriptbare Quelle für App- und UI-Tests (nur Debug): berührt nie HealthKit. Der Anker zählt die schon
/// gelieferten Batches; `errors` werden der Reihe nach vor dem nächsten Batch geworfen.
actor DebugHealthSource: HealthWorkoutSource {
    private let batches: [ImportBatch]
    private var errors: [HealthSourceError]
    private let authorizationError: HealthSourceError?
    private(set) var authorizationRequests = 0
    private(set) var isObserved = false

    init(batches: [ImportBatch], errors: [HealthSourceError] = [], authorizationError: HealthSourceError? = nil) {
        self.batches = batches
        self.errors = errors
        self.authorizationError = authorizationError
    }

    func requestAuthorization() async throws {
        authorizationRequests += 1
        if let authorizationError { throw authorizationError }
    }

    func fetchChanges(since: Date?, anchor: Data?) async throws -> WorkoutChanges {
        if !errors.isEmpty { throw errors.removeFirst() }
        let i = anchor.flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
        guard i < batches.count else { return WorkoutChanges(batch: ImportBatch(), anchor: anchor) }
        return WorkoutChanges(batch: batches[i], anchor: Data(String(i + 1).utf8))
    }

    func startObserving(_ handler: @escaping ObserverHandler) async throws { isObserved = true }
}
#endif
