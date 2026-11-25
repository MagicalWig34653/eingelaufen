import Foundation

public enum ImportResult: Hashable, Sendable {
    /// Keine Verbindung eingerichtet: die Quelle wurde nicht angefasst.
    case disabled
    case success(ImportSummary)
    case failure(ImportFailure)
}

/// Steuert den Abgleich (SPEC 6.1, ARCHITEKTUR 5). Jeder Auslöser (Start, Vordergrund, Beobachter, Entsperren,
/// Einstellungen) läuft über `sync()`: Anker lesen, verankert abfragen, Datensätze und Anker gemeinsam speichern.
/// Abgleiche laufen nacheinander, damit nie zwei mit demselben Anker arbeiten.
public actor HealthImporter {
    private let source: any HealthWorkoutSource
    private let store: any ImportStore
    private let now: @Sendable () -> Date
    private var last: Task<ImportResult, Never>?
    private var isObserving = false

    public init(source: any HealthWorkoutSource, store: any ImportStore, now: @escaping @Sendable () -> Date) {
        self.source = source
        self.store = store
        self.now = now
    }

    /// Fragt die Leserechte an. Ein Erfolg sagt nichts darüber, ob der Nutzer sie erteilt hat (F-04).
    public func requestAuthorization() async throws {
        try await source.requestAuthorization()
    }

    /// Bei jedem App-Start (F-02): Beobachter registrieren (einmal je Prozess) und abgleichen.
    public func start() async {
        guard let state = try? await store.importState(), state.isEnabled else { return }
        await observe()
        await sync()
    }

    @discardableResult
    public func sync() async -> ImportResult {
        let previous = last
        let task = Task {
            _ = await previous?.value
            return await self.runOnce()
        }
        last = task
        return await task.value
    }

    /// Nach dem Entsperren: nur wenn ein Import ausstehend ist, sonst `nil`.
    @discardableResult
    public func retryIfPending() async -> ImportResult? {
        guard let state = try? await store.importState(), state.retryPending else { return nil }
        return await sync()
    }

    private func observe() async {
        guard !isObserving else { return }
        isObserving = true
        do {
            try await source.startObserving { [weak self] error, completion in
                guard let self else { return completion() }
                Task {
                    await self.observerFired(error)
                    completion()
                }
            }
        } catch {
            isObserving = false   // beim nächsten Start erneut
            await record(Self.failure(for: error))
        }
    }

    /// Kehrt in jedem Fall zurück (nichts wirft), damit der Completion-Handler immer folgt.
    private func observerFired(_ error: HealthSourceError?) async {
        if let error { await record(Self.failure(for: error)) } else { await sync() }
    }

    private func runOnce() async -> ImportResult {
        let state: ImportState
        do { state = try await store.importState() } catch { return .failure(.storeError) }
        guard state.isEnabled else { return .disabled }
        let changes: WorkoutChanges
        do {
            changes = try await source.fetchChanges(since: state.since, anchor: state.anchor)
        } catch {
            return await fail(Self.failure(for: error))
        }
        do {
            return .success(try await store.commitImport(changes, now: now()))
        } catch {
            return await fail(.storeError)
        }
    }

    private func fail(_ failure: ImportFailure) async -> ImportResult {
        await record(failure)
        return .failure(failure)
    }

    /// Scheitert auch das Merken, bleibt nur der Rückgabewert; der Anker steht noch, nichts geht verloren.
    private func record(_ failure: ImportFailure) async {
        try? await store.recordImportFailure(failure, now: now())
    }

    private static func failure(for error: Error) -> ImportFailure {
        switch error as? HealthSourceError {
        case .databaseInaccessible: .locked
        case .unavailable: .unavailable
        case .failed, nil: .sourceError
        }
    }
}
