import Testing
import Foundation
@testable import GearCore

private let bike = id(1), chain = id(4), bike2 = id(5), chain2 = id(6)

private func query(_ input: LedgerInput, maintenance: [MaintenanceEvent] = [],
                   gear: [GearItem] = []) -> UsageQuery {
    UsageQuery(entries: LedgerBuilder.build(input).entries, installations: input.installations,
               maintenance: maintenance, gear: gear)
}

private func service(_ gear: UUID, _ kind: MaintenanceKind = .lubricated, at t: Date) -> MaintenanceEvent {
    MaintenanceEvent(gearID: gear, kind: kind, performedAt: t)
}

@Suite("UsageQuery (T-09, T-11, Lebensdauer, seit Einbau, Kalenderalter)")
struct UsageQueryTests {

    // MARK: Lebensdauer

    @Test("Lebensdauer summiert Distanz, Dauer und Anzahl aller Einträge")
    func lifetimeSums() {
        let r1 = activity(1, start: day(1), hours: 1, distance: 10_000)
        let r2 = activity(2, start: day(2), hours: 2, distance: 25_000)
        let q = query(LedgerInput(activities: [r1, r2], assignments: [assign(r1, bike), assign(r2, bike)]))
        #expect(q.lifetime(of: bike) == UsageSummary(
            uses: 2, distanceMeters: .measured(35_000, isComplete: true),
            durationSeconds: .measured(10_800, isComplete: true)))
    }

    @Test("Lebensdauer ohne jede Nutzung: 0 Nutzungen und gemessene 0 (nichts zu verbuchen)")
    func lifetimeUnused() {
        let q = query(LedgerInput())
        #expect(q.lifetime(of: bike) == UsageSummary(
            uses: 0, distanceMeters: .measured(0, isComplete: true),
            durationSeconds: .measured(0, isComplete: true)))
    }

    @Test("T-09: nur Einträge ohne Distanz → „Keine Daten“, nicht 0 km")
    func t09_allNilIsNoData() {
        let r = activity(1, start: day(1), distance: nil)
        let q = query(LedgerInput(activities: [r], assignments: [assign(r, bike)]))
        #expect(q.lifetime(of: bike).distanceMeters == .noData)
        #expect(q.lifetime(of: bike).uses == 1)
        #expect(q.lifetime(of: bike).durationSeconds == .measured(3_600, isComplete: true))
    }

    @Test("Teilweise fehlende Distanz → Summe als unvollständig gekennzeichnet, nicht still zu klein")
    func partialNilIsIncomplete() {
        let r1 = activity(1, start: day(1), distance: 10_000)
        let r2 = activity(2, start: day(2), distance: nil)
        let q = query(LedgerInput(activities: [r1, r2], assignments: [assign(r1, bike), assign(r2, bike)]))
        #expect(q.lifetime(of: bike).distanceMeters == .measured(10_000, isComplete: false))
        #expect(q.lifetime(of: bike).uses == 2)
    }

    @Test("Lebensdauer einer Komponente umfasst frühere Montagen (Kette wandert von Rad zu Rad)")
    func lifetimeSpansInstallations() {
        let r1 = activity(1, start: day(2)), r2 = activity(2, start: day(7))
        let input = LedgerInput(
            activities: [r1, r2], assignments: [assign(r1, bike), assign(r2, bike2)],
            installations: [mount(chain, in: bike, from: day(0), to: day(5)),
                            mount(chain, in: bike2, from: day(5))])
        #expect(query(input).lifetime(of: chain).uses == 2)
    }

    // MARK: Seit Einbau

    @Test("Seit Einbau zählt nur ab Beginn der aktuellen Montage, Lebensdauer bleibt")
    func sinceInstallationCountsFromCurrentMount() {
        let before = activity(1, start: day(2)), after = activity(2, start: day(8))
        let input = LedgerInput(
            activities: [before, after],
            assignments: [assign(before, chain), assign(after, bike)],
            installations: [mount(chain, in: bike, from: day(5))])
        let q = query(input)
        guard case let .value(summary) = q.sinceInstallation(of: chain) else {
            Issue.record("erwartet: Wert"); return
        }
        #expect(summary.uses == 1)
        #expect(q.lifetime(of: chain).uses == 2)
    }

    @Test("Wieder eingebaute Komponente: seit Einbau zählt ab der jüngsten Montage (P-03)")
    func sinceInstallationAfterReinstall() {
        let r1 = activity(1, start: day(2)), r2 = activity(2, start: day(12))
        let input = LedgerInput(
            activities: [r1, r2], assignments: [assign(r1, bike), assign(r2, bike)],
            installations: [mount(chain, in: bike, from: day(0), to: day(5)),
                            mount(chain, in: bike, from: day(10))])
        guard case let .value(summary) = query(input).sinceInstallation(of: chain) else {
            Issue.record("erwartet: Wert"); return
        }
        #expect(summary.uses == 1)
    }

    @Test("Nicht montiert → kein Wert (weder 0 noch Lebensdauer)")
    func sinceInstallationNotInstalled() {
        let r = activity(1, start: day(2))
        let ended = LedgerInput(
            activities: [r], assignments: [assign(r, bike)],
            installations: [mount(chain, in: bike, from: day(0), to: day(5))])
        #expect(query(ended).sinceInstallation(of: chain) == .notInstalled)
        #expect(query(LedgerInput()).sinceInstallation(of: chain2) == .notInstalled)
    }

    // MARK: Seit Wartung

    @Test("T-11: Wartung setzt nur „seit Wartung“ zurück, nicht die Lebensdauer")
    func t11_maintenanceResetsOnlySinceMaintenance() {
        let r1 = activity(1, start: day(2), distance: 100_000)
        let r2 = activity(2, start: day(8), distance: 20_000)
        let input = LedgerInput(activities: [r1, r2], assignments: [assign(r1, chain), assign(r2, chain)])
        let q = query(input, maintenance: [service(chain, .lubricated, at: day(5))])

        guard case let .value(since) = q.sinceMaintenance(of: chain, kind: .lubricated) else {
            Issue.record("erwartet: Wert"); return
        }
        #expect(since.uses == 1)
        #expect(since.distanceMeters == .measured(20_000, isComplete: true))
        #expect(q.lifetime(of: chain).distanceMeters == .measured(120_000, isComplete: true))
    }

    @Test("T-11: Wartung einer Art lässt „seit Wartung“ anderer Arten unberührt")
    func t11_otherKindsUnaffected() {
        let r = activity(1, start: day(8))
        let input = LedgerInput(activities: [r], assignments: [assign(r, chain)])
        let q = query(input, maintenance: [service(chain, .lubricated, at: day(5))])
        #expect(q.sinceMaintenance(of: chain, kind: .inspected) == .noMaintenanceRecorded(.inspected))
    }

    @Test("T-11: Wartung eines anderen Gegenstands wirkt nicht")
    func t11_otherGearUnaffected() {
        let q = query(LedgerInput(), maintenance: [service(chain2, .lubricated, at: day(5))])
        #expect(q.sinceMaintenance(of: chain, kind: .lubricated) == .noMaintenanceRecorded(.lubricated))
    }

    @Test("Maßgeblich ist das jüngste Ereignis der Art, unabhängig von der Eingabereihenfolge (rückdatiert erfasst)")
    func latestEventWinsRegardlessOfOrder() {
        let r1 = activity(1, start: day(4)), r2 = activity(2, start: day(8))
        let input = LedgerInput(activities: [r1, r2], assignments: [assign(r1, chain), assign(r2, chain)])
        let q = query(input, maintenance: [service(chain, at: day(6)), service(chain, at: day(3))])
        guard case let .value(since) = q.sinceMaintenance(of: chain, kind: .lubricated) else {
            Issue.record("erwartet: Wert"); return
        }
        #expect(since.uses == 1)   // nur Tag 8, nicht Tag 4
    }

    @Test("Training genau zum Wartungszeitpunkt zählt noch zur Zeit davor (t > performedAt)")
    func activityAtMaintenanceInstantIsBefore() {
        let r = activity(1, start: day(5))
        let input = LedgerInput(activities: [r], assignments: [assign(r, chain)])
        guard case let .value(since) = query(input, maintenance: [service(chain, at: day(5))])
            .sinceMaintenance(of: chain, kind: .lubricated) else {
            Issue.record("erwartet: Wert"); return
        }
        #expect(since.uses == 0)
    }

    @Test("Seit Wartung ohne Folgenutzung: 0 Nutzungen, gemessene 0")
    func sinceMaintenanceWithoutFollowUp() {
        let q = query(LedgerInput(), maintenance: [service(chain, at: day(5))])
        #expect(q.sinceMaintenance(of: chain, kind: .lubricated) == .value(UsageSummary(
            uses: 0, distanceMeters: .measured(0, isComplete: true), durationSeconds: .measured(0, isComplete: true))))
    }

    // MARK: Kalenderalter

    @Test("Kalenderalter ab Kaufdatum ist gemessen")
    func calendarAgeFromPurchase() {
        let item = GearItem(id: bike, name: "Rad", purchaseDate: day(0))
        let q = query(LedgerInput(), gear: [item])
        #expect(q.calendarAgeDays(of: bike, now: day(10, hour: 5)) == .measured(10, isComplete: true))
    }

    @Test("Ohne Kaufdatum: Schätzung ab erster Montage, gekennzeichnet")
    func calendarAgeEstimateFromInstallation() {
        let input = LedgerInput(installations: [mount(chain, in: bike, from: day(4))])
        let q = query(input, gear: [GearItem(id: chain, name: "Kette")])
        #expect(q.calendarAgeDays(of: chain, now: day(10)) == .estimate(6, basis: .firstInstallation))
    }

    @Test("Ohne Kaufdatum und Montage: Schätzung ab erster Nutzung")
    func calendarAgeEstimateFromUsage() {
        let r = activity(1, start: day(3))
        let q = query(LedgerInput(activities: [r], assignments: [assign(r, bike)]))
        #expect(q.calendarAgeDays(of: bike, now: day(10)) == .estimate(7, basis: .firstUsage))
    }

    @Test("Weder Kaufdatum, Montage noch Nutzung → Keine Daten")
    func calendarAgeNoData() {
        #expect(query(LedgerInput()).calendarAgeDays(of: bike, now: day(10)) == .noData)
    }

    @Test("Kalenderalter ist nie negativ (Kaufdatum in der Zukunft)")
    func calendarAgeNeverNegative() {
        let item = GearItem(id: bike, name: "Rad", purchaseDate: day(20))
        #expect(query(LedgerInput(), gear: [item]).calendarAgeDays(of: bike, now: day(10))
                == .measured(0, isComplete: true))
    }
}
