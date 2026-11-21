import Testing
import Foundation
@testable import GearCore

// Gear-IDs: 1 Fahrrad, 2 Laufradsatz, 3 Reifen, 4 Kette, 5 zweites Fahrrad, 6 neue Kette, 7 Helm
private let bike = id(1), wheel = id(2), tire = id(3), chain = id(4), bike2 = id(5), chain2 = id(6), helmet = id(7)

private func entries(_ result: LedgerResult, gear: UUID) -> [UsageLedgerEntry] {
    result.entries.filter { $0.gearID == gear }
}

@Suite("LedgerBuilder (T-01…T-04, T-08, T-09, I-04, I-05, I-08)")
struct LedgerBuilderTests {

    @Test("T-01: Training + Fahrrad + montierte Kette → Fahrrad und Kette je genau einmal")
    func t01_bikeAndMountedChainOnce() {
        let ride = activity(1, start: day(3))
        let input = LedgerInput(
            activities: [ride], assignments: [assign(ride, bike)],
            installations: [mount(chain, in: bike, from: day(0))])
        let result = LedgerBuilder.build(input)

        #expect(result.entries.count == 2)
        for gear in [bike, chain] {
            let e = entries(result, gear: gear)
            #expect(e.count == 1)
            #expect(e.first?.uses == 1)
            #expect(e.first?.distanceMeters == 10_000)
            #expect(e.first?.durationSeconds == 3_600)
            #expect(e.first?.derivationVersion == LedgerBuilder.derivationVersion)
            #expect(e.first?.occurredAt == day(3))
        }
        #expect(result.issues.isEmpty)
    }

    @Test("T-02: Kette gewechselt → Training vorher zählt für die alte, nachher für die neue Kette")
    func t02_chainReplacementIsTimeCorrect() {
        let before = activity(1, start: day(3))
        let after = activity(2, start: day(7))
        let input = LedgerInput(
            activities: [before, after],
            assignments: [assign(before, bike), assign(after, bike)],
            installations: [
                mount(chain, in: bike, from: day(0), to: day(5)),
                mount(chain2, in: bike, from: day(5)),
            ])
        let result = LedgerBuilder.build(input)

        #expect(entries(result, gear: chain).map(\.activityID) == [before.id])
        #expect(entries(result, gear: chain2).map(\.activityID) == [after.id])
        #expect(entries(result, gear: bike).count == 2)
    }

    @Test("T-02: Wechsel-Zeitpunkt exakt am Trainingsbeginn → gehört zur neuen Kette (halb offen)")
    func t02_boundaryBelongsToNewInstallation() {
        let atSwap = activity(1, start: day(5))
        let input = LedgerInput(
            activities: [atSwap], assignments: [assign(atSwap, bike)],
            installations: [
                mount(chain, in: bike, from: day(0), to: day(5)),
                mount(chain2, in: bike, from: day(5)),
            ])
        let result = LedgerBuilder.build(input)
        #expect(entries(result, gear: chain).isEmpty)
        #expect(entries(result, gear: chain2).count == 1)
    }

    @Test("T-02: rückdatierter Umbau wirkt auf frühere Aktivitäten, gestriges Training nicht auf neue Kette")
    func t02_activityBeforeInstallDoesNotCountForNewPart() {
        let yesterday = activity(1, start: day(9))
        let input = LedgerInput(
            activities: [yesterday], assignments: [assign(yesterday, bike)],
            installations: [mount(chain2, in: bike, from: day(10))])
        #expect(entries(LedgerBuilder.build(input), gear: chain2).isEmpty)

        // Wird der Umbau auf Tag 8 zurückdatiert, zählt die Aktivität (Neuberechnung aus Wahrheitsdaten).
        let backdated = LedgerInput(
            activities: [yesterday], assignments: [assign(yesterday, bike)],
            installations: [mount(chain2, in: bike, from: day(8))])
        #expect(entries(LedgerBuilder.build(backdated), gear: chain2).count == 1)
    }

    @Test("T-03: direkt zugeordnete und über das Fahrrad vererbte Kette → keine Doppelzählung")
    func t03_directPlusInheritedIsCountedOnce() {
        let ride = activity(1, start: day(3))
        let input = LedgerInput(
            activities: [ride], assignments: [assign(ride, bike), assign(ride, chain)],
            installations: [mount(chain, in: bike, from: day(0))])
        let result = LedgerBuilder.build(input)
        #expect(entries(result, gear: chain).count == 1)
        #expect(entries(result, gear: chain).first?.uses == 1)
        #expect(result.entries.count == 2)
    }

    @Test("T-03: doppelte Zuordnungszeilen desselben Gegenstands ergeben einen Eintrag")
    func t03_duplicateAssignmentRows() {
        let ride = activity(1, start: day(3))
        let input = LedgerInput(activities: [ride], assignments: [assign(ride, bike), assign(ride, bike)])
        #expect(LedgerBuilder.build(input).entries.count == 1)
    }

