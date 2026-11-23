import Foundation

// Wahrheits- und Ablaufentitäten für Zuordnung, Posteingang und Wartungsregeln (SPEC 5.1, ARCHITEKTUR 3.1).
// Beziehungen laufen über IDs (A-04), keine Kaskaden.

/// Lebenszyklus-Historie (P-04): Spec 6.2 verlangt den Status *im Aktivitätszeitraum*, nicht nur den heutigen.
public struct GearStatusChange: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var gearID: UUID
    public var status: GearStatus
    public var effectiveAt: Date

    public init(id: UUID = UUID(), gearID: UUID, status: GearStatus, effectiveAt: Date) {
        self.id = id
        self.gearID = gearID
        self.status = status
        self.effectiveAt = effectiveAt
    }
}

/// Ausrüstungsset (SPEC 4.1): Gruppierung häufig gemeinsam genutzter Gegenstände, **keine** physische Montage.
public struct GearPreset: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var sportTypes: [SportType]
    public var memberGearIDs: [UUID]
    public var isEnabled: Bool

    public init(id: UUID = UUID(), name: String, sportTypes: [SportType], memberGearIDs: [UUID], isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.sportTypes = sportTypes
        self.memberGearIDs = memberGearIDs
        self.isEnabled = isEnabled
    }
}

/// Benachrichtigungsstufen (SPEC 7.2). Wirkung gehört zur App; der Kern speichert nur die Wahl.
public enum NotificationLevel: String, Codable, Sendable, CaseIterable {
    case off, assignmentOnly, assignmentAndMaintenance
}

public struct SportProfile: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var sportType: SportType
    public var enabled: Bool
    public var defaultPresetID: UUID?
    public var notificationLevel: NotificationLevel

    public init(id: UUID = UUID(), sportType: SportType, enabled: Bool = true,
                defaultPresetID: UUID? = nil, notificationLevel: NotificationLevel = .assignmentOnly) {
        self.id = id
        self.sportType = sportType
        self.enabled = enabled
        self.defaultPresetID = defaultPresetID
        self.notificationLevel = notificationLevel
    }
}

public enum AssignmentRuleKind: String, Codable, Sendable {
    /// Vom Nutzer ausdrücklich festgelegte Standardausrüstung.
    case explicitDefault
    /// Aus „Für ähnliche Aktivitäten merken“ entstanden (SPEC 6.3); nachvollziehbar und abschaltbar.
    case remembered
}

/// Bedingungen einer Regel. Fehlende Bedingung = gilt immer. Keine Standortüberwachung (SPEC 6.2).
public struct RuleConditions: Hashable, Codable, Sendable {
    /// Greift nur, wenn die Aktivität `isIndoor` *belegt* hat und gleich ist (SPEC 3.3).
    public var isIndoor: Bool?
    /// `Calendar`-Wochentage 1…7, ausgewertet in der übergebenen Zeitzone (SPEC 10.4).
    public var weekdays: Set<Int>?

    public init(isIndoor: Bool? = nil, weekdays: Set<Int>? = nil) {
        self.isIndoor = isIndoor
        self.weekdays = weekdays
    }

    private enum CodingKeys: String, CodingKey { case isIndoor, weekdays }

    /// Mengen kodiert Swift in unbestimmter Reihenfolge; sortiert bleibt der Export (Backup) byte-stabil.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(isIndoor, forKey: .isIndoor)
        try c.encodeIfPresent(weekdays.map { $0.sorted() }, forKey: .weekdays)
    }
}

public struct AssignmentRule: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var sportType: SportType
    public var kind: AssignmentRuleKind
    public var conditions: RuleConditions
    public var gearIDs: [UUID]
    /// Höhere Zahl gewinnt. Gleichrangige, widersprüchliche Regeln führen zu einer Nachfrage, nie zu einer Wahl.
    public var priority: Int
    public var enabled: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), sportType: SportType, kind: AssignmentRuleKind = .explicitDefault,
                conditions: RuleConditions = RuleConditions(), gearIDs: [UUID], priority: Int = 0,
                enabled: Bool = true, createdAt: Date = Date(timeIntervalSince1970: 0)) {
        self.id = id
        self.sportType = sportType
        self.kind = kind
        self.conditions = conditions
        self.gearIDs = gearIDs
        self.priority = priority
        self.enabled = enabled
        self.createdAt = createdAt
    }
}

/// Konfidenz ohne Prozentzahl (SPEC 6.2, ohne ML).
public enum Confidence: String, Codable, Sendable, Comparable {
    case none, low, medium, high, explicit

    private var order: Int { [Confidence.none, .low, .medium, .high, .explicit].firstIndex(of: self)! }
    public static func < (a: Confidence, b: Confidence) -> Bool { a.order < b.order }
}

