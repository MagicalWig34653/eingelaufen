import Foundation

// Wartungsregeln auswerten (SPEC 8.2, 8.3): drei getrennte Statusarten, „frühester Wert“, höchstens drei Hinweise.

public enum RuleState: Int, Equatable, Comparable, Sendable {
    /// Nicht beurteilbar (keine/unvollständige Daten): nie als „in Ordnung“ gezeigt.
    case unknown = 0, belowInterval, dueSoon, due
    public static func < (a: RuleState, b: RuleState) -> Bool { a.rawValue < b.rawValue }
}

public enum IntervalBaseline: Equatable, Sendable {
    case lastMaintenance(Date)
    case sinceTracking
}

/// Statusart 1: Intervall.
public struct IntervalStatus: Equatable, Sendable {
    public var rule: MaintenanceRule
    public var baseline: IntervalBaseline
    /// Wert seit Bezugspunkt in der Einheit der Regel (m, s, Anzahl, Tage); `noData`/`measured(isComplete: false)` bleiben erhalten.
    public var value: Metric<Double>
    public var state: RuleState
}

public enum MeasurementState: Equatable, Sendable { case noLimit, withinLimit, limitReached }

/// Statusart 2: zuletzt gemessener Wert.
public struct MeasurementStatus: Equatable, Sendable {
    public var value: Double
    public var measuredAt: Date
    public var limit: Double?
    public var state: MeasurementState
}

/// Statusart 3: Prognose, immer Schätzung.
public struct Forecast: Equatable, Sendable {
    public var estimatedDaysUntilDue: Int
    public var basisDays: Int
    public var isEstimate: Bool { true }
}

public struct GearMaintenanceReport: Equatable, Sendable {
    public var gearID: UUID
    public var intervals: [IntervalStatus]
    public var measurement: MeasurementStatus?
    public var forecast: Forecast?
    /// Wichtigster Intervallstatus (frühester Wert): höchster Zustand, dann größter Anteil am Intervall.
    public var mostUrgent: IntervalStatus? { nil }
}

public struct MaintenanceHint: Equatable, Sendable {
    public enum Source: Equatable, Sendable { case interval, measurement }
    public var gearID: UUID
    public var ruleID: UUID?
    public var state: RuleState
    public var source: Source
}

public enum MaintenanceEvaluator {
    public static func report(gearID: UUID, rules: [MaintenanceRule], events: [MaintenanceEvent],
                              entries: [UsageLedgerEntry], installations: [Installation], gear: [GearItem],
                              now: Date) -> GearMaintenanceReport {
        GearMaintenanceReport(gearID: gearID, intervals: [])
    }

    public static func topHints(_ reports: [GearMaintenanceReport], limit: Int = 3) -> [MaintenanceHint] { [] }
}
