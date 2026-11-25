import Foundation
@testable import GearCore

/// Fake-Quelle wie eine `HKAnchoredObjectQuery`: ein Änderungsprotokoll, der Anker ist die letzte gelesene Nummer.
/// Gelöschte Trainings liefert sie nicht mehr als Datensatz, sondern nur als Löschmeldung.
actor FakeHealthSource: HealthWorkoutSource {
    private enum Event { case upsert(IncomingWorkout), delete(String) }
    private var log: [Event] = []
    private var fetchError: HealthSourceError?
    private var handler: ObserverHandler?

    private(set) var sinceSeen: [Date?] = []
    private(set) var anchorsSeen: [Data?] = []
    private(set) var authorizationRequests = 0
    private(set) var observerRegistrations = 0
    private var inFlight = 0
    private(set) var maxInFlight = 0

    func put(_ workouts: IncomingWorkout...) { log += workouts.map(Event.upsert) }
    func delete(_ ids: String...) { log += ids.map(Event.delete) }
    func fail(with error: HealthSourceError?) { fetchError = error }

    func requestAuthorization() async throws {
        authorizationRequests += 1
        if fetchError == .unavailable { throw HealthSourceError.unavailable }
    }

    func fetchChanges(since: Date?, anchor: Data?) async throws -> WorkoutChanges {
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        defer { inFlight -= 1 }
        for _ in 0..<20 { await Task.yield() }
        sinceSeen.append(since)
        anchorsSeen.append(anchor)
        if let fetchError { throw fetchError }

        let start = anchor.flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
        var upserts: [String: IncomingWorkout] = [:]
        var deleted: [String] = []
        for event in log.dropFirst(start) {
            switch event {
            case .upsert(let w):
                if since.map({ w.startAt >= $0 }) ?? true { upserts[w.sourceID] = w }
            case .delete(let id):
                upserts[id] = nil
                deleted.append(id)
            }
        }
        return WorkoutChanges(batch: ImportBatch(upserts: Array(upserts.values), deletedSourceIDs: deleted),
                              anchor: Data(String(log.count).utf8))
    }

    func startObserving(_ handler: @escaping ObserverHandler) async throws {
        observerRegistrations += 1
        if let fetchError, fetchError == .unavailable { throw fetchError }
        self.handler = handler
    }

    /// Wie ein Weckruf des Systems: liefert erst, wenn der Completion-Handler aufgerufen wurde.
    /// `false` = kein Observer registriert.
    func fireObserver(error: HealthSourceError? = nil) async -> Bool {
        guard let handler else { return false }
        await withCheckedContinuation { continuation in
            handler(error) { continuation.resume() }
        }
        return true
    }
}

/// Speicher im Arbeitsspeicher: Datensätze und Anker ändern sich nur gemeinsam.
actor MemoryImportStore: ImportStore {
    struct Broken: Error {}
    private(set) var dataset: GearDataset
    private(set) var state: ImportState
    private(set) var commits = 0
    private var failCommit = false
    private var failState = false
    private let now = day(30)

    init(dataset: GearDataset = GearDataset(), enabled: Bool = true, since: Date? = nil) {
        self.dataset = dataset
        state = ImportState(isEnabled: enabled, since: since)
    }

    func setCommitFailure(_ on: Bool) { failCommit = on }
    func setStateFailure(_ on: Bool) { failState = on }
    func enable(since: Date?) { state.isEnabled = true; state.since = since }
    func resetAnchor() { state.anchor = nil }
    func replace(_ d: GearDataset) { dataset = d }

    func importState() async throws -> ImportState {
        if failState { throw Broken() }
        return state
    }

    func commitImport(_ changes: WorkoutChanges, now: Date) async throws -> ImportSummary {
        if failCommit { throw Broken() }
        let out = ImportReconciler.reconcile(dataset, changes.batch, now: now,
                                             policy: EnginePolicy(autoAssignSoleCandidate: true))
        dataset = out.dataset
        state.anchor = changes.anchor
        state.lastSuccessAt = now
        state.lastFailure = nil
        state.retryPending = false
        commits += 1
        return ImportSummary(out)
    }

    func recordImportFailure(_ failure: ImportFailure, now: Date) async throws {
        state.lastFailure = failure
        state.retryPending = failure != .unavailable
    }
}
