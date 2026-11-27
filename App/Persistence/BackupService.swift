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
        guard let files = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        let base = root.standardizedFileURL.path + "/"
        for case let file as URL in files where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let relative = String(file.standardizedFileURL.path.dropFirst(base.count))
            if !paths.contains(relative) { try fm.removeItem(at: file) }
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

    /// Ein Commit für den Bestand (Ledger neu, `dataReplaced`). Fotos werden vorher geschrieben (eine Datei ohne
    /// Verweis schadet nicht) und danach aufgeräumt. Bei einem Fehler bleibt der Bestand unverändert.
    func restore(_ document: BackupDocument, mode: RestoreMode, now: Date) async throws {
        let result = try BackupRestore.restore(document, into: try await persistence.dataset(), mode: mode)
        for photo in BackupRestore.media(of: document, for: result) { try media.write(photo) }
        try await persistence.load(result, now: now)
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
