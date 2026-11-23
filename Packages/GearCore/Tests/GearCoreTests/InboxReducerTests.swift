import Testing
import Foundation
@testable import GearCore

private let shoesA = id(1), shoesB = id(2), bikeA = id(3), helmet = id(6)

/// Zähler als ID-Quelle: deterministisch, ohne Zufall.
private final class Ids: @unchecked Sendable {
    private var n = 9_000
    func next() -> UUID { n += 1; return id(n) }
}

private func suggested(_ gear: [UUID] = [bikeA], revision: Int = 1) -> PendingAssignment {
    PendingAssignment(id: id(500), activityID: id(1_001), state: .suggested, proposedGearIDs: gear,
                      alternatives: [[helmet]], reason: .history, confidence: .medium, proposalRevision: revision,
                      createdAt: day(1))
}

private func reduce(_ p: PendingAssignment, _ action: InboxAction, ids: Ids = Ids()) -> InboxOutcome {
    InboxReducer.reduce(p, action, now: day(9), makeID: ids.next)
}

@Suite("InboxReducer (Spec 7.1, I-09, T-10)")
struct InboxReducerTests {

    @Test("Vorschlag bestätigen: suggested → resolved, genau eine Zuordnung je Gegenstand, Ursprung confirmedProposal")
    func confirmResolves() {
        let out = reduce(suggested([bikeA, helmet]), .confirm(proposalRevision: 1))
        #expect(out.result == .applied)
        #expect(out.pending.state == .resolved)
        #expect(out.pending.resolution == .confirmedProposal)
        #expect(out.assignments.map(\.gearID) == [bikeA, helmet])
        #expect(out.assignments.allSatisfy { $0.activityID == id(1_001) && $0.origin == .confirmedProposal && $0.segmentID == nil })
        #expect(out.assignments.allSatisfy { $0.createdAt == day(9) })
    }

    @Test("T-10: Wiederholte Notification-Aktion wirkt höchstens einmal")
    func t10_repeatedActionAppliesAtMostOnce() {
        let ids = Ids()
        let first = reduce(suggested(), .confirm(proposalRevision: 1), ids: ids)
        let second = reduce(first.pending, .confirm(proposalRevision: 1), ids: ids)
        let third = reduce(second.pending, .confirm(proposalRevision: 1), ids: ids)
        #expect(first.assignments.count == 1)
        #expect(second.assignments.isEmpty && third.assignments.isEmpty)
        #expect(second.result == .noOp(.alreadyFinal(.resolved)))
        #expect(second.pending == first.pending && third.pending == first.pending)

        // Gebucht wird tatsächlich nur einmal im Ledger.
        let ride = activity(1, start: day(3))
        var pending = suggested(); pending.activityID = ride.id
        let a = reduce(pending, .confirm(proposalRevision: 1), ids: ids)
        let b = reduce(a.pending, .confirm(proposalRevision: 1), ids: ids)
        let ledger = LedgerBuilder.build(LedgerInput(activities: [ride], assignments: a.assignments + b.assignments))
        #expect(ledger.entries.filter { $0.gearID == bikeA }.count == 1)
    }

    @Test("T-10: Veraltete Notification (anderer Vorschlagsstand) bucht nichts, der Eintrag bleibt offen")
    func t10_staleRevisionIgnored() {
        let changed = reduce(suggested(), .propose(gear: [helmet], alternatives: [], reason: .multipleCandidates, confidence: .low))
        #expect(changed.pending.proposalRevision == 2)
        let stale = reduce(changed.pending, .confirm(proposalRevision: 1))
        #expect(stale.result == .noOp(.staleRevision))
        #expect(stale.assignments.isEmpty)
        #expect(stale.pending == changed.pending)
        #expect(reduce(changed.pending, .confirm(proposalRevision: 2)).assignments.map(\.gearID) == [helmet])
    }

    @Test("Bestätigen ohne Vorschlag ist nicht möglich")
    func confirmNeedsProposal() {
        let open = PendingAssignment(id: id(500), activityID: id(1_001), state: .unresolved,
                                     candidateGearIDs: [shoesA, shoesB], reason: .multipleCandidates)
        let out = reduce(open, .confirm(proposalRevision: 1))
        #expect(out.result == .noOp(.invalidTransition))
        #expect(out.pending == open && out.assignments.isEmpty)
    }

    @Test("Auswählen aus unresolved: mehrere Gegenstände in einem Schritt, Ursprung manual")
    func chooseMultipleAtOnce() {
        let open = PendingAssignment(id: id(500), activityID: id(1_001), state: .unresolved,
                                     candidateGearIDs: [bikeA, helmet], reason: .multipleCandidates)
        let out = reduce(open, .choose(gear: [bikeA, helmet, bikeA]))
        #expect(out.pending.state == .resolved && out.pending.resolution == .chosen)
        #expect(out.assignments.map(\.gearID) == [bikeA, helmet], "doppelte Auswahl wird zusammengefasst")
        #expect(out.assignments.allSatisfy { $0.origin == .manual })
        #expect(out.pending.proposalRevision == open.proposalRevision + 1)
    }

