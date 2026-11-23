import Testing
import Foundation
@testable import GearCore

private let bike = id(1), chainOld = id(2), chainNew = id(3), shoes = id(4), helmet = id(5)

/// Realistischer Bestand: Kettenwechsel mit Chronologie, Wartung, Regeln, Preset, Posteingang, manuelle und importierte Aktivität.
private func richDataset() -> GearDataset {
    var d = GearDataset()
    d.gear = [
        GearItem(id: bike, name: "Rennrad", purchaseDate: day(-100), createdAt: day(-100), category: .cycling, subtype: .roadBike),
        GearItem(id: chainOld, name: "Kette alt", status: .retired, createdAt: day(-90), category: .cycling),
        GearItem(id: chainNew, name: "Kette neu", createdAt: day(20), category: .cycling),
        GearItem(id: shoes, name: "Laufschuhe", createdAt: day(-30), category: .running, subtype: .roadRunning),
        GearItem(id: helmet, name: "Helm", createdAt: day(-80), category: .cycling),
    ]
    d.statusChanges = [GearStatusChange(id: id(100), gearID: chainOld, status: .retired, effectiveAt: day(20))]
    d.installations = [
        Installation(id: id(200), parentGearID: bike, childGearID: chainOld, startedAt: day(-90), endedAt: day(20), notes: "Erstausstattung"),
        Installation(id: id(201), parentGearID: bike, childGearID: chainNew, startedAt: day(20)),
    ]
    d.presets = [GearPreset(id: id(300), name: "Rennrad-Set", sportTypes: [cycling], memberGearIDs: [bike, helmet])]
    d.sportProfiles = [SportProfile(id: id(301), sportType: cycling, defaultPresetID: id(300), notificationLevel: .assignmentAndMaintenance)]
    let ride1 = ActivityRecord(id: id(400), source: .healthKit, sourceID: "HK-1", sportType: cycling, startAt: day(5), endAt: day(5, hour: 2),
                               distanceMeters: 55_000.5, durationSeconds: 7_200, isIndoor: false, revision: 3)
    let ride2 = ActivityRecord(id: id(401), source: .healthKit, sourceID: "HK-2", sportType: cycling, startAt: day(25), endAt: day(25, hour: 1),
                               distanceMeters: nil, durationSeconds: 3_600)
    let manual = ActivityRecord(id: id(402), source: .manual, sportType: run, startAt: day(26), endAt: day(26, hour: 1),
                                distanceMeters: 8_000, durationSeconds: 3_600)
    let tri = ActivityRecord(id: id(403), source: .healthKit, sourceID: "HK-3", sportType: SportType(rawValue: 82),
                             startAt: day(27), endAt: day(27, hour: 3), distanceMeters: nil, durationSeconds: 10_800)
    d.activities = [ride1, ride2, manual, tri]
    d.segments = [ActivitySegment(id: id(500), activityID: tri.id, sportType: cycling, startAt: day(27, hour: 1), endAt: day(27, hour: 2), distanceMeters: 30_000)]
    d.assignments = [
        ActivityGearAssignment(id: id(600), activityID: ride1.id, gearID: bike, origin: .rule, createdAt: day(5)),
        ActivityGearAssignment(id: id(601), activityID: ride2.id, gearID: bike, origin: .confirmedProposal, createdAt: day(25)),
        ActivityGearAssignment(id: id(602), activityID: manual.id, gearID: shoes, origin: .manual, createdAt: day(26)),
        ActivityGearAssignment(id: id(603), activityID: tri.id, segmentID: id(500), gearID: bike, origin: .manual, createdAt: day(27)),
    ]
    d.maintenanceEvents = [
        MaintenanceEvent(id: id(700), gearID: chainOld, kind: .lubricated, performedAt: day(10), notes: "gewachst"),
        MaintenanceEvent(id: id(701), gearID: chainNew, kind: .wearMeasured, performedAt: day(24), measurement: 0.5, costMinor: 1_999),
        MaintenanceEvent(id: id(702), gearID: bike, kind: .partReplaced, performedAt: day(20)),
    ]
    d.maintenanceRules = [MaintenanceRule(id: id(800), gearID: chainNew, kind: .lubricated, metric: .distance, intervalValue: 350_000, warningLeadValue: 50_000)]
    d.assignmentRules = [
        AssignmentRule(id: id(900), sportType: cycling, kind: .remembered, conditions: RuleConditions(isIndoor: false, weekdays: [7]),
                       gearIDs: [bike, helmet], priority: 2, enabled: true, createdAt: day(6)),
        AssignmentRule(id: id(901), sportType: run, gearIDs: [shoes], enabled: false),
    ]
    d.pendings = [
        PendingAssignment(id: id(950), activityID: ride2.id, state: .suggested, proposedGearIDs: [bike], alternatives: [[helmet]],
                          reason: .history, confidence: .medium, proposalRevision: 4, createdAt: day(25), lastPromptAt: day(26)),
        PendingAssignment(id: id(951), activityID: tri.id, state: .unresolved, candidateGearIDs: [bike, helmet],
                          reason: .multipleCandidates, createdAt: day(27)),
    ]
    return d
}

