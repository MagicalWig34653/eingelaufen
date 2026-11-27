import Foundation

// Backup v1 (SPEC 11, ARCHITEKTUR 7, T-14). Ein Backup enthält nur Wahrheitsdaten (`GearDataset`), nie das
// Ledger: es wird nach dem Wiederherstellen aus den Wahrheitsdaten neu gebaut (I-10, `LedgerBuilder`).
// Der Kern liest/schreibt Bytes und prüft Inhalte; Dateizugriff, Importoberfläche und Neuaufbau gehören der App.

public struct BackupDocument: Codable, Equatable, Sendable {
    /// Layout der Datei. Wird nur bei inkompatiblen Änderungen erhöht; neuere Dateien lehnt der Leser ab.
    public static let currentFormatVersion = 1
    /// Datenmodell-Version der erzeugenden App (für spätere Migrationen).
    public static let currentSchemaVersion = 1

    public var formatVersion: Int
    public var appSchemaVersion: Int
    public var exportedAt: Date
    public var data: GearDataset
    /// Fotos (M8), nur wenn mit Fotos exportiert; `nil` = ohne Fotos (Feld fehlt dann im JSON).
    public var media: [BackupMedia]?

    public init(exportedAt: Date, data: GearDataset, media: [BackupMedia]? = nil) {
        self.formatVersion = Self.currentFormatVersion
        self.appSchemaVersion = Self.currentSchemaVersion
        self.exportedAt = exportedAt
        self.data = data
        self.media = media
    }
}

public struct BackupMedia: Codable, Hashable, Sendable {
    public var path: String
    public var data: Data
    public init(path: String, data: Data) { self.path = path; self.data = data }
}

