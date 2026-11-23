import Foundation
import GearCore
import Testing
@testable import Eingelaufen

/// Manuelle Aktivität (SPEC 6.4): macht die App ohne HealthKit nutzbar, durchläuft dieselbe Ledger-Logik.
@Suite struct ManualActivityTests {
    private func setup() async throws -> (PersistenceActor, bike: GearItem, shoes: GearItem) {
        let p = try makePersistence()
        let bike = GearItem(name: "Rennrad", createdAt: t0, category: .cycling, subtype: .roadBike)
        let shoes = GearItem(name: "Radschuhe", createdAt: t0, category: .cycling)
        _ = try await p.apply(.createGear(bike), now: t0)
        _ = try await p.apply(.createGear(shoes), now: t0)
        return (p, bike, shoes)
    }

    private func ride(_ id: UUID = UUID(), start: Date, minutes: Double = 60, km: Double? = 30, gear: [UUID]) -> ManualActivityInput {
        ManualActivityInput(id: id, sportType: SportCategory.cycling.defaultSportType, startAt: start,
                            durationSeconds: minutes * 60, distanceMeters: km.map { $0 * 1_000 }, gearIDs: gear)
    }

    @Test func manualActivityBooksEachAssignedGearExactlyOnce() async throws {
        let (p, bike, shoes) = try await setup()
        let a = ride(start: day(1), gear: [bike.id, shoes.id])
        let outcome = try await p.apply(.addManualActivity(a), now: day(2))
        #expect(outcome.activityID == a.id)

        let ds = try await p.dataset()
        #expect(ds.activities.count == 1)
        #expect(ds.activities[0].source == .manual)
        #expect(ds.activities[0].sourceID == nil)
        #expect(ds.activities[0].endAt == day(1).addingTimeInterval(3_600))
        #expect(Set(ds.assignments.map(\.gearID)) == [bike.id, shoes.id])
        #expect(ds.assignments.allSatisfy { $0.origin == .manual && $0.segmentID == nil })

        let ledger = try await p.ledger()
        #expect(ledger.count == 2)
        for g in [bike, shoes] {
            let u = try await p.usage(of: g.id)
            #expect(u.uses == 1)
            #expect(u.distanceMeters == .measured(30_000, isComplete: true))
            #expect(u.durationSeconds == .measured(3_600, isComplete: true))
        }
    }

    @Test func missingDistanceStaysNilAndMakesSumsIncomplete() async throws {
        let (p, bike, _) = try await setup()
        _ = try await p.apply(.addManualActivity(ride(start: day(1), km: nil, gear: [bike.id])), now: day(2))
        var u = try await p.usage(of: bike.id)
        #expect(u.distanceMeters == .noData, "T-09: keine Distanz → „Keine Daten“, nicht 0")
        #expect(u.durationSeconds == .measured(3_600, isComplete: true))
        #expect(try await p.dataset().activities[0].distanceMeters == nil)

        _ = try await p.apply(.addManualActivity(ride(start: day(3), km: 20, gear: [bike.id])), now: day(4))
        u = try await p.usage(of: bike.id)
        #expect(u.uses == 2)
        #expect(u.distanceMeters == .measured(20_000, isComplete: false), "SPEC 5.2: Untergrenze statt stillem Weniger")
    }

    @Test func activityWithoutGearIsValidAndBooksNothing() async throws {
        let (p, bike, _) = try await setup()
        _ = try await p.apply(.addManualActivity(ride(start: day(1), gear: [])), now: day(2))
        #expect(try await p.dataset().activities.count == 1)
        #expect(try await p.ledger().isEmpty)
        #expect(try await p.usage(of: bike.id).uses == 0)
        #expect(try await p.dataset().pendings.isEmpty)
    }

    @Test func differentSportsAreUsableSideBySide() async throws {
        let p = try makePersistence()
        let shoes = GearItem(name: "Laufschuhe", createdAt: t0, category: .running)
        let racket = GearItem(name: "Schläger", createdAt: t0, category: .racketSports)
        _ = try await p.apply(.createGear(shoes), now: t0)
        _ = try await p.apply(.createGear(racket), now: t0)
        let run = ManualActivityInput(sportType: SportCategory.running.defaultSportType, startAt: day(1),
                                      durationSeconds: 1_800, distanceMeters: 5_000, gearIDs: [shoes.id])
        let tennis = ManualActivityInput(sportType: SportCategory.racketSports.defaultSportType, startAt: day(2),
                                         durationSeconds: 3_600, distanceMeters: nil, gearIDs: [racket.id])
        _ = try await p.apply(.addManualActivity(run), now: day(3))
        _ = try await p.apply(.addManualActivity(tennis), now: day(3))
        #expect(try await p.usage(of: shoes.id).distanceMeters == .measured(5_000, isComplete: true))
        #expect(try await p.usage(of: racket.id).distanceMeters == .noData)
        #expect(try await p.usage(of: racket.id).uses == 1)
    }

