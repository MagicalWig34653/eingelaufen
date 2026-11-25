import Foundation

// Grenze zur Trainingsquelle und zum Speicher (SPEC 6.1, ARCHITEKTUR 5). Ohne HealthKit-Typen: die App
// implementiert `HealthWorkoutSource` mit Anchored/Observer-Query, Tests mit einer Fake-Quelle.

public enum HealthSourceError: Error, Hashable, Sendable {
    /// Gerät gesperrt, Health-Datenbank nicht lesbar (PLATTFORM F-03).
    case databaseInaccessible
    /// Auf diesem Gerät gibt es kein Health.
    case unavailable
    /// Technische Beschreibung ohne Gesundheitswerte.
    case failed(String)
}

/// Antwort einer verankerten Abfrage: Änderungen seit dem letzten Anker und der neue Anker (undurchsichtig).
public struct WorkoutChanges: Hashable, Sendable {
    public var batch: ImportBatch
    public var anchor: Data?

    public init(batch: ImportBatch, anchor: Data?) {
        self.batch = batch
        self.anchor = anchor
    }
}

/// Weckruf des Beobachters. Der Completion-Handler muss in **jedem** Pfad aufgerufen werden (F-02).
public typealias ObserverHandler = @Sendable (HealthSourceError?, @escaping @Sendable () -> Void) -> Void

public protocol HealthWorkoutSource: Sendable {
    /// Nur Leserechte. Ob der Nutzer sie erteilt hat, ist nicht erkennbar (F-04).
    func requestAuthorization() async throws
    /// Änderungen und ausdrücklich gemeldete Löschungen seit `anchor`; `since == nil` = alle verfügbaren Trainings.
    func fetchChanges(since: Date?, anchor: Data?) async throws -> WorkoutChanges
    /// Beobachter samt Background Delivery registrieren.
    func startObserving(_ handler: @escaping ObserverHandler) async throws
}

/// Zeitraum des Erstimports (SPEC 6.1 Punkt 2).
public enum ImportWindow: Hashable, Sendable, CaseIterable {
    case days30, days90, days365, all

    public static let standard = ImportWindow.days90
    /// `nil` = alle verfügbaren.
    public var days: Int? { nil }
    public init(days: Int?) { self = .all }
    public func startDate(now: Date) -> Date? { nil }
}

public enum ImportFailure: String, Hashable, Codable, Sendable {
    case locked, unavailable, sourceError, storeError
}

public struct ImportState: Hashable, Sendable {
    /// Der Nutzer hat die Verbindung eingerichtet.
    public var isEnabled: Bool
    /// Beginn des gewählten Zeitraums; bleibt fest, damit die Abfrage zum Anker passt.
    public var since: Date?
    public var anchor: Data?
    public var lastSuccessAt: Date?
    public var lastFailure: ImportFailure?
    /// „Import ausstehend“: beim Entsperren und im Vordergrund nachholen.
    public var retryPending: Bool

    public init(isEnabled: Bool, since: Date? = nil, anchor: Data? = nil, lastSuccessAt: Date? = nil,
                lastFailure: ImportFailure? = nil, retryPending: Bool = false) {
        self.isEnabled = isEnabled
        self.since = since
        self.anchor = anchor
        self.lastSuccessAt = lastSuccessAt
        self.lastFailure = lastFailure
        self.retryPending = retryPending
    }
}

/// Was ein Abgleich verändert hat (nur Zahlen, keine Gesundheitswerte).
public struct ImportSummary: Hashable, Sendable {
    public var inserted: Int
    public var updated: Int
    public var removed: Int
    public var pending: Int

    public init(inserted: Int = 0, updated: Int = 0, removed: Int = 0, pending: Int = 0) {
        self.inserted = inserted
        self.updated = updated
        self.removed = removed
        self.pending = pending
    }

    public init(_ output: ReconcileOutput) { self.init() }
}

public protocol ImportStore: Sendable {
    func importState() async throws -> ImportState
    /// Datensätze **und** Anker in einem Commit (SPEC 6.1 Punkt 6).
    func commitImport(_ changes: WorkoutChanges, now: Date) async throws -> ImportSummary
    func recordImportFailure(_ failure: ImportFailure, now: Date) async throws
}

/// Anzeigezustand. Es gibt bewusst keinen Fall „Zugriff verweigert“ (SPEC 6.1 Punkt 7, F-04).
public enum ImportStatus: Hashable, Sendable {
    case notConnected, waiting, pendingUnlock, noWorkoutsVisible, upToDate
    case failed(ImportFailure)

    public static func evaluate(_ state: ImportState, workoutCount: Int) -> ImportStatus { .notConnected }
}

/// Distanzart eines Trainings (PLATTFORM F-06). Die App bildet sie auf den HealthKit-Mengentyp ab.
public enum WorkoutDistanceKind: Hashable, Sendable, CaseIterable {
    case cycling, walkingRunning, wheelchair, swimming, downhillSnowSports, crossCountrySkiing
    case paddleSports, rowing, skatingSports

    public static func of(_ type: SportType) -> WorkoutDistanceKind? { nil }
}