/// Fotos landen beim Import unter Application Support/Media: nur einfache relative Pfade, nie aus dem Ordner heraus.
public enum BackupMediaPath {
    public static func isSafe(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

public enum BackupEntity: String, Codable, Sendable, CaseIterable {
    case gear, statusChange, installation, preset, sportProfile, activity, segment
    case assignment, maintenanceEvent, maintenanceRule, assignmentRule, pending
}

public enum BackupIssue: Hashable, Sendable {
    case unsupportedFormatVersion(Int)
    /// Datenmodell der erzeugenden App ist neuer als dieses: Felder gingen still verloren, daher kein Import.
    case unsupportedSchemaVersion(Int)
    case duplicateID(BackupEntity, UUID)
    case danglingReference(BackupEntity, UUID, missing: UUID)
    case segmentActivityMismatch(assignmentID: UUID)
    case installation(InstallationIssue)
    case duplicateSourceID(String)
    case invalidActivity(UUID)
    case inconsistentPending(UUID)
    case invalidMediaPath(String)
    case duplicateMediaPath(String)
    case missingMedia(gearID: UUID, path: String)
    case unreferencedMedia(String)

    /// Warnungen blockieren den Import nicht (z. B. Montage vor Kaufdatum, I-03; Export ohne Fotos).
    public var isWarning: Bool {
        switch self {
        case let .installation(issue): issue.isWarning
        case .missingMedia, .unreferencedMedia: true
        default: false
        }
    }
}

public enum BackupError: Error, Equatable, Sendable {
    case malformed
    case unsupportedFormatVersion(Int)
    case unsupportedSchemaVersion(Int)
    case invalid([BackupIssue])
}

public enum BackupCodec {
    private struct Header: Decodable { var formatVersion: Int; var appSchemaVersion: Int? }

    /// Stabile Ausgabe (sortierte Schlüssel). Datumswerte als Sekunden seit 2001-01-01 UTC (Foundation-Standard),
    /// damit der Round-Trip verlustfrei ist.
    public static func encode(_ document: BackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(document)
    }

    /// Prüft zuerst nur den Kopf: eine neuere Formatversion wird abgelehnt, bevor irgendetwas gelesen wird.
    public static func decode(_ data: Data) throws -> BackupDocument {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else { throw BackupError.malformed }
        guard (1...BackupDocument.currentFormatVersion).contains(header.formatVersion) else {
            throw BackupError.unsupportedFormatVersion(header.formatVersion)
        }
        // Ein neueres Datenmodell kennt Felder, die dieses Schema beim Lesen verwerfen würde: vorher ablehnen.
        if let schema = header.appSchemaVersion, schema > BackupDocument.currentSchemaVersion {
            throw BackupError.unsupportedSchemaVersion(schema)
        }
        guard let document = try? decoder.decode(BackupDocument.self, from: data) else { throw BackupError.malformed }
        return document
    }
}

public enum BackupValidator {
    public static func validate(_ document: BackupDocument) -> [BackupIssue] {
        var issues: [BackupIssue] = []
        if !(1...BackupDocument.currentFormatVersion).contains(document.formatVersion) {
            issues.append(.unsupportedFormatVersion(document.formatVersion))
        }
        if document.appSchemaVersion > BackupDocument.currentSchemaVersion {
            issues.append(.unsupportedSchemaVersion(document.appSchemaVersion))
        }
        issues += validate(document.data)
        issues += validateMedia(document)
        return issues
    }

    private static func validateMedia(_ document: BackupDocument) -> [BackupIssue] {
        var issues: [BackupIssue] = []
        var files = Set<String>()
        for m in document.media ?? [] {
            if !BackupMediaPath.isSafe(m.path) { issues.append(.invalidMediaPath(m.path)) }
            if !files.insert(m.path).inserted { issues.append(.duplicateMediaPath(m.path)) }
        }
        var referenced = Set<String>()
        for g in document.data.gear {
            guard let path = g.photoPath else { continue }
            referenced.insert(path)
            if !BackupMediaPath.isSafe(path) { issues.append(.invalidMediaPath(path)) }
            else if !files.contains(path) { issues.append(.missingMedia(gearID: g.id, path: path)) }
        }
        for path in files.subtracting(referenced).sorted() where BackupMediaPath.isSafe(path) {
            issues.append(.unreferencedMedia(path))
        }
        return issues
    }

    public static func isImportable(_ document: BackupDocument) -> Bool {
        !validate(document).contains { !$0.isWarning }
    }

    public static func validate(_ d: GearDataset) -> [BackupIssue] {
        var issues: [BackupIssue] = []

        func duplicates<T: Identifiable>(_ items: [T], _ entity: BackupEntity) where T.ID == UUID {
            var seen = Set<UUID>()
            for item in items where !seen.insert(item.id).inserted { issues.append(.duplicateID(entity, item.id)) }
        }
        duplicates(d.gear, .gear); duplicates(d.statusChanges, .statusChange); duplicates(d.installations, .installation)
        duplicates(d.presets, .preset); duplicates(d.sportProfiles, .sportProfile); duplicates(d.activities, .activity)
        duplicates(d.segments, .segment); duplicates(d.assignments, .assignment)
        duplicates(d.maintenanceEvents, .maintenanceEvent); duplicates(d.maintenanceRules, .maintenanceRule)
        duplicates(d.assignmentRules, .assignmentRule); duplicates(d.pendings, .pending)

        let gearIDs = Set(d.gear.map(\.id)), activityIDs = Set(d.activities.map(\.id)), presetIDs = Set(d.presets.map(\.id))
        let segmentActivity = Dictionary(d.segments.map { ($0.id, $0.activityID) }, uniquingKeysWith: { a, _ in a })

        func need(_ entity: BackupEntity, _ id: UUID, _ refs: [UUID], in known: Set<UUID>) {
            for ref in refs where !known.contains(ref) { issues.append(.danglingReference(entity, id, missing: ref)) }
        }
        for x in d.installations { need(.installation, x.id, [x.parentGearID, x.childGearID], in: gearIDs) }
        for x in d.statusChanges { need(.statusChange, x.id, [x.gearID], in: gearIDs) }
        for x in d.maintenanceEvents { need(.maintenanceEvent, x.id, [x.gearID], in: gearIDs) }
        for x in d.maintenanceRules { need(.maintenanceRule, x.id, [x.gearID], in: gearIDs) }
        for x in d.assignmentRules { need(.assignmentRule, x.id, x.gearIDs, in: gearIDs) }
        for x in d.presets { need(.preset, x.id, x.memberGearIDs, in: gearIDs) }
        for x in d.sportProfiles { need(.sportProfile, x.id, x.defaultPresetID.map { [$0] } ?? [], in: presetIDs) }
        for x in d.segments { need(.segment, x.id, [x.activityID], in: activityIDs) }
        for x in d.assignments {
            need(.assignment, x.id, [x.activityID], in: activityIDs)
            need(.assignment, x.id, [x.gearID], in: gearIDs)
            if let segmentID = x.segmentID {
                if let owner = segmentActivity[segmentID] {
                    if owner != x.activityID { issues.append(.segmentActivityMismatch(assignmentID: x.id)) }
                } else {
                    issues.append(.danglingReference(.assignment, x.id, missing: segmentID))
                }
            }
        }
        for x in d.pendings {
            need(.pending, x.id, [x.activityID], in: activityIDs)
            need(.pending, x.id, x.proposedGearIDs + x.alternatives.flatMap { $0 } + x.candidateGearIDs, in: gearIDs)
            if !isConsistent(x) { issues.append(.inconsistentPending(x.id)) }
        }

        // Montageinvarianten I-01…I-03 gelten auch für importierte Daten.
        let graph = InstallationGraph(d.installations)
        issues += (graph.validate() + graph.purchaseWarnings(gear: d.gear)).map(BackupIssue.installation)

        var sourceIDs = Set<String>()
        for a in d.activities {
            if let s = a.sourceID, !sourceIDs.insert(s).inserted { issues.append(.duplicateSourceID(s)) }
            let numbers = [a.durationSeconds] + (a.distanceMeters.map { [$0] } ?? [])
            if a.endAt < a.startAt || numbers.contains(where: { $0 < 0 || !$0.isFinite }) {
                issues.append(.invalidActivity(a.id))
            }
        }
        return issues
    }

    /// Endzustände brauchen die passende Auflösung (I-09); offene Zustände dürfen noch keine haben.
    private static func isConsistent(_ p: PendingAssignment) -> Bool {
        switch p.state {
        case .resolved: p.resolution == .confirmedProposal || p.resolution == .chosen
        case .dismissed: p.resolution == .dismissed
        case .obsolete: p.resolution == .obsolete
        case .unresolved, .suggested, .ignored: p.resolution == .none
        }
    }
}

public struct BackupConflict: Hashable, Sendable {
    public var entity: BackupEntity
    public var id: UUID
    public init(entity: BackupEntity, id: UUID) { self.entity = entity; self.id = id }
}

public struct BackupPreview: Equatable, Sendable {
    public var counts: [BackupEntity: Int]
    /// Gleiche ID, anderer Inhalt als im vorhandenen Bestand.
    public var conflicts: [BackupConflict]
    /// Fehler und Warnungen des Backups.
    public var issues: [BackupIssue]
    /// Je Typ: neu, unverändert, Konflikt (nur Typen mit Einträgen im Backup).
    public var summary: [BackupEntity: BackupEntityChange]
    public var hasConflicts: Bool { !conflicts.isEmpty }
}

public struct BackupEntityChange: Equatable, Sendable {
    public var new: Int
    public var unchanged: Int
    public var conflicting: Int
    public var total: Int { new + unchanged + conflicting }
    public init(new: Int, unchanged: Int, conflicting: Int) { self.new = new; self.unchanged = unchanged; self.conflicting = conflicting }
}

public enum MergePreference: Sendable { case backup, existing }

public enum RestoreMode: Equatable, Sendable {
    /// Der Bestand wird durch das Backup ersetzt.
    case replace
    /// Vereinigung nach ID; bei gleicher ID entscheidet `prefer`.
    case merge(prefer: MergePreference)
}

public enum BackupRestore {

    public static func preview(_ document: BackupDocument, against existing: GearDataset) -> BackupPreview {
        let b = document.data
        var counts: [BackupEntity: Int] = [
            .gear: b.gear.count, .statusChange: b.statusChanges.count, .installation: b.installations.count,
            .preset: b.presets.count, .sportProfile: b.sportProfiles.count, .activity: b.activities.count,
            .segment: b.segments.count, .assignment: b.assignments.count, .maintenanceEvent: b.maintenanceEvents.count,
            .maintenanceRule: b.maintenanceRules.count, .assignmentRule: b.assignmentRules.count, .pending: b.pendings.count,
        ]
        counts = counts.filter { $0.value > 0 }
        var conflicts: [BackupConflict] = []
        var summary: [BackupEntity: BackupEntityChange] = [:]
        func compare<T: Identifiable & Equatable>(_ entity: BackupEntity, _ mine: [T], _ backup: [T]) where T.ID == UUID {
            let local = Dictionary(mine.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var change = BackupEntityChange(new: 0, unchanged: 0, conflicting: 0)
            for item in backup {
                if let other = local[item.id] {
                    if other != item {
                        conflicts.append(BackupConflict(entity: entity, id: item.id))
                        change.conflicting += 1
                    } else {
                        change.unchanged += 1
                    }
                } else {
                    change.new += 1
                }
            }
            if change.total > 0 { summary[entity] = change }
        }
        let e = existing
        compare(.gear, e.gear, b.gear); compare(.statusChange, e.statusChanges, b.statusChanges)
        compare(.installation, e.installations, b.installations); compare(.preset, e.presets, b.presets)
        compare(.sportProfile, e.sportProfiles, b.sportProfiles); compare(.activity, e.activities, b.activities)
        compare(.segment, e.segments, b.segments); compare(.assignment, e.assignments, b.assignments)
        compare(.maintenanceEvent, e.maintenanceEvents, b.maintenanceEvents)
        compare(.maintenanceRule, e.maintenanceRules, b.maintenanceRules)
        compare(.assignmentRule, e.assignmentRules, b.assignmentRules); compare(.pending, e.pendings, b.pendings)
        return BackupPreview(counts: counts, conflicts: conflicts, issues: BackupValidator.validate(document), summary: summary)
    }

    /// Liefert den neuen Bestand oder wirft; bei einem Fehler bleibt der vorhandene Bestand unverändert.
    /// Das Ledger baut der Aufrufer danach aus dem Ergebnis neu (`LedgerBuilder.build`).
    public static func restore(_ document: BackupDocument, into existing: GearDataset, mode: RestoreMode) throws -> GearDataset {
        let incoming = BackupValidator.validate(document).filter { !$0.isWarning }
        guard incoming.isEmpty else { throw BackupError.invalid(incoming) }

        let result: GearDataset
        switch mode {
        case .replace:
            result = document.data
        case let .merge(prefer):
            result = merged(existing, document.data, prefer: prefer)
            let problems = BackupValidator.validate(result).filter { !$0.isWarning }
            guard problems.isEmpty else { throw BackupError.invalid(problems) }
        }
        return result
    }

    /// Die Fotos, die nach dem Wiederherstellen zu schreiben sind: nur sichere Pfade, die das Ergebnis auch nutzt.
    public static func media(of document: BackupDocument, for result: GearDataset) -> [BackupMedia] {
        let used = Set(result.gear.compactMap(\.photoPath))
        var seen = Set<String>()
        return (document.media ?? []).filter { used.contains($0.path) && BackupMediaPath.isSafe($0.path) && seen.insert($0.path).inserted }
    }

    private static func merged(_ e: GearDataset, _ b: GearDataset, prefer: MergePreference) -> GearDataset {
        func union<T: Identifiable>(_ mine: [T], _ backup: [T]) -> [T] where T.ID == UUID {
            var result = mine
            var index = Dictionary(mine.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
            for item in backup {
                if let i = index[item.id] {
                    if prefer == .backup { result[i] = item }
                } else {
                    index[item.id] = result.count
                    result.append(item)
                }
            }
            return result
        }
        // Zuordnungen, Segmente und Posteingang gehören zu ihrer Aktivität. Eine Vereinigung nach ID kann Löschungen
        // nicht erkennen und würde eine später korrigierte, alte Zuordnung wiederbeleben (dieselbe Fahrt zählt dann für
        // zwei Gegenstände). Darum gilt für Aktivitäten, die auf beiden Seiten existieren, nur die gewählte Seite.
        let shared = Set(e.activities.map(\.id)).intersection(b.activities.map(\.id))
        func owned<T>(_ items: [T], by activity: (T) -> UUID, drop dropShared: Bool) -> [T] {
            dropShared ? items.filter { !shared.contains(activity($0)) } : items
        }
        let dropExisting = prefer == .backup, dropBackup = prefer == .existing
        let segments = union(owned(e.segments, by: \.activityID, drop: dropExisting), owned(b.segments, by: \.activityID, drop: dropBackup))
        let assignments = union(owned(e.assignments, by: \.activityID, drop: dropExisting), owned(b.assignments, by: \.activityID, drop: dropBackup))
        let pendings = union(owned(e.pendings, by: \.activityID, drop: dropExisting), owned(b.pendings, by: \.activityID, drop: dropBackup))
        var d = GearDataset()
        d.gear = union(e.gear, b.gear); d.statusChanges = union(e.statusChanges, b.statusChanges)
        d.installations = union(e.installations, b.installations); d.presets = union(e.presets, b.presets)
        d.sportProfiles = union(e.sportProfiles, b.sportProfiles); d.activities = union(e.activities, b.activities)
        d.segments = segments; d.assignments = assignments
        d.maintenanceEvents = union(e.maintenanceEvents, b.maintenanceEvents)
        d.maintenanceRules = union(e.maintenanceRules, b.maintenanceRules)
        d.assignmentRules = union(e.assignmentRules, b.assignmentRules); d.pendings = pendings
        return d
    }
}