private func document(_ d: GearDataset = richDataset(), formatVersion: Int = BackupDocument.currentFormatVersion) -> BackupDocument {
    var doc = BackupDocument(exportedAt: day(40), data: d)
    doc.formatVersion = formatVersion
    return doc
}

private func errors(_ doc: BackupDocument) -> [BackupIssue] { BackupValidator.validate(doc).filter { !$0.isWarning } }

@Suite("Backup (SPEC 11, T-14)")
struct BackupTests {

    // MARK: T-14

    @Test("T-14: Export und Import erhalten IDs, Chronologie, Montagen, Regeln und Wartung")
    func t14_roundTripPreservesEverything() throws {
        let original = richDataset()
        let data = try BackupCodec.encode(document(original))
        let restored = try BackupCodec.decode(data)
        #expect(restored.data == original)
        #expect(restored.exportedAt == day(40))

        #expect(restored.data.installations.map(\.id) == [id(200), id(201)])
        #expect(restored.data.installations[0].endedAt == day(20) && restored.data.installations[1].endedAt == nil)
        #expect(restored.data.activities.map(\.startAt) == original.activities.map(\.startAt), "Chronologie bleibt")
        #expect(restored.data.assignmentRules == original.assignmentRules)
        #expect(restored.data.maintenanceEvents == original.maintenanceEvents)
        #expect(restored.data.maintenanceRules == original.maintenanceRules)
        #expect(restored.data.pendings == original.pendings, "offene Zuordnungen gehen nie verloren")
        #expect(restored.data.activities.first { $0.id == id(401) }?.distanceMeters == nil, "nil bleibt nil, nicht 0")
        #expect(restored.data.activities.first { $0.id == id(400) }?.distanceMeters == 55_000.5)
    }

    @Test("T-14: Nach dem Wiederherstellen ergibt der Neuaufbau dieselben Nutzungswerte wie vorher")
    func t14_ledgerAfterRestoreMatches() throws {
        let original = richDataset()
        let restored = try BackupCodec.decode(BackupCodec.encode(document(original))).data

        let before = LedgerBuilder.build(original.ledgerInput)
        let after = LedgerBuilder.build(restored.ledgerInput)
        #expect(before == after)

        func q(_ d: GearDataset, _ ledger: LedgerResult) -> UsageQuery {
            UsageQuery(entries: ledger.entries, installations: d.installations, maintenance: d.maintenanceEvents, gear: d.gear)
        }
        let qb = q(original, before), qa = q(restored, after)
        for g in [bike, chainOld, chainNew, shoes, helmet] {
            #expect(qb.lifetime(of: g) == qa.lifetime(of: g))
            #expect(qb.sinceInstallation(of: g) == qa.sinceInstallation(of: g))
            #expect(qb.sinceMaintenance(of: g, kind: .lubricated) == qa.sinceMaintenance(of: g, kind: .lubricated))
        }
        // Die alte Kette hat ihre Fahrt vor dem Wechsel, die neue die danach (T-02 bleibt nach Restore wahr).
        #expect(after.entries.filter { $0.gearID == chainOld }.map(\.activityID) == [id(400)])
        #expect(after.entries.filter { $0.gearID == chainNew }.map(\.activityID).sorted { $0.uuidString < $1.uuidString } == [id(401), id(403)])
    }

    @Test("Das Ledger ist nicht Teil des Backups, es wird neu gebaut (ARCHITEKTUR 7)")
    func ledgerIsNotExported() throws {
        let json = String(decoding: try BackupCodec.encode(document()), as: UTF8.self)
        #expect(!json.lowercased().contains("ledger"))
        #expect(json.contains("\"formatVersion\""))
    }

