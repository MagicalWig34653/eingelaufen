import Testing
import Foundation
@testable import GearCore

private let shoesA = id(1), shoesB = id(2), bikeA = id(3), bikeB = id(4)
private let now = day(30)

private final class Ids: @unchecked Sendable {
    private var n: Int
    init(start: Int = 20_000) { n = start }
    func next() -> UUID { n += 1; return id(n) }
}

private func item(_ n: UUID, _ category: SportCategory, created: Int = 0) -> GearItem {
    GearItem(id: n, name: "G\(n.uuidString.suffix(2))", createdAt: day(created), category: category)
}

private func workout(_ sourceID: String, start: Date, hours: Double = 1, distance: Double? = 10_000,
                     sport: SportType = run, indoor: Bool? = nil) -> IncomingWorkout {
    IncomingWorkout(sourceID: sourceID, sportType: sport, startAt: start, endAt: start.addingTimeInterval(hours * 3_600),
                    distanceMeters: distance, durationSeconds: hours * 3_600, isIndoor: indoor)
}

/// Der Startwert folgt dem Datenstand, damit aufeinanderfolgende Läufe nie dieselbe UUID vergeben (Datensätze
/// wachsen nur, Löschung = Tombstone) und gleiche Eingaben trotzdem gleiche IDs ergeben.
private func reconcile(_ d: GearDataset, _ batch: ImportBatch) -> ReconcileOutput {
    let ids = Ids(start: 20_000 + 1_000 * (d.activities.count + d.assignments.count + d.pendings.count))
    return ImportReconciler.reconcile(d, batch, now: now, makeID: ids.next)
}

private func twoShoes() -> GearDataset {
    var d = GearDataset()
    d.gear = [item(shoesA, .running), item(shoesB, .running)]
    return d
}

private func ledger(_ d: GearDataset) -> [UsageLedgerEntry] { LedgerBuilder.build(d.ledgerInput).entries }
private func active(_ d: GearDataset) -> [ActivityRecord] { d.activities.filter { $0.deletedAt == nil } }

@Suite("ImportReconciler (T-05, T-06, T-07, I-07, I-08, P-05)")
struct ImportReconcilerTests {

    // MARK: T-05 Idempotenz

    @Test("T-05: Derselbe Import mehrfach liefert genau einen ActivityRecord je Quell-ID und ändert nichts mehr")
    func t05_importIsIdempotent() {
        var d = GearDataset(); d.gear = [item(shoesA, .running)]
        let batch = ImportBatch(upserts: [workout("W1", start: day(1)), workout("W2", start: day(2))])
        let first = reconcile(d, batch)
        let second = reconcile(first.dataset, batch)
        let third = reconcile(second.dataset, batch)

        #expect(first.dataset.activities.count == 2)
        #expect(Set(first.dataset.activities.compactMap(\.sourceID)) == ["W1", "W2"])
        #expect(second.isUnchanged && third.isUnchanged)
        #expect(second.dataset == first.dataset && third.dataset == first.dataset)
        #expect(ledger(third.dataset) == ledger(first.dataset), "Nutzungsbeiträge ändern sich nicht")
        #expect(second.ledgerChanges.isEmpty && second.mergeSuggestions.isEmpty)
    }

    @Test("T-05: Doppelte Quell-ID im selben Batch zählt einmal (der letzte Stand gewinnt)")
    func t05_duplicateInBatch() {
        let batch = ImportBatch(upserts: [workout("W1", start: day(1), hours: 1), workout("W1", start: day(1), hours: 2)])
        let out = reconcile(twoShoes(), batch)
        #expect(active(out.dataset).count == 1)
        #expect(active(out.dataset).first?.durationSeconds == 7_200)
    }

    @Test("Die Reihenfolge der Eingabe ändert das Ergebnis nicht")
    func orderIndependent() {
        let a = workout("W1", start: day(1)), b = workout("W2", start: day(2)), c = workout("W3", start: day(3))
        let one = reconcile(twoShoes(), ImportBatch(upserts: [a, b, c]))
        let two = reconcile(twoShoes(), ImportBatch(upserts: [c, a, b]))
        #expect(one.dataset == two.dataset)
    }

