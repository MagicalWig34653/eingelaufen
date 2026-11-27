import Testing
import Foundation
@testable import GearCore

// M4: Posteingang auf Datensatz-Ebene (SPEC 6.3, 7.1, S05). Der Resolver lädt den Eintrag aus dem Bestand,
// reduziert ihn und liefert Eintrag, Zuordnungen und – nur auf Wunsch – die gemerkte Regel für EINEN Commit.

private let shoesA = id(1), shoesB = id(2), bikeA = id(3), bikeB = id(4), helmet = id(6), cycShoes = id(7)
private let now = day(30)

private final class Ids: @unchecked Sendable {
    private var n: Int
    init(start: Int = 40_000) { n = start }
    func next() -> UUID { n += 1; return id(n) }
}

private func item(_ n: UUID, _ category: SportCategory, created: Int = 0) -> GearItem {
    GearItem(id: n, name: "G\(n.uuidString.suffix(2))", createdAt: day(created), category: category)
}

/// Zwei Fahrräder, eine Fahrt (id 1_001) mit offenem Vorschlag (id 500).
private func twoBikes(state: PendingState = .suggested, deleted: Bool = false) -> GearDataset {
    var d = GearDataset()
    d.gear = [item(bikeA, .cycling), item(bikeB, .cycling, created: 1), item(helmet, .cycling, created: 2),
              item(cycShoes, .cycling, created: 3)]
    d.activities = [activity(1, start: day(5), deleted: deleted ? day(6) : nil)]
    d.pendings = [PendingAssignment(id: id(500), activityID: id(1_001), state: state, proposedGearIDs: [bikeA],
                                    alternatives: [[bikeB]], reason: .history, confidence: .medium,
                                    proposalRevision: 1, createdAt: day(5))]
    return d
}

private func resolve(_ d: GearDataset, _ action: InboxAction, remember: Bool = false,
                     pending: UUID = id(500), ids: Ids = Ids()) -> InboxResolution? {
    InboxResolver.resolve(pending, action: action, remember: remember, in: d, now: now, makeID: ids.next)
}

@Suite("InboxResolver (Spec 6.3, 7.1, S05)")
struct InboxResolverTests {

    @Test("Bestätigen mit „merken“: eine Zuordnung, Eintrag erledigt, eine nachvollziehbare Regel")
    func confirmAndRemember() throws {
        let out = try #require(resolve(twoBikes(), .confirm(proposalRevision: 1), remember: true))
        #expect(out.result == .applied)
        #expect(out.pending.state == .resolved && out.pending.resolution == .confirmedProposal)
        #expect(out.assignments.map(\.gearID) == [bikeA])
        let rule = try #require(out.rule)
        #expect(rule.kind == .remembered && rule.sportType == cycling && rule.gearIDs == [bikeA] && rule.enabled)
        #expect(rule.createdAt == now)
    }

    @Test("Ohne „merken“ entsteht keine Regel")
    func noRuleWithoutRemember() throws {
        let out = try #require(resolve(twoBikes(), .confirm(proposalRevision: 1)))
        #expect(out.result == .applied && out.rule == nil)
    }

    @Test("„Fahrrad + Helm + Schuhe“ in einem Dialog: drei Zuordnungen, eine Regel mit allen dreien")
    func chooseSeveralAtOnce() throws {
        let out = try #require(resolve(twoBikes(state: .unresolved), .choose(gear: [bikeB, helmet, cycShoes]), remember: true))
        #expect(out.pending.state == .resolved && out.pending.resolution == .chosen)
        #expect(out.assignments.map(\.gearID) == [bikeB, helmet, cycShoes])
        #expect(out.assignments.allSatisfy { $0.origin == .manual && $0.activityID == id(1_001) })
        #expect(Set(try #require(out.rule).gearIDs) == [bikeB, helmet, cycShoes])
    }

    @Test("„Nicht zuordnen“ bucht nichts und merkt nichts, auch wenn „merken“ gesetzt war")
    func dismissNeverRemembers() throws {
        let out = try #require(resolve(twoBikes(), .dismiss, remember: true))
        #expect(out.pending.state == .dismissed)
        #expect(out.assignments.isEmpty && out.rule == nil)
    }

    @Test("„Später“ lässt den Eintrag offen und merkt nichts")
    func laterKeepsOpen() throws {
        let out = try #require(resolve(twoBikes(), .later, remember: true))
        #expect(out.pending.state == .ignored && !out.pending.state.isFinal)
        #expect(out.assignments.isEmpty && out.rule == nil)
    }

    @Test("T-10: Zweite Bestätigung bucht nichts und merkt nichts (idempotent)")
    func secondConfirmIsNoOp() throws {
        let first = try #require(resolve(twoBikes(), .confirm(proposalRevision: 1), remember: true))
        let after = InboxResolver.apply(first, to: twoBikes())
        let second = try #require(resolve(after, .confirm(proposalRevision: 1), remember: true))
        #expect(second.result == .noOp(.alreadyFinal(.resolved)))
        #expect(second.assignments.isEmpty && second.rule == nil)
        let both = InboxResolver.apply(second, to: after)
        #expect(both == after)
        let ledger = LedgerBuilder.build(both.ledgerInput).entries.filter { $0.gearID == bikeA }
        #expect(ledger.count == 1, "genau ein Nutzungsbeitrag")
    }

    @Test("Veraltete Revision: nichts gebucht, nichts gemerkt, Eintrag offen")
    func staleRevision() throws {
        let out = try #require(resolve(twoBikes(), .confirm(proposalRevision: 7), remember: true))
        #expect(out.result == .noOp(.staleRevision))
        #expect(out.assignments.isEmpty && out.rule == nil && out.pending.state == .suggested)
    }

