import Foundation
import GearCore
import Testing
@testable import Eingelaufen

/// M4: Posteingang, Korrektur aus dem Verlauf, Presets und Regeln als Befehle des einzigen Schreibers.
/// Prüft Bestand, Ledger, Summen und Outbox gemeinsam (ein Commit, Seiteneffekte erst danach).
private let cycling = SportCategory.cycling.defaultSportType

private struct World {
    let p: PersistenceActor
    let bikeA: GearItem, bikeB: GearItem, helmet: GearItem, shoes: GearItem
    let ride: ActivityRecord
    let pendingID: UUID
}

/// Zwei Fahrräder, Helm, Radschuhe, eine Fahrt mit offenem Vorschlag „Rad A“ (Revision 1).
private func world(state: PendingState = .suggested, proposal: [UUID]? = nil) async throws -> World {
    let p = try makePersistence()
    let bikeA = GearItem(name: "Rad A", createdAt: day(-100), category: .cycling, subtype: .roadBike)
    let bikeB = GearItem(name: "Rad B", createdAt: day(-99), category: .cycling, subtype: .roadBike)
    let helmet = GearItem(name: "Helm", createdAt: day(-98), category: .cycling)
    let shoes = GearItem(name: "Radschuhe", createdAt: day(-97), category: .cycling)
    let ride = ActivityRecord(source: .healthKit, sourceID: "W1", sportType: cycling, startAt: day(1),
                              endAt: day(1).addingTimeInterval(3_600), distanceMeters: 30_000, durationSeconds: 3_600)
    var d = GearDataset()
    d.gear = [bikeA, bikeB, helmet, shoes]
    d.statusChanges = d.gear.map { GearStatusChange(gearID: $0.id, status: .active, effectiveAt: day(-100)) }
    d.activities = [ride]
    let pending = PendingAssignment(activityID: ride.id, state: state, proposedGearIDs: proposal ?? [bikeA.id],
                                    alternatives: [[bikeB.id]], reason: .history, confidence: .medium, createdAt: day(1))
    d.pendings = [pending]
    try await p.load(d)
    return World(p: p, bikeA: bikeA, bikeB: bikeB, helmet: helmet, shoes: shoes, ride: ride, pendingID: pending.id)
}

@Suite struct InboxCommandTests {

    @Test func confirmBooksOnceWritesPendingAndLedgerInOneCommit() async throws {
        let w = try await world()
        _ = try await w.p.apply(.resolvePending(id: w.pendingID, action: .confirm(proposalRevision: 1), remember: false), now: day(2))
        let d = try await w.p.dataset()
        #expect(d.pendings.first?.state == .resolved && d.pendings.first?.resolution == .confirmedProposal)
        #expect(d.assignments.map(\.gearID) == [w.bikeA.id])
        #expect(d.assignments.first?.origin == .confirmedProposal && d.assignments.first?.createdAt == day(2))
        #expect(d.assignmentRules.isEmpty)
        #expect(try await w.p.ledger().filter { $0.gearID == w.bikeA.id }.count == 1)
        #expect(try await w.p.usage(of: w.bikeA.id).uses == 1)
        let outbox = try await w.p.outbox(pendingOnly: true)
        #expect(outbox.contains { $0.kind == .activityChanged && $0.subjectIDs.contains(w.ride.id) })
        #expect(outbox.contains { $0.kind == .pendingChanged && $0.subjectIDs == [w.pendingID] })
    }

    @Test func t10_repeatedConfirmDoesNotDoubleBook() async throws {
        let w = try await world()
        let confirm = GearCommand.resolvePending(id: w.pendingID, action: .confirm(proposalRevision: 1), remember: true)
        _ = try await w.p.apply(confirm, now: day(2))
        let outboxAfterFirst = try await w.p.outbox(pendingOnly: false).count
        _ = try await w.p.apply(confirm, now: day(3))
        _ = try await w.p.apply(confirm, now: day(4))
        let d = try await w.p.dataset()
        #expect(d.assignments.count == 1 && d.assignmentRules.count == 1)
        #expect(try await w.p.usage(of: w.bikeA.id).uses == 1)
        #expect(try await w.p.outbox(pendingOnly: false).count == outboxAfterFirst, "kein Seiteneffekt ohne Änderung")
    }

    @Test func staleRevisionChangesNothing() async throws {
        let w = try await world()
        _ = try await w.p.apply(.resolvePending(id: w.pendingID, action: .confirm(proposalRevision: 9), remember: true), now: day(2))
        let d = try await w.p.dataset()
        #expect(d.pendings.first?.state == .suggested && d.assignments.isEmpty && d.assignmentRules.isEmpty)
    }