    // MARK: T-06 Änderungen

    @Test("T-06: Geändertes Training (gleiche UUID) aktualisiert Dauer und Distanz, Zuordnungen bleiben")
    func t06_changedWorkoutUpdatesInPlace() throws {
        var d = GearDataset(); d.gear = [item(shoesA, .running)]
        let first = reconcile(d, ImportBatch(upserts: [workout("W1", start: day(1), hours: 1, distance: 10_000)]))
        let original = try #require(first.dataset.activities.first)
        #expect(first.dataset.assignments.map(\.gearID) == [shoesA])

        let changed = reconcile(first.dataset, ImportBatch(upserts: [workout("W1", start: day(1), hours: 2, distance: 21_000)]))
        let updated = try #require(changed.dataset.activities.first)
        #expect(changed.dataset.activities.count == 1)
        #expect(updated.id == original.id && updated.revision == original.revision + 1)
        #expect(updated.durationSeconds == 7_200 && updated.distanceMeters == 21_000)
        #expect(changed.dataset.assignments == first.dataset.assignments)
        #expect(changed.updated == [original.id])
        let entry = try #require(ledger(changed.dataset).first { $0.gearID == shoesA })
        #expect(entry.distanceMeters == 21_000 && entry.durationSeconds == 7_200 && entry.uses == 1)
    }

    @Test("T-06: Fällt die Distanz im Update weg, bleibt sie nil und wird nicht 0 (SPEC 5.2)")
    func t06_distanceBecomesNilNotZero() throws {
        var d = GearDataset(); d.gear = [item(shoesA, .running)]
        let first = reconcile(d, ImportBatch(upserts: [workout("W1", start: day(1), distance: 10_000)]))
        let changed = reconcile(first.dataset, ImportBatch(upserts: [workout("W1", start: day(1), distance: nil)]))
        #expect(changed.dataset.activities.first?.distanceMeters == nil)
        #expect(ledger(changed.dataset).first { $0.gearID == shoesA }?.distanceMeters == nil)
    }

    @Test("T-06 Ersatz: Löschen + Neuanlage mit gleicher Zeit übernimmt die Zuordnung, Nutzung zählt einmal")
    func t06_replacementKeepsAssignmentOnce() throws {
        var d = twoShoes()
        d.assignmentRules = [AssignmentRule(sportType: run, gearIDs: [shoesB])]
        let first = reconcile(d, ImportBatch(upserts: [workout("W1", start: day(1))]))
        let old = try #require(first.dataset.activities.first)
        #expect(first.dataset.assignments.map(\.gearID) == [shoesB])

        // Health ersetzt das Training: neue UUID, Start 20 s später, gleiches Ende.
        let replaced = reconcile(first.dataset, ImportBatch(
            upserts: [workout("W1-neu", start: day(1).addingTimeInterval(20), hours: 1 - 20.0 / 3_600)],
            deletedSourceIDs: ["W1"]))
        let live = active(replaced.dataset)
        #expect(live.count == 1 && live[0].sourceID == "W1-neu")
        #expect(replaced.replaced == [Replacement(old: old.id, new: live[0].id)])
        #expect(replaced.dataset.activities.first { $0.id == old.id }?.deletedAt == now)
        let entries = ledger(replaced.dataset).filter { $0.gearID == shoesB }
        #expect(entries.count == 1 && entries[0].activityID == live[0].id)
        #expect(replaced.dataset.assignments.filter { $0.activityID == live[0].id }.map(\.origin) == [.rule])
        #expect(replaced.dataset.pendings.isEmpty)
    }

