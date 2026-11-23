import Foundation

/// Identität eines Ledger-Eintrags: höchstens einer je (Aktivität, Segment, Gegenstand) – Invariante I-04.
public struct LedgerKey: Hashable, Comparable, Codable, Sendable {
    public var activityID: UUID
    public var segmentID: UUID?
    public var gearID: UUID

    public init(activityID: UUID, segmentID: UUID?, gearID: UUID) {
        self.activityID = activityID
        self.segmentID = segmentID
        self.gearID = gearID
    }

    public static func < (a: LedgerKey, b: LedgerKey) -> Bool {
        (a.activityID.uuidString, a.segmentID?.uuidString ?? "", a.gearID.uuidString)
            < (b.activityID.uuidString, b.segmentID?.uuidString ?? "", b.gearID.uuidString)
    }
}

/// Abgeleiteter Nutzungsbeitrag (SPEC 4.1). Nie Quelle der Wahrheit, jederzeit neu erzeugbar (A-02).
public struct UsageLedgerEntry: Hashable, Codable, Sendable {
    public var key: LedgerKey
    /// Zeitpunkt, der für „seit Einbau/Wartung“ zählt: Beginn der Aktivität bzw. des Segments (P-01).
    public var occurredAt: Date
    /// `nil` = nicht gemessen. Wird nie aus der Dauer geschätzt oder auf Segmente verteilt.
    public var distanceMeters: Double?
    public var durationSeconds: Double?
    public var uses: Int
    public var derivationVersion: Int

    public var activityID: UUID { key.activityID }
    public var segmentID: UUID? { key.segmentID }
    public var gearID: UUID { key.gearID }

    /// Öffentlich, damit die App ein gespeichertes Ledger wieder in Kernwerte überführen kann (Mapper, I-10-Vergleich).
    public init(key: LedgerKey, occurredAt: Date, distanceMeters: Double?, durationSeconds: Double?,
                uses: Int, derivationVersion: Int) {
        self.key = key
        self.occurredAt = occurredAt
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.uses = uses
        self.derivationVersion = derivationVersion
    }
}

public enum LedgerIssue: Hashable, Sendable {
    /// Derselbe Gegenstand auf Aktivitäts- und Segmentebene (I-05): Aktivitätsebene gewinnt, Segmentbeitrag entfällt.
    case segmentDuplicatesActivityLevel(activityID: UUID, segmentID: UUID, gearID: UUID)
    case assignmentForUnknownActivity(assignmentID: UUID)
    case assignmentForUnknownSegment(assignmentID: UUID)
}

/// Alle Wahrheitsdaten, aus denen das Ledger folgt (ARCHITEKTUR 4).
public struct LedgerInput: Sendable, Equatable {
    public var activities: [ActivityRecord]
    public var segments: [ActivitySegment]
    public var assignments: [ActivityGearAssignment]
    public var installations: [Installation]

    public init(activities: [ActivityRecord] = [], segments: [ActivitySegment] = [],
                assignments: [ActivityGearAssignment] = [], installations: [Installation] = []) {
        self.activities = activities
        self.segments = segments
        self.assignments = assignments
        self.installations = installations
    }
}

public struct LedgerResult: Sendable, Equatable {
    /// Nach `LedgerKey` sortiert (deterministisch).
    public var entries: [UsageLedgerEntry]
    public var issues: [LedgerIssue]
}

public enum LedgerBuilder {
    public static let derivationVersion = 1

    /// Baut das Ledger deterministisch aus den Wahrheitsdaten. Mit `only` werden nur diese Aktivitäten berechnet.
    ///
    /// Regeln (ARCHITEKTUR 4, SPEC 4.3/5.2):
    /// 1. Direkt zugeordnete Gegenstände + alle zum Zeitpunkt `startAt` (Aktivität bzw. Segment) montierten Nachfahren.
    /// 2. Je (Aktivität, Segment, Gegenstand) höchstens ein Eintrag (I-04).
    /// 3. Aktivitätsebene gewinnt gegen dieselbe Segmentzuordnung (I-05); der Konflikt wird gemeldet.
    /// 4. Distanz nur, wenn gemessen: Aktivitätsdistanz bzw. Segmentdistanz, sonst `nil` (T-08, T-09).
    /// 5. Gelöschte Aktivitäten haben keine Einträge (I-08).
    public static func build(_ input: LedgerInput, only activityIDs: Set<UUID>? = nil) -> LedgerResult {
        let graph = InstallationGraph(input.installations)
        let activities = Dictionary(input.activities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let segments = Dictionary(input.segments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let assignmentsByActivity = Dictionary(grouping: input.assignments, by: \.activityID)

        var entries: [LedgerKey: UsageLedgerEntry] = [:]
        var issues: [LedgerIssue] = []

        func wanted(_ activityID: UUID) -> Bool { activityIDs?.contains(activityID) ?? true }
        func byID<T: Identifiable>(_ items: [T]) -> [T] where T.ID == UUID {
            items.sorted { $0.id.uuidString < $1.id.uuidString }
        }
        func expand(_ direct: Set<UUID>, at t: Date) -> Set<UUID> {
            var all = direct
            for gear in direct { all.formUnion(graph.descendants(of: gear, at: t)) }
            return all
        }

        // Zuordnungen ohne passende Aktivität bzw. mit fremdem Segment.
        for activityID in assignmentsByActivity.keys.sorted(by: { $0.uuidString < $1.uuidString }) where wanted(activityID) {
            for assignment in byID(assignmentsByActivity[activityID] ?? []) {
                if activities[activityID] == nil {
                    issues.append(.assignmentForUnknownActivity(assignmentID: assignment.id))
                } else if let segmentID = assignment.segmentID, segments[segmentID]?.activityID != activityID {
                    issues.append(.assignmentForUnknownSegment(assignmentID: assignment.id))
                }
            }
        }

        for activity in byID(Array(activities.values)) where activity.deletedAt == nil && wanted(activity.id) {
            let assignments = assignmentsByActivity[activity.id] ?? []

            let activityLevel = expand(Set(assignments.filter { $0.segmentID == nil }.map(\.gearID)),
                                       at: activity.startAt)
            for gear in activityLevel {
                let key = LedgerKey(activityID: activity.id, segmentID: nil, gearID: gear)
                entries[key] = UsageLedgerEntry(
                    key: key, occurredAt: activity.startAt, distanceMeters: activity.distanceMeters,
                    durationSeconds: activity.durationSeconds, uses: 1, derivationVersion: derivationVersion)
            }

            let ownSegments = byID(input.segments.filter { $0.activityID == activity.id })
            for segment in ownSegments {
                let direct = Set(assignments.filter { $0.segmentID == segment.id }.map(\.gearID))
                for gear in expand(direct, at: segment.startAt).sorted(by: { $0.uuidString < $1.uuidString }) {
                    if activityLevel.contains(gear) {
                        issues.append(.segmentDuplicatesActivityLevel(
                            activityID: activity.id, segmentID: segment.id, gearID: gear))
                        continue
                    }
                    let key = LedgerKey(activityID: activity.id, segmentID: segment.id, gearID: gear)
                    entries[key] = UsageLedgerEntry(
                        key: key, occurredAt: segment.startAt, distanceMeters: segment.distanceMeters,
                        durationSeconds: segment.durationSeconds, uses: 1, derivationVersion: derivationVersion)
                }
            }
        }

        return LedgerResult(entries: entries.values.sorted { $0.key < $1.key }, issues: issues)
    }
}
