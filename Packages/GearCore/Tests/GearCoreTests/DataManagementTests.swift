import Testing
import Foundation
@testable import GearCore

// M8 Datensicherung und Löschen (SPEC 11, T-14): Fotos im Backup, Vorschau je Typ, Löschen von Ausrüstung und Aktivitäten.
// IDs wie in `richDataset()` (BackupTests): Rad 1, Kette alt 2, Kette neu 3, Schuhe 4, Helm 5.
private let bike = id(1), chainNew = id(3), shoes = id(4), helmet = id(5)
private let photo = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46])   // JPEG-Kopf genügt als Bytes

private func withPhoto(_ path: String = "gear/rennrad.jpg") -> (GearDataset, BackupDocument) {
    var d = richDataset()
    d.gear[0].photoPath = path
    return (d, BackupDocument(exportedAt: day(40), data: d, media: [BackupMedia(path: path, data: photo)]))
}

private func errors(_ doc: BackupDocument) -> [BackupIssue] { BackupValidator.validate(doc).filter { !$0.isWarning } }

@Suite("Backup mit Fotos (SPEC 11, T-14)")
struct BackupMediaTests {

    @Test("T-14 mit Fotos: Fotopfad und Fotobytes überstehen Export, Import und Wiederherstellen")
    func photoRoundTrip() throws {
        let (_, doc) = withPhoto()
        let decoded = try BackupCodec.decode(BackupCodec.encode(doc))
        #expect(decoded == doc)
        #expect(errors(decoded).isEmpty)
        let restored = try BackupRestore.restore(decoded, into: GearDataset(), mode: .replace)
        #expect(restored.gear.first { $0.id == bike }?.photoPath == "gear/rennrad.jpg")
        #expect(BackupRestore.media(of: decoded, for: restored) == [BackupMedia(path: "gear/rennrad.jpg", data: photo)])
    }

    @Test("Ohne Fotos fehlt das Feld im JSON; ältere Dateien ohne Feld bleiben lesbar")
    func noMediaKeepsFormat() throws {
        let doc = BackupDocument(exportedAt: day(40), data: richDataset())
        #expect(doc.media == nil)
        let json = String(decoding: try BackupCodec.encode(doc), as: UTF8.self)
        #expect(!json.contains("\"media\""))
        #expect(!json.contains("photoPath"))
        #expect(try BackupCodec.decode(Data(json.utf8)).media == nil)
    }

    @Test("Unsichere Fotopfade (absolut, „..“, leer, Backslash) sind Fehler und blockieren den Import")
    func unsafePaths() {
        for bad in ["../x.jpg", "/etc/passwd", "", "a/../../b.jpg", "a\\b.jpg", "gear/./x.jpg"] {
            #expect(!BackupMediaPath.isSafe(bad), "\(bad)")
            let (_, doc) = withPhoto(bad)
            #expect(errors(doc).contains(.invalidMediaPath(bad)), "\(bad)")
            #expect(!BackupValidator.isImportable(doc))
        }
        #expect(BackupMediaPath.isSafe("gear/rennrad.jpg"))
        #expect(BackupMediaPath.isSafe("x.heic"))
    }

    @Test("Export ohne Fotos: Fotopfad ohne Datei ist nur eine Warnung, der Import bleibt möglich")
    func missingMediaIsWarning() {
        var d = richDataset()
        d.gear[0].photoPath = "gear/rennrad.jpg"
        let doc = BackupDocument(exportedAt: day(40), data: d)
        #expect(BackupValidator.validate(doc) == [.missingMedia(gearID: bike, path: "gear/rennrad.jpg")])
        #expect(BackupIssue.missingMedia(gearID: bike, path: "x").isWarning)
        #expect(BackupValidator.isImportable(doc))
    }

