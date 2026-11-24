import Foundation

// Wartungsregeln auswerten (SPEC 8.2, 8.3): drei getrennte Statusarten (Intervall, Messwert, Prognose),
// „frühester Wert“ bei mehreren Regeln, höchstens drei Hinweise. Keine Prozent-Verschleißangaben, nie „in Ordnung“
// aus fehlenden Daten (T-09), Hinweise sagen „Prüfen“, nicht „Ersetzen“ (SPEC 7.4).
//
// Regelsemantik (`MaintenanceRule`): `kind` ist das Wartungsereignis, das den Zähler zurücksetzt (z. B. geschmiert).
// Ausnahme `kind == .wearMeasured`: das ist die Messgrenze, `intervalValue` ist der Grenzwert in der Einheit der Messung.

public enum RuleState: Int, Equatable, Comparable, Sendable {
    /// Nicht beurteilbar (keine oder unvollständige Daten): nie als „in Ordnung“ gezeigt.
    case unknown = 0, belowInterval, dueSoon, due
    public static func < (a: RuleState, b: RuleState) -> Bool { a.rawValue < b.rawValue }
}

public enum IntervalBaseline: Equatable, Sendable {
    case lastMaintenance(Date)
    /// Es gibt keine Wartung dieser Art: gezählt wird ab Beginn der Erfassung.
    case sinceTracking
}

/// Statusart 1: Intervall.
public struct IntervalStatus: Equatable, Sendable {
    public var rule: MaintenanceRule
    public var baseline: IntervalBaseline
    /// Wert seit Bezugspunkt in der Einheit der Regel (m, s, Anzahl, Tage); `noData` und unvollständige Summen bleiben erhalten.
    public var value: Metric<Double>
    public var state: RuleState

    /// Anteil am Intervall (1 = erreicht); `nil`, wenn kein Wert vorliegt.
    public var fractionUsed: Double? {
        guard rule.intervalValue > 0 else { return nil }
        switch value {
        case .noData: return nil
        case let .measured(v, _), let .estimate(v, _): return v / rule.intervalValue
        }
    }
}

public enum MeasurementState: Equatable, Sendable { case noLimit, withinLimit, limitReached }

/// Statusart 2: zuletzt gemessener Wert (z. B. Kettenlängung in %), mit Datum.
public struct MeasurementStatus: Equatable, Sendable {
    public var value: Double
    public var measuredAt: Date
    public var limit: Double?
    public var state: MeasurementState
}

/// Statusart 3: Prognose, immer eine Schätzung und nur mit ausreichend Daten.
public struct Forecast: Equatable, Sendable {
    public var estimatedDaysUntilDue: Int
    /// Zeitraum der Nutzungsdaten, auf dem die Schätzung beruht.
    public var basisDays: Int
    public var isEstimate: Bool { true }
}

public struct GearMaintenanceReport: Equatable, Sendable {
    public var gearID: UUID
    public var intervals: [IntervalStatus]
    public var measurement: MeasurementStatus?
    public var forecast: Forecast?

    public init(gearID: UUID, intervals: [IntervalStatus] = [], measurement: MeasurementStatus? = nil, forecast: Forecast? = nil) {
        self.gearID = gearID
        self.intervals = intervals
        self.measurement = measurement
        self.forecast = forecast
    }

    /// Wichtigster Intervallstatus („frühester Wert“, SPEC 8.3): höchster Zustand, dann größter Anteil, dann Regel-ID.
    public var mostUrgent: IntervalStatus? {
        intervals.max { a, b in
            (a.state, a.fractionUsed ?? -1, b.rule.id.uuidString) < (b.state, b.fractionUsed ?? -1, a.rule.id.uuidString)
        }
    }
}

public struct MaintenanceHint: Equatable, Sendable {
    public enum Source: Equatable, Sendable { case interval, measurement }
    public var gearID: UUID
    public var ruleID: UUID?
    public var state: RuleState
    public var source: Source

    public init(gearID: UUID, ruleID: UUID?, state: RuleState, source: Source) {
        self.gearID = gearID
        self.ruleID = ruleID
        self.state = state
        self.source = source
    }
}

public enum MaintenanceEvaluator {
    /// Mindestdaten für eine Prognose: Einträge im Fenster, Spanne in Tagen, Fensterlänge.
    static let forecastMinEntries = 4
    static let forecastMinSpanDays = 21
    static let forecastWindowDays = 90

    public static func report(gearID: UUID, rules: [MaintenanceRule], events: [MaintenanceEvent],
                              entries: [UsageLedgerEntry], installations: [Installation], gear: [GearItem],
                              now: Date) -> GearMaintenanceReport {
        let own = entries.filter { $0.gearID == gearID }
        let ownEvents = events.filter { $0.gearID == gearID }
        let query = UsageQuery(entries: own, installations: installations, maintenance: ownEvents, gear: gear)
        let active = rules.filter { $0.gearID == gearID && $0.enabled }

        let intervals = active.filter { $0.kind != .wearMeasured }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { intervalStatus($0, events: ownEvents, query: query, gearID: gearID, now: now) }
        let limit = active.filter { $0.kind == .wearMeasured }.map(\.intervalValue).min()

        var result = GearMaintenanceReport(gearID: gearID, intervals: intervals,
                                           measurement: measurementStatus(events: ownEvents, limit: limit))
        if let top = result.mostUrgent {
            result.forecast = forecast(for: top, entries: own, now: now)
        }
        return result
    }

