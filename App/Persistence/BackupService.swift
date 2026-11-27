import Foundation
import GearCore

/// Fotoordner (Application Support/Media, ARCHITEKTUR 3.2). Pfade kommen nur über `BackupMediaPath.isSafe` hinein.
struct MediaStore: Sendable {
    let root: URL
    func read(_ path: String) -> Data? { nil }
    func write(_ media: BackupMedia) throws {}
    func prune(keeping paths: Set<String>) throws {}
    func removeAll() throws {}
}

struct ImportCandidate: Sendable {
    var document: BackupDocument
    var preview: BackupPreview
}

/// Datensicherung und Löschen (SPEC 11, M8).
struct BackupService: Sendable {
    let persistence: PersistenceActor
    let media: MediaStore

    func export(includePhotos: Bool, now: Date) async throws -> Data { Data() }
    func preview(_ data: Data) async throws -> ImportCandidate { throw BackupError.malformed }
    func restore(_ document: BackupDocument, mode: RestoreMode, now: Date) async throws {}
    func deleteGear(_ id: UUID, now: Date) async throws {}
    func deleteAllData(now: Date) async throws {}
}