    @Test("Doppelte Fotodatei ist ein Fehler, ein Foto ohne Gegenstand nur eine Warnung")
    func duplicateAndOrphanMedia() {
        var (d, doc) = withPhoto()
        doc.media = [BackupMedia(path: "gear/rennrad.jpg", data: photo), BackupMedia(path: "gear/rennrad.jpg", data: Data([1]))]
        #expect(errors(doc) == [.duplicateMediaPath("gear/rennrad.jpg")])
        d.gear[0].photoPath = nil
        doc = BackupDocument(exportedAt: day(40), data: d, media: [BackupMedia(path: "gear/fremd.jpg", data: photo)])
        #expect(BackupValidator.validate(doc) == [.unreferencedMedia("gear/fremd.jpg")])
        #expect(BackupValidator.isImportable(doc))
        #expect(BackupRestore.media(of: doc, for: d).isEmpty)
    }

    @Test("Zusammenführen mit Vorrang Bestand: das Foto des Backups wird nur geschrieben, wenn das Ergebnis es nutzt")
    func mergeKeepsOnlyReferencedMedia() throws {
        let (_, doc) = withPhoto()
        let existing = richDataset()   // lokal ohne Foto
        let keepLocal = try BackupRestore.restore(doc, into: existing, mode: .merge(prefer: .existing))
        #expect(keepLocal.gear.first { $0.id == bike }?.photoPath == nil)
        #expect(BackupRestore.media(of: doc, for: keepLocal).isEmpty)
        let takeBackup = try BackupRestore.restore(doc, into: existing, mode: .merge(prefer: .backup))
        #expect(BackupRestore.media(of: doc, for: takeBackup).map(\.path) == ["gear/rennrad.jpg"])
    }
}

@Suite("Backup-Vorschau je Typ (SPEC 11)")
struct BackupPreviewSummaryTests {

    @Test("Vorschau zählt je Typ neu, unverändert und Konflikt")
    func summaryPerEntity() {
        var existing = richDataset()
        existing.gear.removeLast()              // Helm fehlt lokal → neu
        existing.gear[3].name = "Alte Schuhe"   // Laufschuhe lokal umbenannt → Konflikt
        existing.activities.removeAll { $0.id == id(402) }
        let preview = BackupRestore.preview(BackupDocument(exportedAt: day(40), data: richDataset()), against: existing)
        #expect(preview.summary[.gear] == BackupEntityChange(new: 1, unchanged: 3, conflicting: 1))
        #expect(preview.summary[.activity] == BackupEntityChange(new: 1, unchanged: 3, conflicting: 0))
        #expect(preview.summary[.segment] == BackupEntityChange(new: 0, unchanged: 1, conflicting: 0))
        #expect(preview.summary[.gear]?.total == 5)
        #expect(preview.hasConflicts)
        #expect(!BackupRestore.preview(BackupDocument(exportedAt: day(40), data: richDataset()), against: GearDataset()).hasConflicts)
    }
}

@Suite("Löschen (SPEC 11)")
struct DataDeletionTests {

    @Test("Ausrüstung löschen entfernt Montagen, Zuordnungen, Wartung und Status, Mitglieder in Regeln/Sets/Posteingang")
    func deleteBike() throws {
        let before = richDataset()
        let d = try DataDeletion.deleteGear(bike, in: before)
        #expect(!d.gear.contains { $0.id == bike })
        #expect(d.gear.count == 4)                                         // Ketten bleiben als eigene Teile
        #expect(d.installations.isEmpty)
        #expect(d.assignments.map(\.id) == [id(602)])                       // nur die Laufschuh-Zuordnung bleibt
        #expect(d.maintenanceEvents.map(\.id) == [id(700), id(701)])
        #expect(d.presets.first?.memberGearIDs == [helmet])
        #expect(d.assignmentRules.first { $0.id == id(900) }?.gearIDs == [helmet])
        // Offener Vorschlag „Rad“ ist weg: der Eintrag fragt neu nach (Helm bleibt Kandidat) und hat eine neue Revision.
        let p950 = try #require(d.pendings.first { $0.id == id(950) })
        #expect(p950.state == .unresolved)
        #expect(p950.proposedGearIDs.isEmpty && p950.alternatives.isEmpty)
        #expect(p950.candidateGearIDs == [helmet])
        #expect(p950.proposalRevision == 5)
        let p951 = try #require(d.pendings.first { $0.id == id(951) })
        #expect(p951.candidateGearIDs == [helmet])
        #expect(p951.proposalRevision == 2)
        #expect(BackupValidator.validate(d).filter { !$0.isWarning }.isEmpty)
        #expect(!LedgerBuilder.build(d.ledgerInput).entries.contains { $0.key.gearID == bike })
    }