    @Test func duplicateGearIDsAreCountedOnce() async throws {
        let (p, bike, _) = try await setup()
        _ = try await p.apply(.addManualActivity(ride(start: day(1), gear: [bike.id, bike.id])), now: day(2))
        #expect(try await p.dataset().assignments.count == 1)
        #expect(try await p.usage(of: bike.id).uses == 1)
    }

    @Test func archivedGearKeepsItsHistory() async throws {
        let (p, bike, _) = try await setup()
        _ = try await p.apply(.addManualActivity(ride(start: day(1), gear: [bike.id])), now: day(2))
        _ = try await p.apply(.setGearStatus(id: bike.id, status: .archived, effectiveAt: day(5)), now: day(5))
        #expect(try await p.usage(of: bike.id).uses == 1)
        #expect(try await p.ledger().count == 1)
    }

    @Test func invalidInputIsRejectedAndNothingIsStored() async throws {
        let (p, bike, _) = try await setup()
        let before = try await p.outbox(pendingOnly: false).count
        let unknown = UUID()
        let cases: [(ManualActivityInput, PersistenceError)] = [
            (ride(start: day(1), minutes: 0, gear: [bike.id]), .invalidDuration),
            (ride(start: day(1), minutes: -5, gear: [bike.id]), .invalidDuration),
            (ride(start: day(1), km: -1, gear: [bike.id]), .invalidDistance),
            (ride(start: day(1), gear: [unknown]), .gearNotFound(unknown)),
            (ride(start: day(30), gear: [bike.id]), .startsInFuture),
        ]
        for (input, expected) in cases {
            await #expect(throws: expected) { _ = try await p.apply(.addManualActivity(input), now: day(2)) }
        }
        #expect(try await p.dataset().activities.isEmpty)
        #expect(try await p.dataset().assignments.isEmpty)
        #expect(try await p.ledger().isEmpty)
        #expect(try await p.outbox(pendingOnly: false).count == before, "Fehlgeschlagene Befehle schreiben keine Outbox")
    }

    @Test func sameActivityIDTwiceIsRejected() async throws {
        let (p, bike, _) = try await setup()
        let id = UUID()
        _ = try await p.apply(.addManualActivity(ride(id, start: day(1), gear: [bike.id])), now: day(2))
        await #expect(throws: PersistenceError.activityAlreadyExists(id)) {
            _ = try await p.apply(.addManualActivity(ride(id, start: day(1), gear: [bike.id])), now: day(2))
        }
        #expect(try await p.usage(of: bike.id).uses == 1)
    }

    @Test func incrementalLedgerEqualsFullRebuild() async throws {
        // I-10: inkrementell == Neuaufbau, mit festem Seed (kein Zufall der Systemuhr).
        let (p, bike, shoes) = try await setup()
        var seed: UInt64 = 42
        func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed >> 33 }
        for i in 0..<25 {
            let gear: [UUID] = [bike.id, shoes.id].filter { _ in next() % 2 == 0 }
            let km: Double? = next() % 3 == 0 ? nil : Double(next() % 80)
            _ = try await p.apply(.addManualActivity(ride(start: day(Double(i) / 2), minutes: Double(10 + next() % 120), km: km, gear: gear)), now: day(30))
            if i == 10 { _ = try await p.apply(.setGearStatus(id: shoes.id, status: .stored, effectiveAt: day(5)), now: day(30)) }
        }
        let ledgerBefore = try await p.ledger()
        let usageBefore = [try await p.usage(of: bike.id), try await p.usage(of: shoes.id)]
        try await p.rebuildAll()
        #expect(try await p.ledger() == ledgerBefore)
        #expect([try await p.usage(of: bike.id), try await p.usage(of: shoes.id)] == usageBefore)
    }
}