    @Test("Leere Auswahl ist keine Entscheidung; „Nicht zuordnen“ ist eine")
    func emptyChoiceVersusDismiss() {
        let p = suggested()
        #expect(reduce(p, .choose(gear: [])).result == .noOp(.emptySelection))
        let out = reduce(p, .dismiss)
        #expect(out.pending.state == .dismissed && out.pending.resolution == .dismissed && out.assignments.isEmpty)
    }

    @Test("„Später“ lässt den Eintrag im Posteingang und erhält den Vorschlag; danach noch bestätigbar")
    func laterKeepsItInInbox() {
        let later = reduce(suggested(), .later)
        #expect(later.pending.state == .ignored)
        #expect(later.pending.proposedGearIDs == [bikeA])
        #expect(later.pending.proposalRevision == 1)
        #expect(reduce(later.pending, .later).result == .noOp(.invalidTransition))
        #expect(reduce(later.pending, .confirm(proposalRevision: 1)).pending.state == .resolved)
        #expect(reduce(later.pending, .dismiss).pending.state == .dismissed)
    }

    @Test("Neuer Vorschlag aus unresolved erhöht die Revision; aus ignored kehrt der Eintrag als Vorschlag zurück")
    func proposeFromOpenStates() {
        let open = PendingAssignment(id: id(500), activityID: id(1_001), state: .unresolved, candidateGearIDs: [shoesA, shoesB])
        let a = reduce(open, .propose(gear: [shoesA], alternatives: [[shoesB]], reason: .history, confidence: .medium))
        #expect(a.pending.state == .suggested && a.pending.proposalRevision == 2 && a.pending.proposedGearIDs == [shoesA])
        let ignored = reduce(a.pending, .later).pending
        let b = reduce(ignored, .propose(gear: [shoesB], alternatives: [], reason: .history, confidence: .medium))
        #expect(b.pending.state == .suggested && b.pending.proposalRevision == 3)
    }

    @Test("Endzustände sind gegen jede erneute Aktion idempotent (I-09)")
    func finalStatesAreIdempotent() {
        let actions: [InboxAction] = [
            .confirm(proposalRevision: 1), .choose(gear: [shoesA]), .dismiss, .later, .markObsolete,
            .propose(gear: [shoesA], alternatives: [], reason: .history, confidence: .medium), .notified,
        ]
        for state in [PendingState.resolved, .dismissed, .obsolete] {
            var p = suggested(); p.state = state
            for action in actions {
                let out = reduce(p, action)
                #expect(out.pending == p, "\(state) darf sich nicht ändern: \(action)")
                #expect(out.assignments.isEmpty)
                #expect(out.result == .noOp(.alreadyFinal(state)))
            }
        }
    }

    @Test("Training gelöscht: offene Einträge werden obsolete, ein bereits aufgelöster bleibt aufgelöst (T-07)")
    func markObsolete() {
        for state in [PendingState.unresolved, .suggested, .ignored] {
            var p = suggested(); p.state = state
            let out = reduce(p, .markObsolete)
            #expect(out.pending.state == .obsolete && out.pending.resolution == .obsolete)
            #expect(out.assignments.isEmpty)
        }
        var done = suggested(); done.state = .resolved
        #expect(reduce(done, .markObsolete).pending.state == .resolved)
    }

    @Test("Zustellung vermerkt nur den Zeitpunkt, ändert weder Zustand noch Revision")
    func notifiedOnlyStampsTime() {
        let out = reduce(suggested(), .notified)
        #expect(out.pending.lastPromptAt == day(9))
        #expect(out.pending.state == .suggested && out.pending.proposalRevision == 1)
    }
}

@Suite("Korrektur und Regel-Lernen (SPEC 6.3, T-04)")
struct CorrectionTests {

    @Test("T-04: Zuordnung A → B korrigiert: Nutzung bei A sinkt, bei B steigt")
    func t04_reassignMovesUsage() {
        let ride = activity(1, start: day(3))
        let original = ActivityGearAssignment(id: id(7_001), activityID: ride.id, gearID: shoesA)
        var projection = LedgerProjection(input: LedgerInput(activities: [ride], assignments: [original]))
        func uses(_ g: UUID) -> Int { projection.entries.filter { $0.gearID == g }.map(\.uses).reduce(0, +) }
        #expect(uses(shoesA) == 1 && uses(shoesB) == 0)

        let changes = AssignmentCorrection.reassign(activityID: ride.id, from: shoesA, to: shoesB,
                                                    current: [original], now: day(9), makeID: Ids().next)
        for change in changes { projection.apply(change) }
        #expect(uses(shoesA) == 0 && uses(shoesB) == 1)

        var rebuilt = LedgerProjection(input: projection.input)
        rebuilt.rebuildAll()
        #expect(projection.entries == rebuilt.entries, "inkrementell == Neuaufbau (I-10)")
    }