    @Test("Unbekannter Eintrag liefert nil")
    func unknownPending() {
        #expect(resolve(twoBikes(), .dismiss, pending: id(999)) == nil)
    }

    @Test("Unbekannter Gegenstand in der Auswahl wird abgewiesen, nichts wird geschrieben")
    func unknownGearRejected() throws {
        let out = try #require(resolve(twoBikes(), .choose(gear: [bikeA, id(77)]), remember: true))
        #expect(out.result == .noOp(.unknownGear))
        #expect(out.assignments.isEmpty && out.rule == nil && out.pending.state == .suggested)
    }

    @Test("Gelöschtes Training: Eintrag wird hinfällig, es wird nichts gebucht")
    func deletedActivityBecomesObsolete() throws {
        let out = try #require(resolve(twoBikes(deleted: true), .confirm(proposalRevision: 1), remember: true))
        #expect(out.pending.state == .obsolete)
        #expect(out.assignments.isEmpty && out.rule == nil)
    }

    @Test("Gibt es die gleiche aktive Regel schon, wird nichts doppelt gemerkt, die Zuordnung gilt trotzdem")
    func duplicateRuleSkipped() throws {
        var d = twoBikes()
        d.assignmentRules = [AssignmentRule(id: id(800), sportType: cycling, kind: .remembered, gearIDs: [bikeA])]
        let out = try #require(resolve(d, .confirm(proposalRevision: 1), remember: true))
        #expect(out.assignments.count == 1 && out.rule == nil)
    }

    @Test("apply schreibt Eintrag, Zuordnungen und Regel in den Bestand und lässt alles andere unberührt")
    func applyWritesAll() throws {
        let d = twoBikes()
        let out = try #require(resolve(d, .confirm(proposalRevision: 1), remember: true))
        let next = InboxResolver.apply(out, to: d)
        #expect(next.pendings.first?.state == .resolved)
        #expect(next.assignments.map(\.gearID) == [bikeA])
        #expect(next.assignmentRules.count == 1)
        #expect(next.gear == d.gear && next.activities == d.activities)
    }

    @Test("E2E: gemerkte Regel ordnet die nächste ähnliche Fahrt beim Import ohne Nachfrage zu")
    func rememberedRuleDrivesNextImport() throws {
        let d = twoBikes()
        let out = try #require(resolve(d, .confirm(proposalRevision: 1), remember: true))
        let learned = InboxResolver.apply(out, to: d)
        let incoming = IncomingWorkout(sourceID: "W-NEXT", sportType: cycling, startAt: day(12),
                                       endAt: day(12).addingTimeInterval(3_600), distanceMeters: 20_000, durationSeconds: 3_600)
        let ids = Ids(start: 60_000)
        let result = ImportReconciler.reconcile(learned, ImportBatch(upserts: [incoming]), now: now, makeID: ids.next)
        let next = try #require(result.dataset.activities.first { $0.sourceID == "W-NEXT" })
        #expect(result.autoAssigned == [next.id], "Regel wirkt ohne Nachfrage")
        #expect(result.pendingCreated.isEmpty)
        #expect(result.dataset.assignments.filter { $0.activityID == next.id }.map(\.gearID) == [bikeA])
        // Und die abgeschlossene Fahrt bleibt unverändert (kein rückwirkendes Hinzufügen, SPEC 6.3).
        #expect(result.dataset.assignments.filter { $0.activityID == id(1_001) }.count == 1)
    }

    @Test("T-04 über den Posteingang: Korrektur A → B nach Bestätigung, Nutzung A sinkt, B steigt")
    func correctionAfterConfirm() throws {
        let d = twoBikes()
        let confirmed = InboxResolver.apply(try #require(resolve(d, .confirm(proposalRevision: 1))), to: d)
        let fix = AssignmentCorrection.reassign(activityID: id(1_001), from: bikeA, to: bikeB,
                                                current: confirmed.assignments, now: now, makeID: Ids(start: 70_000).next)
        var projection = LedgerProjection(input: confirmed.ledgerInput)
        for change in fix { projection.apply(change) }
        let usage = UsageQuery(entries: projection.entries, installations: [])
        #expect(usage.lifetime(of: bikeA).uses == 0)
        #expect(usage.lifetime(of: bikeB).uses == 1)
    }
}

@Suite("InboxQuery (Spec S05)")
struct InboxQueryTests {

    @Test("Offene Einträge: unresolved, suggested und ignored, neueste Aktivität zuerst; Endzustände und gelöschte Trainings fehlen")
    func openEntries() {
        var d = GearDataset()
        d.gear = [item(bikeA, .cycling)]
        d.activities = [activity(1, start: day(1)), activity(2, start: day(3)), activity(3, start: day(2)),
                        activity(4, start: day(4)), activity(5, start: day(5), deleted: day(6))]
        func p(_ n: Int, _ state: PendingState) -> PendingAssignment {
            PendingAssignment(id: id(500 + n), activityID: id(1_000 + n), state: state, createdAt: day(n))
        }
        d.pendings = [p(1, .suggested), p(2, .unresolved), p(3, .resolved), p(4, .ignored), p(5, .suggested),
                      PendingAssignment(id: id(599), activityID: id(1_777), state: .suggested)]
        let open = InboxQuery.open(in: d)
        #expect(open.map(\.pending.id) == [id(504), id(502), id(501)])
        #expect(open.map(\.activity.id) == [id(1_004), id(1_002), id(1_001)])
    }

    @Test("Zählung für die Übersicht entspricht der Liste")
    func count() {
        var d = twoBikes()
        #expect(InboxQuery.openCount(in: d) == 1)
        d.pendings[0].state = .resolved
        #expect(InboxQuery.openCount(in: d) == 0)
    }
}
