import Testing
import Foundation
@testable import GearCore

private let bike = id(1), chain = id(4), helmet = id(7), shoes = id(8), tires = id(9)

private func rule(_ g: UUID, _ kind: MaintenanceKind = .lubricated, _ metric: UsageMetricKind = .distance,
                  _ value: Double, lead: Double? = nil, enabled: Bool = true) -> MaintenanceRule {
    MaintenanceRule(id: id(Int(value) + 5_000 + (g == bike ? 0 : 1)), gearID: g, kind: kind, metric: metric,
                    intervalValue: value, warningLeadValue: lead, enabled: enabled)
}

private func report(_ g: UUID = bike, rules: [MaintenanceRule], events: [MaintenanceEvent] = [],
                    rides: [(day: Int, km: Double?)], now: Date) -> GearMaintenanceReport {
    let acts = rides.enumerated().map { activity($0.offset + 1, start: day($0.element.day), distance: $0.element.km.map { $0 * 1_000 }) }
    let input = LedgerInput(activities: acts, assignments: acts.map { assign($0, g) })
    return MaintenanceEvaluator.report(gearID: g, rules: rules, events: events,
                                       entries: LedgerBuilder.build(input).entries, installations: [], gear: [], now: now)
}

@Suite("MaintenanceEvaluator (SPEC 8.2/8.3, T-09, T-11)")
struct MaintenanceEvaluatorTests {

    // MARK: Intervallstatus

    @Test("Intervall: Wert seit letzter Wartung dieser Art, darunter / Vorwarnung / fällig")
    func intervalStates() {
        let lube = MaintenanceEvent(gearID: bike, kind: .lubricated, performedAt: day(10))
        let r = rule(bike, .lubricated, .distance, 350_000, lead: 50_000)
        func state(_ km: Double) -> RuleState {
            report(rules: [r], events: [lube], rides: [(5, 400), (12, km)], now: day(20)).intervals.first?.state ?? .unknown
        }
        #expect(state(100) == .belowInterval)
        #expect(state(300) == .dueSoon)       // 300 ≥ 350 − 50
        #expect(state(350) == .due)
        let s = report(rules: [r], events: [lube], rides: [(5, 400), (12, 320)], now: day(20)).intervals.first
        #expect(s?.value == .measured(320_000, isComplete: true))
        #expect(s?.baseline == .lastMaintenance(day(10)))     // Fahrt von Tag 5 zählt nicht mit (T-11)
    }

    @Test("Ohne erfasste Wartung zählt die Nutzung seit Erfassungsbeginn, gekennzeichnet als Bezug „seit Erfassung“")
    func noMaintenanceUsesTracking() {
        let s = report(rules: [rule(bike, .lubricated, .distance, 350_000)], rides: [(1, 100), (2, 120)], now: day(5)).intervals.first
        #expect(s?.baseline == .sinceTracking)
        #expect(s?.value == .measured(220_000, isComplete: true))
        #expect(s?.state == .belowInterval)
    }

    @Test("T-09: Intervall ohne Distanzdaten ist „nicht beurteilbar“, nie „in Ordnung“; unvollständig unter Schwelle ebenso")
    func missingDataIsUnknown() {
        let r = rule(bike, .lubricated, .distance, 350_000)
        let none = report(rules: [r], rides: [(1, nil)], now: day(5)).intervals.first
        #expect(none?.value == .noData && none?.state == .unknown)
        let partial = report(rules: [r], rides: [(1, 100), (2, nil)], now: day(5)).intervals.first
        #expect(partial?.value == .measured(100_000, isComplete: false) && partial?.state == .unknown)
        // Untergrenze ≥ Intervall ist trotz Lücke fällig.
        let enough = report(rules: [r], rides: [(1, 400), (2, nil)], now: day(5)).intervals.first
        #expect(enough?.state == .due)
    }

    @Test("Metriken Dauer, Anzahl und Kalender (Tage seit Wartung)")
    func otherMetrics() {
        let lube = MaintenanceEvent(gearID: bike, kind: .cleaned, performedAt: day(10))
        let uses = report(rules: [rule(bike, .cleaned, .uses, 3)], events: [lube],
                          rides: [(11, 5), (12, 5), (13, 5)], now: day(20)).intervals.first
        #expect(uses?.value == .measured(3, isComplete: true) && uses?.state == .due)
        let hours = report(rules: [rule(bike, .cleaned, .duration, 7_200)], events: [lube],
                           rides: [(11, 5), (12, 5)], now: day(20)).intervals.first    // 2 × 1 h
        #expect(hours?.state == .due)
        let cal = report(rules: [rule(bike, .cleaned, .calendarAge, 30)], events: [lube], rides: [], now: day(45)).intervals.first
        #expect(cal?.value == .measured(35, isComplete: true) && cal?.state == .due)
        let calOk = report(rules: [rule(bike, .cleaned, .calendarAge, 30)], events: [lube], rides: [], now: day(20)).intervals.first
        #expect(calOk?.state == .belowInterval)
    }

    @Test("Deaktivierte Regeln werden nicht ausgewertet (SPEC 7.4)")
    func disabledRulesAreIgnored() {
        let r = rule(bike, .lubricated, .distance, 1_000, enabled: false)
        #expect(report(rules: [r], rides: [(1, 50)], now: day(5)).intervals.isEmpty)
    }

    @Test("Frühester Wert: bei mehreren Regeln gewinnt die dringendste (höchster Zustand, dann größter Anteil)")
    func earliestRuleWins() {
        let slow = rule(bike, .lubricated, .distance, 1_000_000)
        let fast = rule(bike, .cleaned, .distance, 100_000)
        let r = report(rules: [slow, fast], rides: [(1, 120)], now: day(5))
        #expect(r.intervals.count == 2)
        #expect(r.mostUrgent?.rule.id == fast.id)
        #expect(r.mostUrgent?.state == .due)
    }