    @Test("Korrektur auf einen bereits zugeordneten Gegenstand verdoppelt nichts")
    func reassignToAlreadyAssignedDoesNotDouble() {
        let ride = activity(1, start: day(3))
        let a = ActivityGearAssignment(id: id(7_001), activityID: ride.id, gearID: shoesA)
        let b = ActivityGearAssignment(id: id(7_002), activityID: ride.id, gearID: shoesB)
        let changes = AssignmentCorrection.reassign(activityID: ride.id, from: shoesA, to: shoesB,
                                                    current: [a, b], now: day(9), makeID: Ids().next)
        #expect(changes == [.removeAssignment(a.id)])
    }

    @Test("Gesamtauswahl setzen: nur Unterschiede werden zu Änderungen, Segmentzuordnungen bleiben unberührt")
    func setAssignmentsDiffs() {
        let ride = activity(1, start: day(3))
        let seg = ActivitySegment(id: id(3_001), activityID: ride.id, sportType: cycling, startAt: day(3), endAt: day(3, hour: 1))
        let keep = ActivityGearAssignment(id: id(7_001), activityID: ride.id, gearID: bikeA)
        let drop = ActivityGearAssignment(id: id(7_002), activityID: ride.id, gearID: shoesA)
        let onSegment = ActivityGearAssignment(id: id(7_003), activityID: ride.id, segmentID: seg.id, gearID: helmet)
        let changes = AssignmentCorrection.setAssignments(activityID: ride.id, gear: [bikeA, helmet],
                                                          current: [keep, drop, onSegment], now: day(9), makeID: Ids().next)
        #expect(changes.contains(.removeAssignment(drop.id)))
        #expect(!changes.contains(.removeAssignment(keep.id)))
        #expect(!changes.contains(.removeAssignment(onSegment.id)))
        let added = changes.compactMap { change -> ActivityGearAssignment? in
            if case let .upsertAssignment(a) = change { return a } else { return nil }
        }
        #expect(added.map(\.gearID) == [helmet])
        #expect(added.first?.origin == .manual)
    }

    @Test("„Für ähnliche Aktivitäten merken“ erzeugt eine nachvollziehbare, abschaltbare Regel")
    func rememberCreatesTraceableRule() throws {
        let ride = activity(1, start: day(3))
        let rule = try #require(RuleLearning.rememberRule(for: ride, gear: [bikeA], existing: [], now: day(9), id: id(8_001)))
        #expect(rule.kind == .remembered && rule.enabled)
        #expect(rule.sportType == ride.sportType && rule.gearIDs == [bikeA])
        #expect(rule.createdAt == day(9))
        #expect(rule.conditions == RuleConditions())
        // Indoor wird nur übernommen, wenn belegt (SPEC 3.3).
        var indoor = ride; indoor.isIndoor = true
        let withIndoor = try #require(RuleLearning.rememberRule(for: indoor, gear: [bikeA], existing: [], now: day(9), id: id(8_002)))
        #expect(withIndoor.conditions.isIndoor == true)
    }

    @Test("Eine gleiche aktive Regel wird nicht doppelt angelegt; Auswahl ohne Gegenstand erzeugt keine Regel")
    func rememberDeduplicates() {
        let ride = activity(1, start: day(3))
        let existing = AssignmentRule(sportType: ride.sportType, kind: .remembered, gearIDs: [bikeA])
        #expect(RuleLearning.rememberRule(for: ride, gear: [bikeA], existing: [existing], now: day(9)) == nil)
        #expect(RuleLearning.rememberRule(for: ride, gear: [], existing: [], now: day(9)) == nil)
        var off = existing; off.enabled = false
        #expect(RuleLearning.rememberRule(for: ride, gear: [bikeA], existing: [off], now: day(9)) != nil)
    }

    @Test("Gewohnheit zählt nur ausdrückliche Bestätigungen, keine Automatik")
    func historyCountsOnlyUserConfirmations() {
        var d = GearDataset()
        let a1 = activity(1, start: day(1)), a2 = activity(2, start: day(2)), a3 = activity(3, start: day(3))
        d.activities = [a1, a2, a3]
        d.assignments = [
            ActivityGearAssignment(activityID: a1.id, gearID: bikeA, origin: .confirmedProposal, createdAt: day(1)),
            ActivityGearAssignment(activityID: a2.id, gearID: bikeA, origin: .manual, createdAt: day(2)),
            ActivityGearAssignment(activityID: a3.id, gearID: shoesA, origin: .rule, createdAt: day(3)),
        ]
        let history = AssignmentHistory.confirmed(from: d)
        #expect(history.count == 2)
        #expect(history.allSatisfy { $0.gearIDs == [bikeA] && $0.sportType == cycling })
    }
}
