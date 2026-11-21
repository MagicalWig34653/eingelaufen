import Testing
import Foundation
@testable import GearCore

private let bike = id(1), chain = id(4), bike2 = id(5), helmet = id(7)

/// Deterministischer Zufall (SplitMix64) – feste Seeds, keine Systemzufälligkeit.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("LedgerProjection (I-10: inkrementell == Neuaufbau)")
struct LedgerProjectionTests {

    @Test("Neue Zuordnung berechnet nur die betroffene Aktivität neu")
    func assignmentRecomputesOnlyThatActivity() {
        let r1 = activity(1, start: day(1)), r2 = activity(2, start: day(2)), r3 = activity(3, start: day(3))
        var projection = LedgerProjection(input: LedgerInput(activities: [r1, r2, r3]))
        projection.apply(.upsertAssignment(assign(r2, bike)))
        #expect(projection.lastRecomputedActivityCount == 1)
        #expect(projection.entries.map(\.activityID) == [r2.id])
    }

    @Test("T-04: Korrektur A → B über die Projektion: A sinkt, B steigt")
    func t04_reassignmentViaProjection() {
        let ride = activity(1, start: day(3))
        let onA = assign(ride, bike)
        var projection = LedgerProjection(input: LedgerInput(activities: [ride], assignments: [onA]))
        #expect(projection.entries.map(\.gearID) == [bike])

        projection.apply(.removeAssignment(onA.id))
        projection.apply(.upsertAssignment(assign(ride, bike2)))
        #expect(projection.entries.map(\.gearID) == [bike2])
    }

    @Test("Rückdatierter Umbau berechnet nur Aktivitäten im betroffenen Zeitfenster neu")
    func backdatedInstallationRecomputesWindowOnly() {
        let early = activity(1, start: day(1)), inWindow = activity(2, start: day(6)), late = activity(3, start: day(30))
        let assignments = [assign(early, bike), assign(inWindow, bike), assign(late, bike)]
        var projection = LedgerProjection(input: LedgerInput(
            activities: [early, inWindow, late], assignments: assignments))

        projection.apply(.upsertInstallation(mount(chain, in: bike, from: day(5), to: day(10))))
        #expect(projection.lastRecomputedActivityCount == 1)
        #expect(projection.entries.filter { $0.gearID == chain }.map(\.activityID) == [inWindow.id])
    }

    @Test("Gelöschte Aktivität entfernt ihre Einträge (T-07-Kern, I-08)")
    func deletingActivityRemovesEntries() {
        let ride = activity(1, start: day(3))
        var projection = LedgerProjection(input: LedgerInput(activities: [ride], assignments: [assign(ride, bike)]))
        var deleted = ride
        deleted.deletedAt = day(4)
        projection.apply(.upsertActivity(deleted))
        #expect(projection.entries.isEmpty)

        projection.apply(.upsertActivity(ride))     // Wiederherstellung
        #expect(projection.entries.count == 1)
        projection.apply(.removeActivity(ride.id))  // hart entfernt, Zuordnung bleibt dangling
        #expect(projection.entries.isEmpty)
    }

    @Test("T-06-Kern: geänderte Distanz/Dauer derselben Aktivität wird übernommen")
    func updatedActivityValuesAreReflected() {
        let ride = activity(1, start: day(3), distance: 10_000)
        var projection = LedgerProjection(input: LedgerInput(activities: [ride], assignments: [assign(ride, bike)]))
        var changed = ride
        changed.distanceMeters = 12_500
        changed.durationSeconds = 4_000
        projection.apply(.upsertActivity(changed))
        #expect(projection.entries.count == 1)
        #expect(projection.entries[0].distanceMeters == 12_500)
        #expect(projection.entries[0].durationSeconds == 4_000)
    }

