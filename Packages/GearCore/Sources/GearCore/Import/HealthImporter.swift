import Foundation

public enum ImportResult: Hashable, Sendable {
    case disabled
    case success(ImportSummary)
    case failure(ImportFailure)
}

/// Steuert den Abgleich (ARCHITEKTUR 5). Gerüst.
public actor HealthImporter {
    private let source: any HealthWorkoutSource
    private let store: any ImportStore
    private let now: @Sendable () -> Date

    public init(source: any HealthWorkoutSource, store: any ImportStore, now: @escaping @Sendable () -> Date) {
        self.source = source
        self.store = store
        self.now = now
    }

    public func requestAuthorization() async throws {}
    public func start() async {}
    @discardableResult
    public func sync() async -> ImportResult { .disabled }
    @discardableResult
    public func retryIfPending() async -> ImportResult? { nil }
}