    @Test("T-06 Ersatz: Ein offener Posteingangseintrag wandert mit zur neuen Aktivität")
    func replacementMovesOpenPending() throws {
        let first = reconcile(twoShoes(), ImportBatch(upserts: [workout("W1", start: day(1))]))
        let oldPending = try #require(first.dataset.pendings.first)
        #expect(oldPending.state == .unresolved)

        let replaced = reconcile(first.dataset, ImportBatch(upserts: [workout("W1-neu", start: day(1).addingTimeInterval(5))],
                                                            deletedSourceIDs: ["W1"]))
        let newID = try #require(active(replaced.dataset).first?.id)
        let open = replaced.dataset.pendings.filter { !$0.state.isFinal }
        #expect(open.count == 1 && open[0].activityID == newID)
        #expect(open[0].candidateGearIDs == oldPending.candidateGearIDs)
        #expect(replaced.dataset.pendings.first { $0.id == oldPending.id }?.state == .obsolete)
    }

    @Test("Ersatz nur bei eindeutiger Übereinstimmung; sonst Posteingang und keine stille Übernahme (P-05)")
    func ambiguousReplacementGoesToInbox() throws {
        var d = twoShoes()
        d.assignmentRules = [AssignmentRule(sportType: run, gearIDs: [shoesA])]
        let first = reconcile(d, ImportBatch(upserts: [workout("W1", start: day(1)), workout("W2", start: day(1))]))
        #expect(active(first.dataset).count == 2)

        let out = reconcile(first.dataset, ImportBatch(upserts: [workout("N1", start: day(1)), workout("N2", start: day(1))],
                                                       deletedSourceIDs: ["W1", "W2"]))
        #expect(out.replaced.isEmpty)
        let live = active(out.dataset)
        #expect(live.count == 2 && Set(live.compactMap(\.sourceID)) == ["N1", "N2"])
        for a in live {
            #expect(out.dataset.assignments.filter { $0.activityID == a.id }.isEmpty, "keine stille Übernahme")
            let pending = try #require(out.dataset.pendings.first { $0.activityID == a.id })
            #expect(pending.reason == .replacementAmbiguous && !pending.state.isFinal)
            #expect(pending.proposedGearIDs == [shoesA])
        }
    }

    @Test("Anderer Sporttyp oder weit entfernte Zeit ist kein Ersatz")
    func differentSportOrTimeIsNoReplacement() throws {
        var d = GearDataset(); d.gear = [item(shoesA, .running), item(bikeA, .cycling)]
        let first = reconcile(d, ImportBatch(upserts: [workout("W1", start: day(1))]))
        let otherSport = reconcile(first.dataset, ImportBatch(upserts: [workout("X", start: day(1), sport: cycling)],
                                                              deletedSourceIDs: ["W1"]))
        #expect(otherSport.replaced.isEmpty)
        let farAway = reconcile(first.dataset, ImportBatch(upserts: [workout("Y", start: day(1, hour: 5))],
                                                           deletedSourceIDs: ["W1"]))
        #expect(farAway.replaced.isEmpty)
    }

    // MARK: T-07 Löschungen

    @Test("T-07: Gelöschtes Training entfernt die Ledger-Einträge und schließt den Posteingang, nicht die Ausrüstung")
    func t07_deletionRevisesLedgerAndInbox() throws {
        var d = twoShoes()
        d.assignmentRules = [AssignmentRule(sportType: run, gearIDs: [shoesA])]
        let first = reconcile(d, ImportBatch(upserts: [workout("W1", start: day(1)), workout("OFFEN", start: day(2), sport: run)]))
        // zweites Training als offener Eintrag: Regel deaktivieren und neu importieren
        var d2 = first.dataset; d2.assignmentRules = []
        let withOpen = reconcile(d2, ImportBatch(upserts: [workout("W3", start: day(3))]))
        let openPending = try #require(withOpen.dataset.pendings.first { !$0.state.isFinal })
        #expect(ledger(withOpen.dataset).filter { $0.gearID == shoesA }.count == 2)

        let out = reconcile(withOpen.dataset, ImportBatch(deletedSourceIDs: ["W1", "W3"]))
        #expect(out.tombstoned.count == 2)
        #expect(ledger(out.dataset).filter { $0.gearID == shoesA }.count == 1, "nur das nicht gelöschte OFFEN-Training bleibt")
        #expect(out.dataset.pendings.first { $0.id == openPending.id }?.state == .obsolete)
        #expect(out.dataset.gear == withOpen.dataset.gear, "physische Ausrüstung bleibt")
        #expect(out.dataset.assignments.count == withOpen.dataset.assignments.count, "Zuordnungen bleiben als Historie, Ledger ignoriert sie")
    }

