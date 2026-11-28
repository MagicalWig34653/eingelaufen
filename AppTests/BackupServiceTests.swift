import Foundation
import GearCore
import SwiftData
import Testing
@testable import Eingelaufen

/// M8 Datensicherung und Löschen in der App (SPEC 11, T-14): Export/Import über den echten Speicher und Fotoordner.
@Suite struct BackupServiceTests {
    private let photo = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03])

    private func tempMedia() -> MediaStore {
        MediaStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("media-\(UUID().uuidString)", isDirectory: true))
    }

    /// Voller Bestand (alle Wahrheits-Entitäten) mit Foto am Rad.
    private func seeded() async throws -> (BackupService, GearDataset) {
        var d = MapperTests.fullDataset()
        d.gear[0].photoPath = "gear/rad.jpg"
        let p = try makePersistence()
        try await p.load(d, now: t0)
        let media = tempMedia()
        try media.write(BackupMedia(path: "gear/rad.jpg", data: photo))
        return (BackupService(persistence: p, media: media), d)
    }

    @Test("T-14 App-Rundreise mit Fotos: IDs, Chronologie, Montagen, Regeln, Wartung, Posteingang und Foto auf einem neuen Gerät")
    func roundTripWithPhotos() async throws {
        let (source, d) = try await seeded()
        let bytes = try await source.export(includePhotos: true, now: day(10))

        let target = BackupService(persistence: try makePersistence(), media: tempMedia())
        let candidate = try await target.preview(bytes)
        #expect(candidate.preview.conflicts.isEmpty)
        #expect(candidate.preview.issues.isEmpty)
        #expect(candidate.preview.summary[.gear] == BackupEntityChange(new: 2, unchanged: 0, conflicting: 0))
        try await target.restore(candidate.document, mode: .replace, now: day(11))

        #expect(normalized(try await target.persistence.dataset()) == normalized(d))
        #expect(target.media.read("gear/rad.jpg") == photo)
        #expect(try await target.persistence.ledger() == (try await source.persistence.ledger()))
        #expect(try await target.persistence.outbox(pendingOnly: true).last?.kind == .dataReplaced)
    }

    @Test("Karte F33E735D: Vorschau meldet, ob Ersetzen einen Bestand verwirft (nach dem Onboarding allein nicht)")
    func previewFlagsReplacingExistingData() async throws {
        let (source, _) = try await seeded()
        let bytes = try await source.export(includePhotos: false, now: day(10))
        #expect(try await source.preview(bytes).preview.replaceDiscardsExisting, "eigener Bestand")

        let fresh = BackupService(persistence: try makePersistence(), media: tempMedia())
        _ = try await fresh.persistence.apply(.completeOnboarding(OnboardingChoice(categories: [.cycling, .running], health: .later)), now: t0)
        #expect(!(try await fresh.persistence.dataset().sportProfiles.isEmpty), "Onboarding legt Sportarten an")
        #expect(!(try await fresh.preview(bytes).preview.replaceDiscardsExisting), "nur Onboarding: keine Rückfrage")

        _ = try await fresh.persistence.apply(.createGear(GearItem(name: "Helm", category: .cycling)), now: t0)
        #expect(try await fresh.preview(bytes).preview.replaceDiscardsExisting, "ein eigenes Teil genügt")
    }

    @Test("Export ohne Fotos: Datei ohne Bilder, Fotopfad bleibt, Vorschau warnt, Import ist möglich")
    func exportWithoutPhotos() async throws {
        let (source, _) = try await seeded()
        let bytes = try await source.export(includePhotos: false, now: day(10))
        #expect(try BackupCodec.decode(bytes).media == nil)
        let target = BackupService(persistence: try makePersistence(), media: tempMedia())
        let candidate = try await target.preview(bytes)
        #expect(candidate.preview.issues.contains { $0.isWarning })
        try await target.restore(candidate.document, mode: .replace, now: day(11))
        #expect(target.media.read("gear/rad.jpg") == nil)
    }

    @Test("Vorschau zeigt Konflikte; Zusammenführen behält je nach Wahl den Bestand oder das Backup")
    func previewAndMerge() async throws {
        let (source, d) = try await seeded()
        let bytes = try await source.export(includePhotos: true, now: day(10))
        let bike = d.gear[0].id

        let local = try makePersistence()
        var mine = d
        mine.gear[0].name = "Rad lokal umbenannt"
        mine.gear[0].photoPath = nil
        try await local.load(mine, now: t0)
        let target = BackupService(persistence: local, media: tempMedia())
        let candidate = try await target.preview(bytes)
        #expect(candidate.preview.conflicts == [BackupConflict(entity: .gear, id: bike)])
        #expect(candidate.preview.summary[.gear] == BackupEntityChange(new: 0, unchanged: 1, conflicting: 1))

        try await target.restore(candidate.document, mode: .merge(prefer: .existing), now: day(11))
        #expect(try await local.dataset().gear.first { $0.id == bike }?.name == "Rad lokal umbenannt")
        #expect(target.media.read("gear/rad.jpg") == nil)

        try await target.restore(candidate.document, mode: .merge(prefer: .backup), now: day(12))
        #expect(try await local.dataset().gear.first { $0.id == bike }?.name == "Rad")
        #expect(target.media.read("gear/rad.jpg") == photo)
    }

    @Test("Kaputte oder ungültige Datei: klarer Fehler, der Bestand bleibt unverändert")
    func brokenFileChangesNothing() async throws {
        let (service, d) = try await seeded()
        await #expect(throws: BackupError.malformed) { try await service.preview(Data("kein Backup".utf8)) }
        var bad = BackupDocument(exportedAt: day(10), data: d)
        bad.data.assignments[0].gearID = UUID()
        await #expect(throws: BackupError.self) { try await service.restore(bad, mode: .replace, now: day(11)) }
        #expect(normalized(try await service.persistence.dataset()) == normalized(d))
    }

    @Test("Ausrüstung löschen: weg samt Historie, Ledger neu, Foto entfernt, Outbox meldet die Änderung")
    func deleteGear() async throws {
        let (service, d) = try await seeded()
        let bike = d.gear[0].id
        try await service.deleteGear(bike, now: day(10))
        let after = try await service.persistence.dataset()
        #expect(!after.gear.contains { $0.id == bike })
        #expect(after.installations.isEmpty && after.assignments.isEmpty)
        #expect(!(try await service.persistence.ledger()).contains { $0.gearID == bike })
        #expect(service.media.read("gear/rad.jpg") == nil)
        #expect(try await service.persistence.outbox(pendingOnly: true).last?.kind == .gearChanged)
        await #expect(throws: PersistenceError.gearNotFound(bike)) { try await service.persistence.apply(.deleteGear(bike), now: day(11)) }
    }

    @Test("Aktivität löschen: Health-Training wird Grabstein ohne Nutzung, manuelle verschwindet ganz")
    func deleteActivity() async throws {
        let (service, d) = try await seeded()
        let hk = d.activities[0].id
        _ = try await service.persistence.apply(.deleteActivity(hk), now: day(10))
        let after = try await service.persistence.dataset()
        #expect(after.activities.first { $0.id == hk }?.deletedAt == day(10))
        #expect(try await service.persistence.ledger().isEmpty)
        #expect(try await service.persistence.outbox(pendingOnly: true).last?.kind == .activityChanged)

        let manual = try await service.persistence.apply(.addManualActivity(ManualActivityInput(
            sportType: SportType(rawValue: 37), startAt: day(5), durationSeconds: 1_800, distanceMeters: 5_000, gearIDs: [])), now: day(6))
        let manualID = try #require(manual.activityID)
        _ = try await service.persistence.apply(.deleteActivity(manualID), now: day(10))
        #expect(!(try await service.persistence.dataset()).activities.contains { $0.id == manualID })
        await #expect(throws: PersistenceError.activityNotFound) { try await service.persistence.apply(.deleteActivity(hk), now: day(11)) }
    }

    @Test("Alle App-Daten löschen: Bestand, Ledger, Einstellungen, Anker und Fotos sind weg, das Onboarding beginnt neu")
    func deleteAllData() async throws {
        let (service, _) = try await seeded()
        _ = try await service.persistence.apply(.completeOnboarding(OnboardingChoice(categories: [.cycling], health: .later)), now: t0)
        try await service.deleteAllData(now: day(10))
        #expect(try await service.persistence.dataset() == GearDataset())
        #expect(try await service.persistence.ledger().isEmpty)
        #expect(try await service.persistence.settings().onboardingCompleted == false)
        #expect(try await service.persistence.notificationRecords().isEmpty)
        #expect(service.media.read("gear/rad.jpg") == nil)
        #expect(try await service.persistence.outbox(pendingOnly: true).map(\.kind) == [.dataReplaced])
    }

    // MARK: Zusammenspiel mit dem Health-Import

    private func workout(_ sourceID: String) -> WorkoutChanges {
        let w = IncomingWorkout(sourceID: sourceID, sportType: SportType(rawValue: 37), startAt: day(1),
                                endAt: day(1).addingTimeInterval(3_600), distanceMeters: 10_000, durationSeconds: 3_600)
        return WorkoutChanges(batch: ImportBatch(upserts: [w]), anchor: Data(sourceID.utf8))
    }

    private func imported() async throws -> BackupService {
        let service = BackupService(persistence: try makePersistence(), media: tempMedia())
        _ = try await service.persistence.apply(.connectHealth(.all), now: t0)
        _ = try await service.persistence.commitImport(workout("W1"), since: nil, now: day(2))
        return service
    }

    @Test("Gelöschtes Health-Training bleibt auch nach Zeitraumwechsel und erneutem Import gelöscht")
    func deletedWorkoutStaysDeleted() async throws {
        let service = try await imported()
        let activity = try #require(try await service.persistence.dataset().activities.first)
        _ = try await service.persistence.apply(.deleteActivity(activity.id), now: day(3))
        _ = try await service.persistence.apply(.connectHealth(.days90), now: day(4))
        let since = try await service.persistence.importState().since
        _ = try await service.persistence.commitImport(workout("W1"), since: since, now: day(5))
        let after = try await service.persistence.dataset()
        #expect(after.activities.count == 1 && after.activities[0].deletedAt == day(3))
        #expect(try await service.persistence.ledger().isEmpty && after.pendings.allSatisfy { $0.state == .obsolete })
    }

    @Test("Wiederherstellen setzt den Health-Anker zurück: der nächste Abgleich holt fehlende Trainings nach")
    func restoreResetsAnchor() async throws {
        let service = try await imported()
        #expect(try await service.persistence.importState().anchor != nil)
        try await service.restore(BackupDocument(exportedAt: day(3), data: GearDataset()), mode: .replace, now: day(3))
        #expect(try await service.persistence.importState().anchor == nil)
        #expect(try await service.persistence.importState().isEnabled)
    }

    @Test("Ein Import, der während „Alle Daten löschen“ lief, schreibt nichts in den leeren Bestand")
    func lateImportAfterDeleteAllIsIgnored() async throws {
        let service = try await imported()
        try await service.deleteAllData(now: day(3))
        _ = try await service.persistence.commitImport(workout("W2"), since: nil, now: day(4))
        #expect(try await service.persistence.dataset() == GearDataset())
        #expect(try await service.persistence.importState().anchor == nil)
    }

    @Test("Zusammenführen mit Vorrang Bestand überschreibt kein lokales Foto mit gleichem Pfad")
    func mergeKeepsLocalPhoto() async throws {
        let (source, d) = try await seeded()
        let bytes = try await source.export(includePhotos: true, now: day(10))
        let local = try makePersistence()
        try await local.load(d, now: t0)
        let target = BackupService(persistence: local, media: tempMedia())
        let mine = Data([9, 9, 9])
        try target.media.write(BackupMedia(path: "gear/rad.jpg", data: mine))
        let candidate = try await target.preview(bytes)
        try await target.restore(candidate.document, mode: .merge(prefer: .existing), now: day(11))
        #expect(target.media.read("gear/rad.jpg") == mine)
        try await target.restore(candidate.document, mode: .merge(prefer: .backup), now: day(12))
        #expect(target.media.read("gear/rad.jpg") == photo)
    }
}