    // MARK: Messwert

    @Test("Messwert: zuletzt gemessener Wert mit Datum, getrennt vom Intervall; Messgrenze löst „Grenze erreicht“ aus")
    func measurementStatus() {
        let m1 = MaintenanceEvent(gearID: chain, kind: .wearMeasured, performedAt: day(3), measurement: 0.3)
        let m2 = MaintenanceEvent(gearID: chain, kind: .wearMeasured, performedAt: day(12), measurement: 0.5)
        let limit = rule(chain, .wearMeasured, .distance, 0.5)
        let r = report(chain, rules: [limit], events: [m1, m2], rides: [], now: day(20))
        #expect(r.measurement == MeasurementStatus(value: 0.5, measuredAt: day(12), limit: 0.5, state: .limitReached))
        #expect(r.intervals.isEmpty)     // die Messgrenze ist kein Intervall
        let below = report(chain, rules: [limit], events: [m1], rides: [], now: day(20)).measurement
        #expect(below?.state == .withinLimit)
        let noLimit = report(chain, rules: [], events: [m2], rides: [], now: day(20)).measurement
        #expect(noLimit == MeasurementStatus(value: 0.5, measuredAt: day(12), limit: nil, state: .noLimit))
    }

    @Test("Messwert: Ereignisse ohne Wert und fremde Typen zählen nicht; ohne Messung gibt es keinen Messstatus")
    func measurementIgnoresOthers() {
        let noValue = MaintenanceEvent(gearID: chain, kind: .wearMeasured, performedAt: day(3))
        let other = MaintenanceEvent(gearID: chain, kind: .cleaned, performedAt: day(4), measurement: 9)
        #expect(report(chain, rules: [], events: [noValue, other], rides: [], now: day(20)).measurement == nil)
    }

    // MARK: Prognose

    @Test("Prognose nur mit ausreichend Daten und immer als Schätzung")
    func forecastNeedsEnoughData() {
        let rides = (0..<8).map { (day: $0 * 7, km: Double?(20)) }                  // 8 Fahrten über 7 Wochen, 160 km
        let r = report(rules: [rule(bike, .lubricated, .distance, 200_000)], rides: rides, now: day(50))
        // 160 km in 50 Tagen = 3,2 km/Tag, Rest 40 km → 12,5 → aufgerundet 13 Tage.
        #expect(r.forecast == Forecast(estimatedDaysUntilDue: 13, basisDays: 50))
        #expect(r.forecast?.isEstimate == true)
        let sparse = report(rules: [rule(bike, .lubricated, .distance, 200_000)], rides: [(40, 20), (48, 20)], now: day(50))
        #expect(sparse.forecast == nil)
    }

    @Test("Keine Prognose, wenn schon fällig, bei Kalenderregeln oder lückenhaften Distanzen")
    func forecastSkipped() {
        let rides = (0..<8).map { (day: $0 * 7, km: Double?(20)) }
        #expect(report(rules: [rule(bike, .lubricated, .distance, 100_000)], rides: rides, now: day(50)).forecast == nil)
        #expect(report(rules: [rule(bike, .lubricated, .calendarAge, 90)], rides: rides, now: day(50)).forecast == nil)
        let gappy = (0..<8).map { (day: $0 * 7, km: $0 == 3 ? nil : Double?(20)) }
        #expect(report(rules: [rule(bike, .lubricated, .distance, 400_000)], rides: gappy, now: day(50)).forecast == nil)
    }

    // MARK: Hinweise (max. 3, SPEC S02)

    @Test("Übersicht: höchstens drei Hinweise, fällige vor Vorwarnungen, danach größter Anteil; nichts Fälliges → leer")
    func topHintsLimitAndOrder() {
        func r(_ g: UUID, km: Double, interval: Double, lead: Double? = nil) -> GearMaintenanceReport {
            report(g, rules: [rule(g, .cleaned, .distance, interval, lead: lead)], rides: [(1, km)], now: day(5))
        }
        let reports = [
            r(bike, km: 90, interval: 100_000, lead: 20_000),   // Vorwarnung
            r(chain, km: 150, interval: 100_000),               // fällig, 150 %
            r(helmet, km: 100, interval: 100_000),              // fällig, 100 %
            r(shoes, km: 500, interval: 100_000),               // fällig, 500 %
            r(tires, km: 10, interval: 100_000),                // in Ordnung → kein Hinweis
        ]
        let hints = MaintenanceEvaluator.topHints(reports, limit: 3)
        #expect(hints.map(\.gearID) == [shoes, chain, helmet])
        #expect(hints.allSatisfy { $0.state == .due })
        #expect(MaintenanceEvaluator.topHints([reports[4]], limit: 3).isEmpty)
        let withWarn = MaintenanceEvaluator.topHints([reports[0], reports[2]], limit: 3)
        #expect(withWarn.map(\.state) == [.due, .dueSoon])
    }

    @Test("Messgrenze erreicht erzeugt einen Hinweis aus der Messung")
    func measurementHint() {
        let m = MaintenanceEvent(gearID: chain, kind: .wearMeasured, performedAt: day(3), measurement: 0.6)
        let r = report(chain, rules: [rule(chain, .wearMeasured, .distance, 0.5)], events: [m], rides: [], now: day(5))
        let hints = MaintenanceEvaluator.topHints([r], limit: 3)
        #expect(hints == [MaintenanceHint(gearID: chain, ruleID: nil, state: .due, source: .measurement)])
    }
}