    @Test("Eine unbekannte oder bereits gelöschte Quell-ID ist ein No-Op")
    func deletingUnknownOrTwiceIsNoOp() {
        var d = GearDataset(); d.gear = [item(shoesA, .running)]
        let first = reconcile(d, ImportBatch(upserts: [workout("W1", start: day(1))]))
        let gone = reconcile(first.dataset, ImportBatch(deletedSourceIDs: ["W1"]))
        let again = reconcile(gone.dataset, ImportBatch(deletedSourceIDs: ["W1", "NIE-GEHÖRT"]))
        #expect(again.isUnchanged && again.dataset == gone.dataset)
    }

    @Test("Ein leerer Batch löscht nichts: aus fehlenden Daten folgt keine Löschung (SPEC 11, 6.1 Punkt 7)")
    func emptyBatchNeverDeletes() {
        var d = GearDataset(); d.gear = [item(shoesA, .running)]
        let first = reconcile(d, ImportBatch(upserts: [workout("W1", start: day(1))]))
        let out = reconcile(first.dataset, ImportBatch())
        #expect(out.isUnchanged && out.dataset == first.dataset)
        #expect(active(out.dataset).count == 1)
    }

    @Test("Ein später wieder gelieferter, zuvor gelöschter Eintrag wird wiederbelebt und zählt wieder")
    func tombstonedWorkoutReturns() throws {
        var d = GearDataset(); d.gear = [item(shoesA, .running)]
        let first = reconcile(d, ImportBatch(upserts: [workout("W1", start: day(1))]))
        let gone = reconcile(first.dataset, ImportBatch(deletedSourceIDs: ["W1"]))
        #expect(ledger(gone.dataset).isEmpty)
        let back = reconcile(gone.dataset, ImportBatch(upserts: [workout("W1", start: day(1))]))
        let a = try #require(back.dataset.activities.first)
        #expect(back.dataset.activities.count == 1 && a.deletedAt == nil)
        #expect(a.revision == gone.dataset.activities[0].revision + 1)
        #expect(ledger(back.dataset).filter { $0.gearID == shoesA }.count == 1)
    }

    // MARK: Entscheidungen für neue Aktivitäten

    @Test("Eindeutige Aktivität: automatisch zugeordnet, ohne Posteingang (Null-Interaktionsfall)")
    func zeroInteractionCase() throws {
        var d = GearDataset(); d.gear = [item(shoesA, .running)]
        let out = reconcile(d, ImportBatch(upserts: [workout("W1", start: day(1))]))
        let a = try #require(out.dataset.activities.first)
        #expect(out.dataset.assignments.map(\.gearID) == [shoesA])
        #expect(out.dataset.assignments.first?.origin == .soleCandidate)
        #expect(out.dataset.assignments.first?.activityID == a.id)
        #expect(out.dataset.pendings.isEmpty)
        #expect(out.autoAssigned == [a.id])
    }

    @Test("Mehrere Kandidaten: offener Eintrag zur Nachfrage, noch keine Buchung")
    func ambiguousCreatesPending() throws {
        let out = reconcile(twoShoes(), ImportBatch(upserts: [workout("W1", start: day(1))]))
        let p = try #require(out.dataset.pendings.first)
        #expect(p.state == .unresolved && p.candidateGearIDs == [shoesA, shoesB] && p.reason == .multipleCandidates)
        #expect(out.dataset.assignments.isEmpty && ledger(out.dataset).isEmpty)
        #expect(out.pendingCreated == [p.id])
    }