    @Test("Leere Regel und leeres Set verschwinden, der Sport verliert das Standard-Set")
    func emptyRuleAndPresetRemoved() throws {
        var d = try DataDeletion.deleteGear(shoes, in: richDataset())
        #expect(!d.assignmentRules.contains { $0.id == id(901) })
        d = try DataDeletion.deleteGear(helmet, in: d)
        d = try DataDeletion.deleteGear(bike, in: d)
        #expect(d.presets.isEmpty)
        #expect(d.sportProfiles.first?.defaultPresetID == nil)
        #expect(d.assignmentRules.isEmpty)
        #expect(BackupValidator.validate(d).filter { !$0.isWarning }.isEmpty)
    }

    @Test("Komponente löschen entfernt nur ihre Montage, Regeln und Wartung")
    func deleteComponent() throws {
        let d = try DataDeletion.deleteGear(chainNew, in: richDataset())
        #expect(d.installations.map(\.id) == [id(200)])
        #expect(d.maintenanceRules.isEmpty)
        #expect(d.maintenanceEvents.map(\.id) == [id(700), id(702)])
        #expect(d.assignments.count == 4)
    }

    @Test("Unbekannte Ausrüstung löschen ist ein Fehler und ändert nichts")
    func deleteUnknownGear() {
        #expect(throws: DeletionError.gearNotFound(id(77))) { try DataDeletion.deleteGear(id(77), in: richDataset()) }
    }

    @Test("Manuelle Aktivität löschen entfernt sie samt Zuordnung vollständig")
    func deleteManualActivity() throws {
        let d = try DataDeletion.deleteActivity(id(402), in: richDataset(), now: day(50))
        #expect(!d.activities.contains { $0.id == id(402) })
        #expect(!d.assignments.contains { $0.activityID == id(402) })
        #expect(!LedgerBuilder.build(d.ledgerInput).entries.contains { $0.activityID == id(402) })
    }

    @Test("Health-Aktivität löschen hinterlässt einen Grabstein (I-08): keine Nutzung, Posteingang hinfällig, neue Revision")
    func deleteHealthActivity() throws {
        let before = richDataset()
        let d = try DataDeletion.deleteActivity(id(401), in: before, now: day(50))
        let a = try #require(d.activities.first { $0.id == id(401) })
        #expect(a.deletedAt == day(50))
        #expect(a.sourceID == "HK-2")                       // bleibt, damit der Import sie wiedererkennt
        #expect(a.revision == 2)
        #expect(!d.assignments.contains { $0.activityID == id(401) })
        let p = try #require(d.pendings.first { $0.id == id(950) })
        #expect(p.state == .obsolete && p.resolution == .obsolete)
        #expect(p.proposalRevision == 5)
        #expect(!LedgerBuilder.build(d.ledgerInput).entries.contains { $0.activityID == id(401) })
        #expect(BackupValidator.validate(d).filter { !$0.isWarning }.isEmpty)
        // Erledigte Einträge anderer Aktivitäten bleiben unberührt.
        #expect(d.pendings.first { $0.id == id(951) } == before.pendings.first { $0.id == id(951) })
    }

    @Test("Bereits gelöschte oder unbekannte Aktivität: Fehler, nichts ändert sich")
    func deleteTwice() throws {
        let d = try DataDeletion.deleteActivity(id(401), in: richDataset(), now: day(50))
        #expect(throws: DeletionError.activityNotFound(id(401))) { try DataDeletion.deleteActivity(id(401), in: d, now: day(51)) }
        #expect(throws: DeletionError.activityNotFound(id(99))) { try DataDeletion.deleteActivity(id(99), in: d, now: day(51)) }
    }
}