    /// Höchstens `limit` Hinweise für die Übersicht (SPEC S02): je Gegenstand der dringendste, fällige vor Vorwarnungen,
    /// dann größter Anteil am Intervall, dann Gegenstands-ID. Nichts Fälliges → leer.
    public static func topHints(_ reports: [GearMaintenanceReport], limit: Int = 3) -> [MaintenanceHint] {
        struct Candidate { var hint: MaintenanceHint; var fraction: Double }
        var candidates: [Candidate] = []
        for report in reports {
            var options: [Candidate] = []
            if let top = report.mostUrgent, top.state >= .dueSoon {
                options.append(Candidate(hint: MaintenanceHint(gearID: report.gearID, ruleID: top.rule.id, state: top.state, source: .interval),
                                         fraction: top.fractionUsed ?? 0))
            }
            if let m = report.measurement, m.state == .limitReached, let l = m.limit, l > 0 {
                options.append(Candidate(hint: MaintenanceHint(gearID: report.gearID, ruleID: nil, state: .due, source: .measurement),
                                         fraction: m.value / l))
            }
            if let best = options.max(by: { ($0.hint.state, $0.fraction) < ($1.hint.state, $1.fraction) }) { candidates.append(best) }
        }
        let sorted = candidates.sorted { a, b in
            (b.hint.state, b.fraction, a.hint.gearID.uuidString) < (a.hint.state, a.fraction, b.hint.gearID.uuidString)
        }
        return sorted.prefix(max(0, limit)).map(\.hint)
    }

    // MARK: Intern

    private static func intervalStatus(_ rule: MaintenanceRule, events: [MaintenanceEvent], query: UsageQuery,
                                       gearID: UUID, now: Date) -> IntervalStatus {
        let last = events.filter { $0.kind == rule.kind }.map(\.performedAt).max()
        let baseline: IntervalBaseline = last.map(IntervalBaseline.lastMaintenance) ?? .sinceTracking
        let value: Metric<Double>
        switch rule.metric {
        case .calendarAge:
            if let last {
                value = .measured(Double(max(0, Int(now.timeIntervalSince(last) / 86_400))), isComplete: true)
            } else {
                switch query.calendarAgeDays(of: gearID, now: now) {
                case .noData: value = .noData
                case let .measured(d, complete): value = .measured(Double(d), isComplete: complete)
                case let .estimate(d, basis): value = .estimate(Double(d), basis: basis)
                }
            }
        case .distance, .duration, .uses:
            let window = query.sinceMaintenance(of: gearID, kind: rule.kind)
            let summary: UsageSummary
            if case let .value(s) = window { summary = s } else { summary = query.lifetime(of: gearID) }
            switch rule.metric {
            case .distance: value = summary.distanceMeters
            case .duration: value = summary.durationSeconds
            default: value = .measured(Double(summary.uses), isComplete: true)
            }
        }
        return IntervalStatus(rule: rule, baseline: baseline, value: value, state: state(of: value, rule: rule))
    }

    private static func state(of value: Metric<Double>, rule: MaintenanceRule) -> RuleState {
        guard rule.intervalValue > 0 else { return .unknown }
        let v: Double, complete: Bool
        switch value {
        case .noData: return .unknown
        case let .measured(x, c): v = x; complete = c
        case let .estimate(x, _): v = x; complete = true
        }
        if v >= rule.intervalValue { return .due }          // eine Untergrenze reicht für „fällig“
        guard complete else { return .unknown }             // Lücken in den Daten: nicht „in Ordnung“ behaupten
        if let lead = rule.warningLeadValue, v >= rule.intervalValue - lead { return .dueSoon }
        return .belowInterval
    }

    private static func measurementStatus(events: [MaintenanceEvent], limit: Double?) -> MeasurementStatus? {
        let latest = events.filter { $0.kind == .wearMeasured && $0.measurement != nil }
            .max { ($0.performedAt, $0.id.uuidString) < ($1.performedAt, $1.id.uuidString) }
        guard let latest, let value = latest.measurement else { return nil }
        let state: MeasurementState = limit.map { value >= $0 ? .limitReached : .withinLimit } ?? .noLimit
        return MeasurementStatus(value: value, measuredAt: latest.performedAt, limit: limit, state: state)
    }

    /// Nur für Distanz-/Dauer-/Anzahl-Regeln, die noch nicht fällig sind, und nur mit lückenlosen, ausreichenden Daten.
    private static func forecast(for status: IntervalStatus, entries: [UsageLedgerEntry], now: Date) -> Forecast? {
        guard status.state == .belowInterval || status.state == .dueSoon,
              case let .measured(current, true) = status.value else { return nil }
        let amount: (UsageLedgerEntry) -> Double?
        switch status.rule.metric {
        case .distance: amount = { $0.distanceMeters }
        case .duration: amount = { $0.durationSeconds }
        case .uses: amount = { Double($0.uses) }
        case .calendarAge: return nil
        }
        let windowStart = now.addingTimeInterval(-Double(forecastWindowDays) * 86_400)
        let inWindow = entries.filter { $0.occurredAt >= windowStart && $0.occurredAt <= now }
        let values = inWindow.compactMap(amount)
        guard inWindow.count >= forecastMinEntries, values.count == inWindow.count,
              let first = inWindow.map(\.occurredAt).min() else { return nil }
        let basisDays = Int(now.timeIntervalSince(first) / 86_400)
        guard basisDays >= forecastMinSpanDays else { return nil }
        let rate = values.reduce(0, +) / Double(basisDays)
        guard rate > 0 else { return nil }
        let remaining = max(0, status.rule.intervalValue - current)
        return Forecast(estimatedDaysUntilDue: Int((remaining / rate).rounded(.up)), basisDays: basisDays)
    }
}