    @Test func unknownPendingIsAnError() async throws {
        let w = try await world()
        await #expect(throws: PersistenceError.pendingNotFound) {
            _ = try await w.p.apply(.resolvePending(id: UUID(), action: .dismiss, remember: false), now: day(2))
        }
    }

    @Test func bikeHelmetAndShoesInOneDialogWithRemember() async throws {
        let w = try await world(state: .unresolved, proposal: [])
        _ = try await w.p.apply(.resolvePending(id: w.pendingID, action: .choose(gear: [w.bikeB.id, w.helmet.id, w.shoes.id]),
                                                remember: true), now: day(2))
        let d = try await w.p.dataset()
        #expect(Set(d.assignments.map(\.gearID)) == [w.bikeB.id, w.helmet.id, w.shoes.id])
        #expect(d.assignments.allSatisfy { $0.origin == .manual })
        #expect(d.assignmentRules.count == 1 && d.assignmentRules[0].kind == .remembered)
        #expect(Set(d.assignmentRules[0].gearIDs) == [w.bikeB.id, w.helmet.id, w.shoes.id])
        for g in [w.bikeB, w.helmet, w.shoes] { #expect(try await w.p.usage(of: g.id).uses == 1) }
        #expect(try await w.p.usage(of: w.bikeA.id).uses == 0)
    }

    @Test func dismissBooksNothingAndKeepsActivity() async throws {
        let w = try await world()
        _ = try await w.p.apply(.resolvePending(id: w.pendingID, action: .dismiss, remember: true), now: day(2))
        let d = try await w.p.dataset()
        #expect(d.pendings.first?.state == .dismissed && d.assignments.isEmpty && d.assignmentRules.isEmpty)
        let ledger = try await w.p.ledger()
        #expect(d.activities.count == 1 && ledger.isEmpty)
    }

    @Test func rememberedRuleAssignsTheNextImportedRide() async throws {
        let w = try await world()
        _ = try await w.p.apply(.resolvePending(id: w.pendingID, action: .confirm(proposalRevision: 1), remember: true), now: day(2))
        _ = try await w.p.apply(.connectHealth(.all), now: day(2))
        let next = IncomingWorkout(sourceID: "W2", sportType: cycling, startAt: day(5), endAt: day(5).addingTimeInterval(3_600),
                                   distanceMeters: 20_000, durationSeconds: 3_600)
        let importer = HealthImporter(source: DebugHealthSource(batches: [ImportBatch(upserts: [next])]), store: w.p, now: { day(6) })
        await importer.sync()
        let d = try await w.p.dataset()
        #expect(d.pendings.count == 1, "nur der erste Eintrag, die zweite Fahrt wird von der Regel zugeordnet")
        #expect(try await w.p.usage(of: w.bikeA.id).uses == 2)
    }

    @Test func t04_correctionFromHistoryMovesUsage() async throws {
        let w = try await world()
        _ = try await w.p.apply(.resolvePending(id: w.pendingID, action: .confirm(proposalRevision: 1), remember: false), now: day(2))
        #expect(try await w.p.usage(of: w.bikeA.id).uses == 1)
        _ = try await w.p.apply(.setActivityGear(activity: w.ride.id, gear: [w.bikeB.id]), now: day(3))
        #expect(try await w.p.usage(of: w.bikeA.id).uses == 0)
        #expect(try await w.p.usage(of: w.bikeB.id).uses == 1)
        let d = try await w.p.dataset()
        #expect(d.assignments.map(\.gearID) == [w.bikeB.id])
        // inkrementell == Neuaufbau
        let before = try await w.p.ledger()
        try await w.p.rebuildAll(now: day(4))
        #expect(try await w.p.ledger() == before)
    }

    @Test func correctionOfAnActivityWithOpenInboxEntryClosesTheEntry() async throws {
        let w = try await world()
        _ = try await w.p.apply(.setActivityGear(activity: w.ride.id, gear: [w.bikeB.id, w.helmet.id]), now: day(2))
        let d = try await w.p.dataset()
        #expect(d.pendings.first?.state == .resolved)
        #expect(Set(d.assignments.map(\.gearID)) == [w.bikeB.id, w.helmet.id] && d.assignments.count == 2)
        #expect(try await w.p.usage(of: w.helmet.id).uses == 1)
    }

    @Test func correctionToNoGearClearsAssignments() async throws {
        let w = try await world()
        _ = try await w.p.apply(.resolvePending(id: w.pendingID, action: .confirm(proposalRevision: 1), remember: false), now: day(2))
        _ = try await w.p.apply(.setActivityGear(activity: w.ride.id, gear: []), now: day(3))
        #expect(try await w.p.dataset().assignments.isEmpty)
        #expect(try await w.p.usage(of: w.bikeA.id).uses == 0)
    }

    @Test func correctionRejectsUnknownActivityOrGear() async throws {
        let w = try await world()
        await #expect(throws: PersistenceError.activityNotFound) {
            _ = try await w.p.apply(.setActivityGear(activity: UUID(), gear: []), now: day(2))
        }
        let ghost = UUID()
        await #expect(throws: PersistenceError.gearNotFound(ghost)) {
            _ = try await w.p.apply(.setActivityGear(activity: w.ride.id, gear: [w.bikeA.id, ghost]), now: day(2))
        }
    }
}

