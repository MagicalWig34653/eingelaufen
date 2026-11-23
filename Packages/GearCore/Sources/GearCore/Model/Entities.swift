import Foundation

// Werttypen der Wahrheits-Entitäten (SPEC 5.1) – Teilmenge für M1b.
// M1a (Katalog) und M1c (Engine/Inbox/Backup) ergänzen Felder mit Standardwerten, ohne diese Typen umzubauen.
// Einheiten (ARCHITEKTUR A-08): Meter, Sekunden. Fehlende Werte sind `nil`, nie `0`.

/// Sportart als roher Schlüssel (HealthKit-`HKWorkoutActivityType.rawValue`); Katalog/Mapping folgt in M1a.
public struct SportType: RawRepresentable, Hashable, Codable, Sendable {
    public var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
}

/// Lebenszyklus (SPEC 4.2).
public enum GearStatus: String, Codable, Sendable, CaseIterable {
    case active, stored, retired, sold, disposed, lost, archived
}

public struct GearItem: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var purchaseDate: Date?
    public var status: GearStatus
    public var createdAt: Date
    /// Kategorie/Unterkategorie aus dem Katalog (M1a); Standard „Sonstige“, damit bestehende Aufrufe gültig bleiben.
    public var category: SportCategory
    public var subtype: SportSubtype?

    public init(id: UUID = UUID(), name: String, purchaseDate: Date? = nil,
                status: GearStatus = .active, createdAt: Date = Date(timeIntervalSince1970: 0),
                category: SportCategory = .other, subtype: SportSubtype? = nil) {
        self.id = id
        self.name = name
        self.purchaseDate = purchaseDate
        self.status = status
        self.createdAt = createdAt
        self.category = category
        self.subtype = subtype
    }
}

/// Montage: Intervall `[startedAt, endedAt)`, `endedAt == nil` heißt „noch montiert“ (ARCHITEKTUR A-07).
public struct Installation: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var parentGearID: UUID
    public var childGearID: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var notes: String?

    public init(id: UUID = UUID(), parentGearID: UUID, childGearID: UUID,
                startedAt: Date, endedAt: Date? = nil, notes: String? = nil) {
        self.id = id
        self.parentGearID = parentGearID
        self.childGearID = childGearID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
    }

    /// Halb offenes Intervall: `startedAt` gehört dazu, `endedAt` nicht.
    public func isActive(at t: Date) -> Bool {
        t >= startedAt && (endedAt.map { t < $0 } ?? true)
    }
}

public enum ActivitySource: String, Codable, Sendable {
    case healthKit, manual
}

public struct ActivityRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var source: ActivitySource
    public var sourceID: String?
    public var sportType: SportType
    public var startAt: Date
    public var endAt: Date
    /// `nil` = nicht gemessen (nie `0` erfinden, SPEC 5.2).
    public var distanceMeters: Double?
    public var durationSeconds: Double
    public var deletedAt: Date?
    /// Nur wenn Metadaten/Quelle es belastbar liefern; nie aus Distanz oder Sporttyp geraten (SPEC 3.3).
    public var isIndoor: Bool?
    /// Zählt jede inhaltliche Änderung (Import-Update, Korrektur); schützt veraltete Aktionen (ARCHITEKTUR 3.1).
    public var revision: Int

    public init(id: UUID = UUID(), source: ActivitySource = .manual, sourceID: String? = nil,
                sportType: SportType, startAt: Date, endAt: Date,
                distanceMeters: Double? = nil, durationSeconds: Double,
                deletedAt: Date? = nil, isIndoor: Bool? = nil, revision: Int = 1) {
        self.id = id
        self.source = source
        self.sourceID = sourceID
        self.sportType = sportType
        self.startAt = startAt
        self.endAt = endAt
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.deletedAt = deletedAt
        self.isIndoor = isIndoor
        self.revision = revision
    }
}

public struct ActivitySegment: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var activityID: UUID
    public var sportType: SportType
    public var startAt: Date
    public var endAt: Date
    /// Nur wenn die Quelle eine Segmentdistanz liefert; nie aus der Dauer verteilt (SPEC 5.2, T-08).
    public var distanceMeters: Double?

    public var durationSeconds: Double { endAt.timeIntervalSince(startAt) }

    public init(id: UUID = UUID(), activityID: UUID, sportType: SportType,
                startAt: Date, endAt: Date, distanceMeters: Double? = nil) {
        self.id = id
        self.activityID = activityID
        self.sportType = sportType
        self.startAt = startAt
        self.endAt = endAt
        self.distanceMeters = distanceMeters
    }
}

public enum AssignmentOrigin: String, Codable, Sendable {
    case manual, confirmedProposal, rule, preset
    /// Automatisch, weil es in der Kategorie genau einen verfügbaren Gegenstand gab (Annahme P-09).
    case soleCandidate
}

/// Direkte Zuordnung. `segmentID == nil` = Aktivitätsebene.
public struct ActivityGearAssignment: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var activityID: UUID
    public var segmentID: UUID?
    public var gearID: UUID
    public var origin: AssignmentOrigin
    public var createdAt: Date

    public init(id: UUID = UUID(), activityID: UUID, segmentID: UUID? = nil, gearID: UUID,
                origin: AssignmentOrigin = .manual, createdAt: Date = Date(timeIntervalSince1970: 0)) {
        self.id = id
        self.activityID = activityID
        self.segmentID = segmentID
        self.gearID = gearID
        self.origin = origin
        self.createdAt = createdAt
    }
}

/// Ereignistypen aus SPEC 8.1.
public enum MaintenanceKind: String, Codable, Sendable, CaseIterable {
    case cleaned, lubricated, inspected, wearMeasured
    case partInstalled, partRemoved, partReplaced
    case repaired, custom
}

public struct MaintenanceEvent: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var gearID: UUID
    public var kind: MaintenanceKind
    public var performedAt: Date
    public var measurement: Double?
    public var costMinor: Int?
    public var notes: String?

    public init(id: UUID = UUID(), gearID: UUID, kind: MaintenanceKind, performedAt: Date,
                measurement: Double? = nil, costMinor: Int? = nil, notes: String? = nil) {
        self.id = id
        self.gearID = gearID
        self.kind = kind
        self.performedAt = performedAt
        self.measurement = measurement
        self.costMinor = costMinor
        self.notes = notes
    }
}