/// Begründung, erläuterbar in Posteingang und Benachrichtigung (SPEC 6.2 Schritt 5).
public enum AssignmentReason: Hashable, Codable, Sendable {
    case rule(UUID)
    case defaultPreset(UUID)
    case preset(UUID)
    case soleCandidate
    case history
    case multipleCandidates
    case noCandidates
    /// Teile der Regel/des Sets waren im Aktivitätszeitraum nicht verfügbar (T-12), Rest wird nur vorgeschlagen.
    case unavailableMembersDropped
    case replacementAmbiguous
    case conflictingRules
}

public enum PendingState: String, Codable, Sendable {
    case unresolved, suggested, resolved, dismissed, ignored, obsolete

    public var isFinal: Bool { self == .resolved || self == .dismissed || self == .obsolete }
}

public enum PendingResolution: String, Codable, Sendable {
    case none, confirmedProposal, chosen, dismissed, obsolete
}

/// Ausnahme-Posteingang (SPEC 7.1): Quelle der Wahrheit für offene Zuordnungen.
public struct PendingAssignment: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var activityID: UUID
    public var state: PendingState
    /// Empfohlene Auswahl (leer bei `unresolved`).
    public var proposedGearIDs: [UUID]
    public var alternatives: [[UUID]]
    /// Gleich plausible Kandidaten bei `unresolved`.
    public var candidateGearIDs: [UUID]
    public var reason: AssignmentReason?
    public var confidence: Confidence
    /// Jede Änderung am Vorschlag erhöht den Zähler; Notification/Live Activity tragen `(id, proposalRevision)`.
    public var proposalRevision: Int
    public var createdAt: Date
    public var lastPromptAt: Date?
    public var resolution: PendingResolution

    public init(id: UUID = UUID(), activityID: UUID, state: PendingState = .unresolved,
                proposedGearIDs: [UUID] = [], alternatives: [[UUID]] = [], candidateGearIDs: [UUID] = [],
                reason: AssignmentReason? = nil, confidence: Confidence = .none, proposalRevision: Int = 1,
                createdAt: Date = Date(timeIntervalSince1970: 0), lastPromptAt: Date? = nil,
                resolution: PendingResolution = .none) {
        self.id = id
        self.activityID = activityID
        self.state = state
        self.proposedGearIDs = proposedGearIDs
        self.alternatives = alternatives
        self.candidateGearIDs = candidateGearIDs
        self.reason = reason
        self.confidence = confidence
        self.proposalRevision = proposalRevision
        self.createdAt = createdAt
        self.lastPromptAt = lastPromptAt
        self.resolution = resolution
    }
}

/// Wartungsintervall je Gegenstand (SPEC 5.1). Auswertung folgt in M5 (`MaintenanceEvaluator`);
/// hier nur als Wahrheitsdatum, damit Backup (T-14) die Regeln erhält.
public struct MaintenanceRule: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var gearID: UUID
    public var kind: MaintenanceKind
    public var metric: UsageMetricKind
    /// Meter, Sekunden, Anzahl oder Tage je nach `metric` (A-08).
    public var intervalValue: Double
    public var warningLeadValue: Double?
    public var enabled: Bool

    public init(id: UUID = UUID(), gearID: UUID, kind: MaintenanceKind, metric: UsageMetricKind,
                intervalValue: Double, warningLeadValue: Double? = nil, enabled: Bool = true) {
        self.id = id
        self.gearID = gearID
        self.kind = kind
        self.metric = metric
        self.intervalValue = intervalValue
        self.warningLeadValue = warningLeadValue
        self.enabled = enabled
    }
}

/// Alle Wahrheits- und Ablaufdaten (ohne abgeleitetes Ledger). Gemeinsame Grundlage für Reconciler,
/// Backup und Konsistenzprüfung. `ImportCursor`/`AppSettings` gehören zur App (M2/M3), nicht in den Kern.
public struct GearDataset: Hashable, Codable, Sendable {
    public var gear: [GearItem] = []
    public var statusChanges: [GearStatusChange] = []
    public var installations: [Installation] = []
    public var presets: [GearPreset] = []
    public var sportProfiles: [SportProfile] = []
    public var activities: [ActivityRecord] = []
    public var segments: [ActivitySegment] = []
    public var assignments: [ActivityGearAssignment] = []
    public var maintenanceEvents: [MaintenanceEvent] = []
    public var maintenanceRules: [MaintenanceRule] = []
    public var assignmentRules: [AssignmentRule] = []
    public var pendings: [PendingAssignment] = []

    public init() {}

    public var ledgerInput: LedgerInput {
        LedgerInput(activities: activities, segments: segments, assignments: assignments, installations: installations)
    }
}