    @Test("rebuildAll liefert denselben Stand wie der inkrementelle Verlauf")
    func rebuildAllMatches() {
        let ride = activity(1, start: day(3))
        var projection = LedgerProjection()
        projection.apply(.upsertActivity(ride))
        projection.apply(.upsertAssignment(assign(ride, bike)))
        projection.apply(.upsertInstallation(mount(chain, in: bike, from: day(0))))
        let incremental = projection.entries
        projection.rebuildAll()
        #expect(projection.entries == incremental)
        #expect(incremental.count == 2)
    }

    // MARK: Eigenschaftstest I-10

    private static func randomChange(_ g: inout SeededGenerator) -> LedgerChange {
        let gear = (1...8).map { id($0) }
        func pickGear(_ g: inout SeededGenerator) -> UUID { gear.randomElement(using: &g)! }
        func slot(_ range: ClosedRange<Int>, _ g: inout SeededGenerator) -> Int { Int.random(in: range, using: &g) }
        func randomDay(_ g: inout SeededGenerator) -> Date { day(slot(0...30, &g), hour: slot(0...23, &g)) }

        switch slot(0...9, &g) {
        case 0, 1:   // Aktivität anlegen/ändern, teils gelöscht, teils ohne Distanz
            let start = randomDay(&g)
            let hours = Double(slot(1...3, &g))
            return .upsertActivity(ActivityRecord(
                id: id(1_000 + slot(1...10, &g)), sportType: cycling, startAt: start,
                endAt: start.addingTimeInterval(hours * 3_600),
                distanceMeters: slot(0...2, &g) == 0 ? nil : Double(slot(1...50, &g)) * 1_000,
                durationSeconds: hours * 3_600,
                deletedAt: slot(0...5, &g) == 0 ? randomDay(&g) : nil))
        case 2:
            return .removeActivity(id(1_000 + slot(1...10, &g)))
        case 3:      // Segment
            let start = randomDay(&g)
            return .upsertSegment(ActivitySegment(
                id: id(2_000 + slot(1...6, &g)), activityID: id(1_000 + slot(1...10, &g)), sportType: run,
                startAt: start, endAt: start.addingTimeInterval(1_800),
                distanceMeters: slot(0...1, &g) == 0 ? nil : Double(slot(1...9, &g)) * 1_000))
        case 4:
            return .removeSegment(id(2_000 + slot(1...6, &g)))
        case 5, 6:   // Zuordnung (aktivitäts- oder segmentebene, teils ungültig)
            return .upsertAssignment(ActivityGearAssignment(
                id: id(3_000 + slot(1...25, &g)), activityID: id(1_000 + slot(1...10, &g)),
                segmentID: slot(0...2, &g) == 0 ? id(2_000 + slot(1...6, &g)) : nil, gearID: pickGear(&g)))
        case 7:
            return .removeAssignment(id(3_000 + slot(1...25, &g)))
        case 8:      // Montage, absichtlich auch ungültige/überlappende/zyklische Daten
            let start = randomDay(&g)
            return .upsertInstallation(Installation(
                id: id(4_000 + slot(1...10, &g)), parentGearID: pickGear(&g), childGearID: pickGear(&g),
                startedAt: start, endedAt: slot(0...1, &g) == 0 ? nil : randomDay(&g)))
        default:
            return .removeInstallation(id(4_000 + slot(1...10, &g)))
        }
    }

    @Test("I-10: inkrementelle Aktualisierung == vollständiger Neuaufbau (400 Folgen à 40 Befehle, fester Seed)")
    func i10_incrementalEqualsRebuild() {
        for sequence in 0..<400 {
            var g = SeededGenerator(seed: 0x2026_1121 &+ UInt64(sequence))
            var projection = LedgerProjection()
            for step in 0..<40 {
                let change = Self.randomChange(&g)
                projection.apply(change)
                let expected = LedgerBuilder.build(projection.input).entries
                if projection.entries != expected {
                    Issue.record("Folge \(sequence), Schritt \(step): \(change) – inkrementell \(projection.entries.count) ≠ Neuaufbau \(expected.count)")
                    return
                }
            }
        }
    }
}