    @Test("Ohne Ausrüstung: Aktivität wird importiert, kein Posteingang, keine Zuordnung")
    func noGearImportsQuietly() {
        let out = reconcile(GearDataset(), ImportBatch(upserts: [workout("W1", start: day(1))]))
        #expect(out.dataset.activities.count == 1 && out.dataset.assignments.isEmpty && out.dataset.pendings.isEmpty)
    }

    @Test("Bestätigte Gewohnheit ergibt einen Vorschlag (suggested), nie eine stille Buchung")
    func historyYieldsSuggestion() throws {
        var d = twoShoes()
        let a1 = ActivityRecord(id: id(901), sportType: run, startAt: day(1), endAt: day(1, hour: 1), durationSeconds: 3_600)
        let a2 = ActivityRecord(id: id(902), sportType: run, startAt: day(2), endAt: day(2, hour: 1), durationSeconds: 3_600)
        d.activities = [a1, a2]
        d.assignments = [ActivityGearAssignment(activityID: a1.id, gearID: shoesB, origin: .confirmedProposal, createdAt: day(1)),
                         ActivityGearAssignment(activityID: a2.id, gearID: shoesB, origin: .manual, createdAt: day(2))]
        let out = reconcile(d, ImportBatch(upserts: [workout("W9", start: day(9))]))
        let p = try #require(out.dataset.pendings.first)
        #expect(p.state == .suggested && p.proposedGearIDs == [shoesB] && p.reason == .history)
        #expect(out.dataset.assignments.count == 2, "keine neue Buchung")
    }

    @Test("Manuelle Aktivitäten durchlaufen dieselbe Zuordnungslogik")
    func manualActivityUsesSameLogic() throws {
        var d = GearDataset(); d.gear = [item(shoesA, .running)]
        let manual = ActivityRecord(id: id(950), source: .manual, sportType: run, startAt: day(2), endAt: day(2, hour: 1),
                                    distanceMeters: nil, durationSeconds: 3_600)
        let out = ImportReconciler.addManual(manual, to: d, now: now, makeID: Ids().next)
        #expect(out.dataset.activities == [manual])
        #expect(out.dataset.assignments.map(\.gearID) == [shoesA])
        #expect(ledger(out.dataset).first?.distanceMeters == nil)
    }

    // MARK: Regeln wirken nie still auf Abgeschlossenes (SPEC 6.3)

    @Test("Eine neue Regel ändert bestehende Aktivitäten nicht, auch nicht bei Re-Import und Update")
    func rulesNeverTouchCompletedActivities() throws {
        let first = reconcile(twoShoes(), ImportBatch(upserts: [workout("W1", start: day(1)), workout("W2", start: day(2))]))
        // W1 manuell zugeordnet, W2 bewusst ohne Ausrüstung.
        var d = first.dataset
        let p1 = try #require(d.pendings.first { $0.activityID == d.activities[0].id })
        let p2 = try #require(d.pendings.first { $0.activityID == d.activities[1].id })
        let r1 = InboxReducer.reduce(p1, .choose(gear: [shoesA]), now: now, makeID: Ids().next)
        let r2 = InboxReducer.reduce(p2, .dismiss, now: now)
        d.pendings = [r1.pending, r2.pending]; d.assignments = r1.assignments
        let before = d

        d.assignmentRules = [AssignmentRule(sportType: run, kind: .remembered, gearIDs: [shoesB])]
        let reimport = reconcile(d, ImportBatch(upserts: [workout("W1", start: day(1)), workout("W2", start: day(2))]))
        #expect(reimport.isUnchanged)
        let update = reconcile(d, ImportBatch(upserts: [workout("W1", start: day(1), hours: 2), workout("W2", start: day(2), hours: 3)]))
        #expect(update.dataset.assignments == before.assignments, "keine neuen Gegenstände an abgeschlossene Aktivitäten")
        #expect(update.dataset.pendings == before.pendings)
        #expect(update.pendingCreated.isEmpty && update.autoAssigned.isEmpty)
    }

    // MARK: Zusammenführen: nur vorschlagen (SPEC 5.2, 6.4)