    @Test("T-04: Zuordnung von A auf B korrigiert → A sinkt, B steigt")
    func t04_reassignmentMovesUsage() {
        let ride = activity(1, start: day(3))
        let onA = LedgerInput(activities: [ride], assignments: [assign(ride, bike)])
        let onB = LedgerInput(activities: [ride], assignments: [assign(ride, bike2)])
        let first = LedgerBuilder.build(onA), second = LedgerBuilder.build(onB)

        #expect(entries(first, gear: bike).count == 1 && entries(first, gear: bike2).isEmpty)
        #expect(entries(second, gear: bike).isEmpty && entries(second, gear: bike2).count == 1)
    }

    @Test("Vererbung läuft über mehrere Ebenen (Fahrrad → Laufradsatz → Reifen)")
    func inheritanceIsTransitive() {
        let ride = activity(1, start: day(3))
        let input = LedgerInput(
            activities: [ride], assignments: [assign(ride, bike)],
            installations: [
                mount(wheel, in: bike, from: day(0)),
                mount(tire, in: wheel, from: day(0)),
            ])
        #expect(Set(LedgerBuilder.build(input).entries.map(\.gearID)) == [bike, wheel, tire])
    }

    @Test("Keine Vererbung zwischen unabhängigen Gegenständen: Fahrrad ⇒ nie automatisch Helm (SPEC 5.2)")
    func noInheritanceBetweenIndependentGear() {
        let ride = activity(1, start: day(3))
        let input = LedgerInput(activities: [ride], assignments: [assign(ride, bike)])
        #expect(entries(LedgerBuilder.build(input), gear: helmet).isEmpty)
    }

    @Test("Ausgebaute Komponente erhält nichts, auch wenn sie später woanders montiert ist")
    func removedComponentGetsNothing() {
        let ride = activity(1, start: day(3))
        let input = LedgerInput(
            activities: [ride], assignments: [assign(ride, bike)],
            installations: [
                mount(chain, in: bike, from: day(0), to: day(2)),
                mount(chain, in: bike2, from: day(2)),
            ])
        #expect(entries(LedgerBuilder.build(input), gear: chain).isEmpty)
    }

    @Test("T-09: Aktivität ohne Distanz → Ledger-Distanz bleibt nil, nicht 0")
    func t09_nilDistanceStaysNil() {
        let ride = activity(1, start: day(3), distance: nil)
        let input = LedgerInput(activities: [ride], assignments: [assign(ride, bike)])
        let e = LedgerBuilder.build(input).entries
        #expect(e.count == 1)
        #expect(e.first?.distanceMeters == nil)
        #expect(e.first?.durationSeconds == 3_600)
    }

    @Test("T-08: Multisport ohne Segmentdistanz → keine erfundene Distanz, keine Verteilung nach Dauer")
    func t08_noInventedSegmentDistance() {
        let multi = activity(1, start: day(3), hours: 3, distance: 30_000)
        let swim = ActivitySegment(id: id(2_001), activityID: multi.id, sportType: run,
                                   startAt: day(3), endAt: day(3, hour: 1), distanceMeters: nil)
        let bikeLeg = ActivitySegment(id: id(2_002), activityID: multi.id, sportType: cycling,
                                      startAt: day(3, hour: 1), endAt: day(3, hour: 3), distanceMeters: 28_000)
        let input = LedgerInput(
            activities: [multi], segments: [swim, bikeLeg],
            assignments: [assign(multi, helmet, segment: swim), assign(multi, bike, segment: bikeLeg)])
        let result = LedgerBuilder.build(input)

        let onSwim = result.entries.first { $0.segmentID == swim.id }
        let onBike = result.entries.first { $0.segmentID == bikeLeg.id }
        #expect(onSwim?.distanceMeters == nil)         // nicht 10 km (1/3 der Dauer)
        #expect(onSwim?.durationSeconds == 3_600)
        #expect(onBike?.distanceMeters == 28_000)      // echte Segmentdistanz, nicht Rest/Verteilung
        #expect(onBike?.occurredAt == day(3, hour: 1)) // Montagezuordnung nach Segmentbeginn
    }

    @Test("Aktivitätsebene nutzt die Aktivitätsdistanz, auch wenn Segmente existieren")
    func activityLevelUsesActivityDistance() {
        let multi = activity(1, start: day(3), hours: 2, distance: 20_000)
        let leg = ActivitySegment(id: id(2_001), activityID: multi.id, sportType: run,
                                  startAt: day(3), endAt: day(3, hour: 1), distanceMeters: nil)
        let input = LedgerInput(activities: [multi], segments: [leg], assignments: [assign(multi, bike)])
        let e = LedgerBuilder.build(input).entries
        #expect(e.count == 1 && e[0].segmentID == nil && e[0].distanceMeters == 20_000)
    }