    @Test("Der Export ist gültiges JSON mit Kopfdaten und gleiche Eingabe ergibt gleiche Bytes")
    func exportIsStableJSON() throws {
        let doc = document()
        let a = try BackupCodec.encode(doc), b = try BackupCodec.encode(doc)
        #expect(a == b)
        let object = try #require(try JSONSerialization.jsonObject(with: a) as? [String: Any])
        #expect(object["formatVersion"] as? Int == 1)
        #expect(object["appSchemaVersion"] as? Int == BackupDocument.currentSchemaVersion)
        #expect(object["data"] is [String: Any])
    }

    // MARK: Versionierung und Fehler

    @Test("Eine neuere Formatversion wird vor dem Dekodieren abgelehnt, nichts wird teilweise übernommen")
    func newerFormatRejected() throws {
        let future = try BackupCodec.encode(document(formatVersion: BackupDocument.currentFormatVersion + 1))
        #expect(throws: BackupError.unsupportedFormatVersion(BackupDocument.currentFormatVersion + 1)) {
            try BackupCodec.decode(future)
        }
        #expect(BackupValidator.validate(document(formatVersion: 2)).contains(.unsupportedFormatVersion(2)))
        #expect(BackupValidator.validate(document(formatVersion: 0)).contains(.unsupportedFormatVersion(0)))
    }

    @Test("Beschädigte oder fremde Dateien ergeben einen klaren Fehler statt eines Absturzes")
    func malformedInput() {
        for bad in ["", "kein json", "{}", "[]", "{\"formatVersion\":1}"] {
            #expect(throws: BackupError.self) { try BackupCodec.decode(Data(bad.utf8)) }
        }
    }

    @Test("Unbekannte zusätzliche Felder (spätere Versionen) stören das Lesen nicht")
    func unknownFieldsIgnored() throws {
        let data = try BackupCodec.encode(document())
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["hinzugekommen"] = ["x": 1]
        let patched = try JSONSerialization.data(withJSONObject: object)
        #expect(try BackupCodec.decode(patched).data == richDataset())
    }

    // MARK: Validator

    @Test("Ein gültiger Bestand hat weder Fehler noch Warnungen")
    func validDatasetIsClean() {
        #expect(BackupValidator.validate(document()).isEmpty)
        #expect(BackupValidator.validate(document(GearDataset())).isEmpty)
    }

    @Test("Verweise ins Leere werden je Entität erkannt")
    func danglingReferences() {
        let ghost = id(9_999)
        func broken(_ mutate: (inout GearDataset) -> Void) -> [BackupIssue] {
            var d = richDataset(); mutate(&d); return errors(document(d))
        }
        #expect(broken { $0.installations[0].childGearID = ghost }.contains(.danglingReference(.installation, id(200), missing: ghost)))
        #expect(broken { $0.installations[1].parentGearID = ghost }.contains(.danglingReference(.installation, id(201), missing: ghost)))
        #expect(broken { $0.assignments[0].gearID = ghost }.contains(.danglingReference(.assignment, id(600), missing: ghost)))
        #expect(broken { $0.assignments[0].activityID = ghost }.contains(.danglingReference(.assignment, id(600), missing: ghost)))
        #expect(broken { $0.assignments[3].segmentID = ghost }.contains(.danglingReference(.assignment, id(603), missing: ghost)))
        #expect(broken { $0.segments[0].activityID = ghost }.contains(.danglingReference(.segment, id(500), missing: ghost)))
        #expect(broken { $0.maintenanceEvents[0].gearID = ghost }.contains(.danglingReference(.maintenanceEvent, id(700), missing: ghost)))
        #expect(broken { $0.maintenanceRules[0].gearID = ghost }.contains(.danglingReference(.maintenanceRule, id(800), missing: ghost)))
        #expect(broken { $0.assignmentRules[0].gearIDs = [ghost] }.contains(.danglingReference(.assignmentRule, id(900), missing: ghost)))
        #expect(broken { $0.presets[0].memberGearIDs = [ghost] }.contains(.danglingReference(.preset, id(300), missing: ghost)))
        #expect(broken { $0.sportProfiles[0].defaultPresetID = ghost }.contains(.danglingReference(.sportProfile, id(301), missing: ghost)))
        #expect(broken { $0.statusChanges[0].gearID = ghost }.contains(.danglingReference(.statusChange, id(100), missing: ghost)))
        #expect(broken { $0.pendings[0].activityID = ghost }.contains(.danglingReference(.pending, id(950), missing: ghost)))
        #expect(broken { $0.pendings[0].proposedGearIDs = [ghost] }.contains(.danglingReference(.pending, id(950), missing: ghost)))
        #expect(broken { $0.pendings[1].candidateGearIDs = [ghost] }.contains(.danglingReference(.pending, id(951), missing: ghost)))
    }

    @Test("Eine Segmentzuordnung zu einem Segment einer anderen Aktivität ist ungültig")
    func segmentBelongsToActivity() {
        var d = richDataset()
        d.assignments[3].activityID = id(400)   // Segment 500 gehört zu Aktivität 403
        #expect(errors(document(d)).contains(.segmentActivityMismatch(assignmentID: id(603))))
    }

    @Test("Doppelte IDs werden je Entität gemeldet")
    func duplicateIDs() {
        var d = richDataset()
        d.gear.append(d.gear[0])
        d.assignments.append(d.assignments[0])
        let e = errors(document(d))
        #expect(e.contains(.duplicateID(.gear, bike)))
        #expect(e.contains(.duplicateID(.assignment, id(600))))
    }

    @Test("Montageregeln des Kerns gelten auch für Backups: Überlappung, Kreis, Ende vor Beginn (I-01…I-03)")
    func installationInvariants() {
        var overlap = richDataset()
        overlap.installations.append(Installation(id: id(202), parentGearID: helmet, childGearID: chainNew, startedAt: day(21)))
        #expect(errors(document(overlap)).contains { if case .installation(.overlappingChildInstallations) = $0 { true } else { false } })

        var cycle = richDataset()
        cycle.installations.append(Installation(id: id(203), parentGearID: chainNew, childGearID: bike, startedAt: day(21)))
        #expect(errors(document(cycle)).contains { if case .installation(.cycle) = $0 { true } else { false } })

        var reversed = richDataset()
        reversed.installations[0].endedAt = day(-95)
        #expect(errors(document(reversed)).contains(.installation(.endNotAfterStart(installationID: id(200)))))
    }

    @Test("Montage vor dem Kaufdatum ist nur eine Warnung (I-03), blockiert den Import nicht")
    func purchaseDateIsWarningOnly() {
        var d = richDataset()
        d.gear[2].purchaseDate = day(30)   // neue Kette „gekauft“ nach Einbau
        let issues = BackupValidator.validate(document(d))
        #expect(issues.contains { $0.isWarning })
        #expect(errors(document(d)).isEmpty)
        #expect(BackupValidator.isImportable(document(d)))
    }

    @Test("Zwei HealthKit-Aktivitäten mit derselben Quell-ID verletzen I-07")
    func duplicateSourceID() {
        var d = richDataset()
        d.activities[1].sourceID = d.activities[0].sourceID
        #expect(errors(document(d)).contains(.duplicateSourceID("HK-1")))
    }

    @Test("Unmögliche Werte: Ende vor Start, negative Distanz oder Dauer")
    func impossibleActivityValues() {
        var d = richDataset()
        d.activities[0].endAt = d.activities[0].startAt.addingTimeInterval(-1)
        d.activities[1].durationSeconds = -5
        d.activities[2].distanceMeters = -1
        let e = errors(document(d))
        #expect(e.contains(.invalidActivity(id(400))) && e.contains(.invalidActivity(id(401))) && e.contains(.invalidActivity(id(402))))
    }

    @Test("Posteingang: Endzustand ohne passende Auflösung ist inkonsistent (I-09)")
    func inconsistentPendingState() {
        var d = richDataset()
        d.pendings[0].state = .resolved           // Auflösung steht noch auf .none
        #expect(errors(document(d)).contains(.inconsistentPending(id(950))))
        d.pendings[0].resolution = .chosen
        #expect(!errors(document(d)).contains(.inconsistentPending(id(950))))
    }

    @Test("isImportable ist nur bei Fehlern false")
    func isImportable() {
        #expect(BackupValidator.isImportable(document()))
        var d = richDataset(); d.gear.append(d.gear[0])
        #expect(!BackupValidator.isImportable(document(d)))
    }

    // MARK: Vorschau und Wiederherstellung

    @Test("Vorschau: Anzahl je Typ und Konflikte gegenüber dem vorhandenen Bestand")
    func previewCountsAndConflicts() {
        var existing = richDataset()
        existing.gear[0].name = "Rennrad (lokal umbenannt)"
        existing.gear.append(GearItem(id: id(77), name: "Nur lokal"))
        let preview = BackupRestore.preview(document(), against: existing)
        #expect(preview.counts[.gear] == 5 && preview.counts[.installation] == 2 && preview.counts[.activity] == 4)
        #expect(preview.counts[.pending] == 2 && preview.counts[.maintenanceRule] == 1)
        #expect(preview.conflicts == [BackupConflict(entity: .gear, id: bike)])
        #expect(preview.issues.isEmpty)
    }

    @Test("Vorschau gegen leeren Bestand hat keine Konflikte")
    func previewAgainstEmpty() {
        let preview = BackupRestore.preview(document(), against: GearDataset())
        #expect(preview.conflicts.isEmpty)
        #expect(preview.counts.values.reduce(0, +) > 0)
    }

    @Test("Ersetzen: Ergebnis ist exakt der Bestand des Backups, nichts Lokales bleibt")
    func restoreReplace() throws {
        var existing = richDataset()
        existing.gear.append(GearItem(id: id(77), name: "Nur lokal"))
        let result = try BackupRestore.restore(document(), into: existing, mode: .replace)
        #expect(result == richDataset())
    }

    @Test("Zusammenführen nach ID: Neues kommt dazu, bei gleicher ID entscheidet die gewählte Seite")
    func restoreMerge() throws {
        var existing = richDataset()
        existing.gear[0].name = "lokal"
        existing.gear.append(GearItem(id: id(77), name: "Nur lokal"))
        var backup = richDataset()
        backup.gear[0].name = "Backup"
        backup.gear.append(GearItem(id: id(78), name: "Nur im Backup"))

        let keepExisting = try BackupRestore.restore(document(backup), into: existing, mode: .merge(prefer: .existing))
        #expect(keepExisting.gear.first { $0.id == bike }?.name == "lokal")
        #expect(Set(keepExisting.gear.map(\.id)) == Set(existing.gear.map(\.id) + [id(78)]))

        let preferBackup = try BackupRestore.restore(document(backup), into: existing, mode: .merge(prefer: .backup))
        #expect(preferBackup.gear.first { $0.id == bike }?.name == "Backup")
        #expect(preferBackup.gear.contains { $0.id == id(77) } && preferBackup.gear.contains { $0.id == id(78) })
        #expect(preferBackup.gear.count == 7, "keine doppelten IDs")
        #expect(preferBackup.activities.count == 4 && preferBackup.installations.count == 2)
    }

    @Test("Zusammenführen, das gegen die Montageregeln verstößt, wird abgelehnt und ändert nichts")
    func mergeCreatingOverlapIsRejected() {
        var existing = richDataset()
        existing.installations.append(Installation(id: id(210), parentGearID: helmet, childGearID: chainNew, startedAt: day(21)))
        // `existing` selbst ist ungültig; sauberer Fall: lokal gültig, Backup gültig, Union verletzt I-01.
        existing = richDataset()
        var backup = richDataset()
        backup.installations[1].id = id(211)                          // gleiche Montage unter anderer ID …
        backup.installations[1].parentGearID = helmet                  // … an anderem Elternteil
        #expect(BackupValidator.isImportable(document(backup)))
        #expect(BackupValidator.isImportable(document(existing)))
        #expect(throws: BackupError.self) {
            try BackupRestore.restore(document(backup), into: existing, mode: .merge(prefer: .backup))
        }
    }

    @Test("Ungültiges Backup wird nicht wiederhergestellt, Fehlerliste liegt bei")
    func invalidBackupThrowsWithIssues() {
        var d = richDataset(); d.assignments[0].gearID = id(9_999)
        do {
            _ = try BackupRestore.restore(document(d), into: GearDataset(), mode: .replace)
            Issue.record("Hätte ablehnen müssen")
        } catch let BackupError.invalid(issues) {
            #expect(issues.contains(.danglingReference(.assignment, id(600), missing: id(9_999))))
        } catch {
            Issue.record("Falscher Fehler: \(error)")
        }
    }

    @Test("Aus dem Datensatz exportieren und wieder einlesen ist stabil, auch für leeren Bestand")
    func emptyDatasetRoundTrip() throws {
        let doc = document(GearDataset())
        #expect(try BackupCodec.decode(BackupCodec.encode(doc)) == doc)
    }
}