    @Test("Kein Zusammenführen nur wegen Zeitüberschneidung: Teilüberlappung ergibt weder Merge noch Vorschlag")
    func overlapAloneNeverMerges() {
        let out = reconcile(twoShoes(), ImportBatch(upserts: [workout("W1", start: day(1)),
                                                              workout("W2", start: day(1).addingTimeInterval(1_800))]))
        #expect(active(out.dataset).count == 2)
        #expect(out.mergeSuggestions.isEmpty)
    }

    @Test("Zwei Quellen mit gleichem Zeitraum und Sporttyp: beide bleiben, es gibt höchstens einen Vorschlag")
    func twoSourcesSameSpanOnlySuggests() throws {
        let out = reconcile(twoShoes(), ImportBatch(upserts: [workout("W1", start: day(1)), workout("W2", start: day(1))]))
        #expect(active(out.dataset).count == 2)
        let s = try #require(out.mergeSuggestions.first)
        #expect(out.mergeSuggestions.count == 1 && s.reason == .sameSpanDifferentSources)
        #expect(Set([s.keptID, s.otherID]) == Set(active(out.dataset).map(\.id)))
    }

    @Test("Manuell + später importiert (starke Übereinstimmung): Vorschlag statt Doppelung, nichts wird gelöscht")
    func manualThenImportedSuggestsMerge() throws {
        var d = GearDataset(); d.gear = [item(shoesA, .running)]
        let manual = ActivityRecord(id: id(950), source: .manual, sportType: run, startAt: day(2), endAt: day(2, hour: 1),
                                    distanceMeters: 10_000, durationSeconds: 3_600)
        d = ImportReconciler.addManual(manual, to: d, now: now, makeID: Ids().next).dataset
        let out = reconcile(d, ImportBatch(upserts: [workout("W1", start: day(2).addingTimeInterval(120))]))
        let s = try #require(out.mergeSuggestions.first)
        #expect(s.reason == .manualMatchesImported && s.keptID == manual.id)
        #expect(active(out.dataset).count == 2, "kein stilles Zusammenführen")
    }

    @Test("Verschiedene Sportarten zur selben Zeit sind legitim (z. B. Triathlon-Teile) und werden nie vorgeschlagen")
    func differentSportsAreLegitimate() {
        var d = GearDataset(); d.gear = [item(shoesA, .running), item(bikeA, .cycling)]
        let out = reconcile(d, ImportBatch(upserts: [workout("W1", start: day(1)), workout("W2", start: day(1), sport: cycling)]))
        #expect(out.mergeSuggestions.isEmpty && active(out.dataset).count == 2)
    }

    @Test("Mehrdeutige Übereinstimmung (drei gleiche Zeiträume) ergibt keinen Vorschlag")
    func ambiguousMatchNoSuggestion() {
        let out = reconcile(twoShoes(), ImportBatch(upserts: [workout("A", start: day(1)), workout("B", start: day(1)),
                                                              workout("C", start: day(1))]))
        #expect(out.mergeSuggestions.isEmpty && active(out.dataset).count == 3)
    }

    // MARK: Konsistenz mit dem Ledger

    @Test("Die gemeldeten Ledger-Änderungen führen die Projektion auf denselben Stand wie ein Neuaufbau (I-10)")
    func ledgerChangesMatchRebuild() {
        var d = twoShoes()
        d.assignmentRules = [AssignmentRule(sportType: run, gearIDs: [shoesA])]
        let first = reconcile(d, ImportBatch(upserts: [workout("W1", start: day(1)), workout("W2", start: day(2))]))
        var projection = LedgerProjection(input: d.ledgerInput)
        first.ledgerChanges.forEach { projection.apply($0) }
        #expect(projection.entries == ledger(first.dataset))

        let second = reconcile(first.dataset, ImportBatch(
            upserts: [workout("W2", start: day(2), hours: 2), workout("W3", start: day(3))], deletedSourceIDs: ["W1"]))
        second.ledgerChanges.forEach { projection.apply($0) }
        #expect(projection.entries == ledger(second.dataset))
    }
}
