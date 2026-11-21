import Foundation

/// Grundlage einer Kennzahl. Die UI darf „0 km“ nur zeigen, wenn wirklich 0 gemessen wurde (T-09).
public enum Metric<Value: Equatable & Sendable>: Equatable, Sendable {
    /// Es liegt kein einziger Messwert vor → Anzeige „Keine Daten“.
    case noData
    /// Gemessen. `isComplete == false`: mindestens ein Beitrag hatte keinen Wert, die Summe ist eine Untergrenze
    /// → Anzeige „x km (unvollständig)“, nie still weniger.
    case measured(Value, isComplete: Bool)
    /// Durch Regel/Heuristik erzeugt, muss in der UI als Schätzung gekennzeichnet werden (SPEC 5.3).
    case estimate(Value, basis: EstimateBasis)
}

public enum EstimateBasis: String, Equatable, Sendable {
    case firstInstallation, firstUsage
}

public struct UsageSummary: Equatable, Sendable {
    public var uses: Int
    public var distanceMeters: Metric<Double>
    public var durationSeconds: Metric<Double>
}

/// Ergebnis einer Fensterabfrage, bei der der Bezugspunkt fehlen kann.
public enum UsageWindow: Equatable, Sendable {
    case value(UsageSummary)
    /// „Seit Einbau“ für einen Gegenstand, der nicht (mehr) montiert ist: kein Wert statt einer erfundenen Zahl.
    case notInstalled
    /// „Seit letzter Wartung“ ohne erfasste Wartung dieser Art.
    case noMaintenanceRecorded(MaintenanceKind)
}

/// Abfragen über das abgeleitete Ledger (ARCHITEKTUR 4, SPEC 5.3).
public struct UsageQuery: Sendable {
    private let entriesByGear: [UUID: [UsageLedgerEntry]]
    private let graph: InstallationGraph
    private let maintenance: [MaintenanceEvent]
    private let gear: [UUID: GearItem]

    public init(entries: [UsageLedgerEntry], installations: [Installation],
                maintenance: [MaintenanceEvent] = [], gear: [GearItem] = []) {
        self.entriesByGear = Dictionary(grouping: entries, by: \.gearID)
        self.graph = InstallationGraph(installations)
        self.maintenance = maintenance
        self.gear = Dictionary(gear.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Summe aller historisch belegten Nutzungen, auch aus früheren Montagen (SPEC 5.3, P-03).
    public func lifetime(of gearID: UUID) -> UsageSummary {
        Self.summarize(entriesByGear[gearID] ?? [])
    }

    /// Ab Beginn der aktuellen Montage (P-03): Einträge mit `t >= startedAt`.
    public func sinceInstallation(of gearID: UUID) -> UsageWindow {
        guard let current = graph.currentInstallation(of: gearID) else { return .notInstalled }
        let inWindow = (entriesByGear[gearID] ?? []).filter { $0.occurredAt >= current.startedAt }
        return .value(Self.summarize(inWindow))
    }

    /// Nach dem jüngsten Wartungsereignis dieser Art; setzt nur diesen Wert zurück, nie die Lebensdauer (T-11).
    /// Einträge mit `t > performedAt` zählen (ARCHITEKTUR 4).
    public func sinceMaintenance(of gearID: UUID, kind: MaintenanceKind) -> UsageWindow {
        let latest = maintenance.filter { $0.gearID == gearID && $0.kind == kind }.map(\.performedAt).max()
        guard let performedAt = latest else { return .noMaintenanceRecorded(kind) }
        let inWindow = (entriesByGear[gearID] ?? []).filter { $0.occurredAt > performedAt }
        return .value(Self.summarize(inWindow))
    }

    /// Kalenderalter in vollen Tagen. Ab Kaufdatum gemessen, sonst ab erster Montage/Nutzung als Schätzung gekennzeichnet.
    public func calendarAgeDays(of gearID: UUID, now: Date) -> Metric<Int> {
        func days(from start: Date) -> Int { max(0, Int(now.timeIntervalSince(start) / 86_400)) }

        if let purchase = gear[gearID]?.purchaseDate {
            return .measured(days(from: purchase), isComplete: true)
        }
        let firstMount = graph.installations.filter { $0.childGearID == gearID }.map(\.startedAt).min()
        let firstUse = (entriesByGear[gearID] ?? []).map(\.occurredAt).min()
        switch (firstMount, firstUse) {
        case let (mount?, use?):
            return mount <= use ? .estimate(days(from: mount), basis: .firstInstallation)
                                : .estimate(days(from: use), basis: .firstUsage)
        case let (mount?, nil): return .estimate(days(from: mount), basis: .firstInstallation)
        case let (nil, use?): return .estimate(days(from: use), basis: .firstUsage)
        case (nil, nil): return .noData
        }
    }

    // MARK: Intern

    /// Fehlende Werte bleiben fehlend: nur `nil` → `.noData`; gemischt → Untergrenze mit `isComplete == false`.
    /// Ohne jeden Eintrag ist 0 eine wahre Messung (nichts war zu verbuchen).
    private static func summarize(_ entries: [UsageLedgerEntry]) -> UsageSummary {
        UsageSummary(
            uses: entries.reduce(0) { $0 + $1.uses },
            distanceMeters: sum(entries.map(\.distanceMeters)),
            durationSeconds: sum(entries.map(\.durationSeconds)))
    }

    private static func sum(_ values: [Double?]) -> Metric<Double> {
        if values.isEmpty { return .measured(0, isComplete: true) }
        let known = values.compactMap { $0 }
        if known.isEmpty { return .noData }
        return .measured(known.reduce(0, +), isComplete: known.count == values.count)
    }
}