@Suite struct PresetRuleCommandTests {

    @Test func createPresetAndSetDefaultThenImportUsesIt() async throws {
        let w = try await world()
        _ = try await w.p.apply(.createPreset(name: " Rennrad ", sportTypes: [cycling],
                                              members: [w.bikeA.id, w.helmet.id, w.shoes.id]), now: day(2))
        var d = try await w.p.dataset()
        #expect(d.presets.count == 1 && d.presets[0].name == "Rennrad")
        let preset = d.presets[0].id
        _ = try await w.p.apply(.setDefaultPreset(sport: cycling, preset: preset), now: day(2))
        d = try await w.p.dataset()
        #expect(d.sportProfiles.first { $0.sportType == cycling }?.defaultPresetID == preset)

        _ = try await w.p.apply(.connectHealth(.all), now: day(2))
        let next = IncomingWorkout(sourceID: "W9", sportType: cycling, startAt: day(5), endAt: day(5).addingTimeInterval(3_600),
                                   distanceMeters: 20_000, durationSeconds: 3_600)
        await HealthImporter(source: DebugHealthSource(batches: [ImportBatch(upserts: [next])]), store: w.p, now: { day(6) }).sync()
        d = try await w.p.dataset()
        let created = try #require(d.activities.first { $0.sourceID == "W9" })
        #expect(Set(d.assignments.filter { $0.activityID == created.id }.map(\.gearID)) == [w.bikeA.id, w.helmet.id, w.shoes.id])
        #expect(d.assignments.filter { $0.activityID == created.id }.allSatisfy { $0.origin == .preset })
        #expect(try await w.p.usage(of: w.helmet.id).uses == 1)

        _ = try await w.p.apply(.removePreset(preset), now: day(7))
        d = try await w.p.dataset()
        #expect(d.presets.isEmpty && d.sportProfiles.first { $0.sportType == cycling }?.defaultPresetID == nil)
        #expect(d.assignments.filter { $0.activityID == created.id }.count == 3, "bestehende Zuordnungen bleiben")
    }

    @Test func invalidPresetIsRejected() async throws {
        let w = try await world()
        await #expect(throws: PersistenceError.preset(.emptyName)) {
            _ = try await w.p.apply(.createPreset(name: " ", sportTypes: [cycling], members: [w.bikeA.id]), now: day(2))
        }
        #expect(try await w.p.dataset().presets.isEmpty)
    }

    @Test func disableAndRemoveRuleStopAutomationButKeepHistory() async throws {
        let w = try await world()
        _ = try await w.p.apply(.resolvePending(id: w.pendingID, action: .confirm(proposalRevision: 1), remember: true), now: day(2))
        let rule = try #require(try await w.p.dataset().assignmentRules.first)
        _ = try await w.p.apply(.setAssignmentRuleEnabled(id: rule.id, enabled: false), now: day(3))
        #expect(try await w.p.dataset().assignmentRules.first?.enabled == false)
        _ = try await w.p.apply(.removeAssignmentRule(rule.id), now: day(4))
        let d = try await w.p.dataset()
        #expect(d.assignmentRules.isEmpty && d.assignments.count == 1, "die frühere Zuordnung bleibt")
        await #expect(throws: PersistenceError.ruleNotFound(rule.id)) {
            _ = try await w.p.apply(.removeAssignmentRule(rule.id), now: day(5))
        }
        #expect(try await w.p.outbox(pendingOnly: true).contains { $0.kind == .rulesChanged })
    }
}