    @Test("I-05: gleicher Gegenstand auf Aktivitäts- und Segmentebene → nur Aktivitätsebene, Problem wird gemeldet")
    func i05_activityLevelWinsOverSegment() {
        let multi = activity(1, start: day(3), hours: 2, distance: 20_000)
        let leg = ActivitySegment(id: id(2_001), activityID: multi.id, sportType: run,
                                  startAt: day(3), endAt: day(3, hour: 1), distanceMeters: 5_000)
        let input = LedgerInput(
            activities: [multi], segments: [leg],
            assignments: [assign(multi, bike), assign(multi, bike, segment: leg)])
        let result = LedgerBuilder.build(input)
        #expect(result.entries.count == 1)
        #expect(result.entries[0].segmentID == nil)
        #expect(result.issues == [.segmentDuplicatesActivityLevel(activityID: multi.id, segmentID: leg.id, gearID: bike)])
    }

    @Test("P-02: derselbe Gegenstand in zwei Segmenten → zwei Einträge (verschiedene Segmente)")
    func p02_sameGearInTwoSegments() {
        let multi = activity(1, start: day(3), hours: 2, distance: nil)
        let a = ActivitySegment(id: id(2_001), activityID: multi.id, sportType: run,
                                startAt: day(3), endAt: day(3, hour: 1), distanceMeters: 4_000)
        let b = ActivitySegment(id: id(2_002), activityID: multi.id, sportType: run,
                                startAt: day(3, hour: 1), endAt: day(3, hour: 2), distanceMeters: 5_000)
        let input = LedgerInput(
            activities: [multi], segments: [a, b],
            assignments: [assign(multi, helmet, segment: a), assign(multi, helmet, segment: b)])
        let e = LedgerBuilder.build(input).entries
        #expect(e.count == 2)
        #expect(e.compactMap(\.distanceMeters).reduce(0, +) == 9_000)
    }

    @Test("I-08: gelöschte Aktivität erzeugt keine Ledger-Einträge")
    func i08_deletedActivityHasNoEntries() {
        let gone = activity(1, start: day(3), deleted: day(4))
        let input = LedgerInput(activities: [gone], assignments: [assign(gone, bike)],
                                installations: [mount(chain, in: bike, from: day(0))])
        let result = LedgerBuilder.build(input)
        #expect(result.entries.isEmpty)
        #expect(result.issues.isEmpty)
    }

    @Test("Zuordnung zu unbekannter Aktivität oder fremdem Segment wird ignoriert und gemeldet")
    func danglingAssignmentsAreReported() {
        let ride = activity(1, start: day(3))
        let other = activity(2, start: day(4))
        let foreignSegment = ActivitySegment(id: id(2_001), activityID: other.id, sportType: run,
                                             startAt: day(4), endAt: day(4, hour: 1))
        let orphan = ActivityGearAssignment(activityID: id(9_999), gearID: bike)
        let wrongSegment = ActivityGearAssignment(activityID: ride.id, segmentID: foreignSegment.id, gearID: bike)
        let input = LedgerInput(activities: [ride, other], segments: [foreignSegment],
                                assignments: [orphan, wrongSegment])
        let result = LedgerBuilder.build(input)
        #expect(result.entries.isEmpty)
        #expect(Set(result.issues) == [.assignmentForUnknownActivity(assignmentID: orphan.id),
                                       .assignmentForUnknownSegment(assignmentID: wrongSegment.id)])
    }

    @Test("Ausgabe ist deterministisch sortiert und unabhängig von der Eingabereihenfolge")
    func outputIsDeterministic() {
        let r1 = activity(1, start: day(3)), r2 = activity(2, start: day(4))
        let a = LedgerInput(activities: [r1, r2],
                            assignments: [assign(r1, bike), assign(r2, bike2), assign(r1, helmet)],
                            installations: [mount(chain, in: bike, from: day(0)), mount(wheel, in: bike2, from: day(0))])
        let b = LedgerInput(activities: [r2, r1],
                            assignments: [assign(r1, helmet), assign(r2, bike2), assign(r1, bike)],
                            installations: [mount(wheel, in: bike2, from: day(0)), mount(chain, in: bike, from: day(0))])
        #expect(LedgerBuilder.build(a).entries == LedgerBuilder.build(b).entries)
        #expect(LedgerBuilder.build(a).entries.map(\.key) == LedgerBuilder.build(a).entries.map(\.key).sorted())
    }

    @Test("`only` berechnet nur die genannten Aktivitäten")
    func onlyRestrictsToGivenActivities() {
        let r1 = activity(1, start: day(3)), r2 = activity(2, start: day(4))
        let input = LedgerInput(activities: [r1, r2], assignments: [assign(r1, bike), assign(r2, bike)])
        let partial = LedgerBuilder.build(input, only: [r2.id])
        #expect(partial.entries.map(\.activityID) == [r2.id])
    }
}
