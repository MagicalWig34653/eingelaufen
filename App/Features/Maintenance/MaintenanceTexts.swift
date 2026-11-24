import Foundation
import GearCore

/// Texte und Formatierung für Wartung (SPEC 8). Intervallhinweise sagen „Prüfen“, nie „Ersetzen“ (SPEC 7.4);
/// Zustände stehen immer als Text, nie nur als Farbe (SPEC 1.4); fehlende Daten sind „Nicht beurteilbar“, nie „in Ordnung“ (T-09).
extension DisplayNames {
    static func name(for kind: MaintenanceKind) -> String {
        switch kind {
        case .cleaned: String(localized: "Gereinigt")
        case .lubricated: String(localized: "Geschmiert")
        case .inspected: String(localized: "Geprüft")
        case .wearMeasured: String(localized: "Verschleiß gemessen")
        case .partInstalled: String(localized: "Teil eingebaut")
        case .partRemoved: String(localized: "Teil ausgebaut")
        case .partReplaced: String(localized: "Teil ersetzt")
        case .repaired: String(localized: "Repariert")
        case .custom: String(localized: "Wartung")
        }
    }

    static func name(for action: QuickAction) -> String {
        switch action {
        case .cleaned: String(localized: "Gereinigt")
        case .lubricated: String(localized: "Geschmiert")
        case .inspected: String(localized: "Geprüft")
        case .wearMeasured: String(localized: "Messen")
        case .partChange: String(localized: "Teil wechseln")
        case .repaired: String(localized: "Repariert")
        case .custom: String(localized: "Eigene Wartung")
        }
    }

    static func symbol(for action: QuickAction) -> String {
        switch action {
        case .cleaned: "bubbles.and.sparkles"
        case .lubricated: "drop"
        case .inspected: "checkmark.circle"
        case .wearMeasured: "ruler"
        case .partChange: "arrow.triangle.2.circlepath"
        case .repaired: "wrench.and.screwdriver"
        case .custom: "square.and.pencil"
        }
    }

    static func name(for state: RuleState) -> String {
        switch state {
        case .due: String(localized: "Prüfen")
        case .dueSoon: String(localized: "Bald prüfen")
        case .belowInterval: String(localized: "Kein Hinweis fällig")
        case .unknown: String(localized: "Nicht beurteilbar")
        }
    }

    static func number(_ value: Double, maxFraction: Int = 2) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = maxFraction
        return f.string(from: value as NSNumber) ?? "\(value)"
    }

    static func day(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .omitted) }

    static func cost(minor: Int) -> String {
        (Decimal(minor) / 100).formatted(.currency(code: Locale.current.currency?.identifier ?? "EUR"))
    }

    /// Wert einer Regel in ihrer Einheit.
    static func value(_ metric: Metric<Double>, for unit: UsageMetricKind) -> String {
        switch metric {
        case .noData: return String(localized: "Keine Daten")
        case let .measured(v, complete): return plain(v, unit) + (complete ? "" : " " + String(localized: "(unvollständig)"))
        case let .estimate(v, _): return plain(v, unit) + " " + String(localized: "(Schätzung)")
        }
    }

    static func plain(_ v: Double, _ unit: UsageMetricKind) -> String {
        switch unit {
        case .distance: lengthText(v)
        case .duration: durationText(v)
        case .uses: String(localized: "\(Int(v)) Nutzungen")
        case .calendarAge: String(localized: "\(Int(v)) Tage")
        }
    }

    static func baseline(_ b: IntervalBaseline) -> String {
        switch b {
        case .lastMaintenance(let date): String(localized: "seit \(day(date))")
        case .sinceTracking: String(localized: "seit Erfassung")
        }
    }

    /// „Geschmiert · seit 3. Nov. 2026: 105 km von 100 km · Prüfen“.
    static func summary(_ status: IntervalStatus) -> String {
        let rule = status.rule
        return "\(name(for: rule.kind)) · \(baseline(status.baseline)): \(value(status.value, for: rule.metric)) "
            + String(localized: "von") + " \(plain(rule.intervalValue, rule.metric)) · \(name(for: status.state))"
    }
}

/// Auswertung für Detail und Übersicht aus den gespeicherten Daten (Lesen per `@Query`, Rechnen im Kern).
enum MaintenanceReports {
    static func build(gear: [GearEntity], rules: [MaintenanceRuleEntity], events: [MaintenanceEventEntity],
                      ledger: [LedgerEntryEntity], installations: [InstallationEntity], now: Date) -> [GearMaintenanceReport] {
        let items = gear.map(\.value)
        let ruleValues = rules.map(\.value), eventValues = events.map(\.value)
        let entries = ledger.map(\.value), mounts = installations.map(\.value)
        let relevant = Set(ruleValues.map(\.gearID)).union(eventValues.map(\.gearID))
        return items.filter { relevant.contains($0.id) }.map {
            MaintenanceEvaluator.report(gearID: $0.id, rules: ruleValues, events: eventValues, entries: entries,
                                        installations: mounts, gear: items, now: now)
        }
    }
}
