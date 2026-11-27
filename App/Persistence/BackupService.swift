import Foundation
import GearCore

/// Fotoordner (Application Support/Media, ARCHITEKTUR 3.2). Pfade kommen nur über `BackupMediaPath.isSafe` hinein.
struct MediaStore: Sendable {
    let root: URL

    static var standard: MediaStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return MediaStore(root: support.appendingPathComponent("Media", isDirectory: true))
    }

    private func url(_ path: String) -> URL? {
        BackupMediaPath.isSafe(path) ? root.appendingPathComponent(path, isDirectory: false) : nil
    }

    func read(_ path: String) -> Data? { url(path).flatMap { try? Data(contentsOf: $0) } }

    func write(_ media: BackupMedia) throws {
        guard let target = url(media.path) else { throw BackupError.invalid([.invalidMediaPath(media.path)]) }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try media.data.write(to: target, options: [.atomic, .completeFileProtection])
    }

    /// Entfernt alle Fotos, die kein Gegenstand mehr nutzt (nach Löschen und Wiederherstellen).
    func prune(keeping paths: Set<String>) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return }
        // Relative Pfade direkt vom System: kein Vergleich absoluter Pfade (/var ↔ /private/var).
        for relative in try fm.subpathsOfDirectory(atPath: root.path) where !paths.contains(relative) {
            let file = root.appendingPathComponent(relative)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            try fm.removeItem(at: file)
        }
    }

    func removeAll() throws {
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }
}

/// Gelesene, geprüfte Datei mit Vorschau gegen den aktuellen Bestand; noch nichts geändert.
struct ImportCandidate: Sendable {
    var document: BackupDocument
    var preview: BackupPreview
}

/// Datensicherung und Löschen (SPEC 11, ARCHITEKTUR 7). Rechenlogik im Kern (`BackupRestore`, `DataDeletion`),
/// Schreiben nur über den `PersistenceActor`; Fotos liegen daneben im `MediaStore`.
struct BackupService: Sendable {
    let persistence: PersistenceActor
    let media: MediaStore

    /// JSON v1; mit Fotos als `media`-Liste in derselben Datei.
    func export(includePhotos: Bool, now: Date) async throws -> Data {
        let data = try await persistence.dataset()
        var photos: [BackupMedia]?
        if includePhotos {
            let paths = Set(data.gear.compactMap(\.photoPath)).sorted()
            photos = paths.compactMap { path in media.read(path).map { BackupMedia(path: path, data: $0) } }
        }
        return try BackupCodec.encode(BackupDocument(exportedAt: now, data: data, media: photos))
    }

    func preview(_ data: Data) async throws -> ImportCandidate {
        let document = try BackupCodec.decode(data)
        let preview = BackupRestore.preview(document, against: try await persistence.dataset())
        return ImportCandidate(document: document, preview: preview)
    }

    /// Ein Commit für den Bestand (Ledger neu, `dataReplaced`), danach die Fotos, die das Ergebnis nutzt, und
    /// Aufräumen. Bei einem ungültigen Backup bleibt alles unverändert.
    func restore(_ document: BackupDocument, mode: RestoreMode, now: Date) async throws {
        let result = try await persistence.restore(document, mode: mode, now: now)
        for photo in BackupRestore.media(of: document, for: result) {
            // Vorrang Bestand: ein vorhandenes lokales Foto bleibt, auch bei gleichem Pfad.
            if mode == .merge(prefer: .existing), media.read(photo.path) != nil { continue }
            try media.write(photo)
        }
        try media.prune(keeping: Set(result.gear.compactMap(\.photoPath)))
    }

    func deleteGear(_ id: UUID, now: Date) async throws {
        _ = try await persistence.apply(.deleteGear(id), now: now)
        try media.prune(keeping: Set(try await persistence.dataset().gear.compactMap(\.photoPath)))
    }

    func deleteAllData(now: Date) async throws {
        _ = try await persistence.apply(.deleteAllData, now: now)
        try media.removeAll()
    }
}
