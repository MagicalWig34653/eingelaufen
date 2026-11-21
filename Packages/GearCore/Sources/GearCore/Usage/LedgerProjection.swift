import Foundation

/// Fachliche Änderung an den Wahrheitsdaten (ARCHITEKTUR A-03: Änderungen laufen als Befehle).
public enum LedgerChange: Sendable, Equatable {
    case upsertActivity(ActivityRecord)
    case removeActivity(UUID)
    case upsertSegment(ActivitySegment)
    case removeSegment(UUID)
    case upsertAssignment(ActivityGearAssignment)
    case removeAssignment(UUID)
    case upsertInstallation(Installation)
    case removeInstallation(UUID)
}

/// Inkrementell gepflegtes Ledger. Muss nach jeder Änderung exakt dem vollständigen Neuaufbau entsprechen (I-10).
///
/// Betroffen von einer Änderung sind nur:
/// - Aktivität/Segment/Zuordnung: die zugehörige(n) Aktivität(en), jeweils alter und neuer Stand;
/// - Montage: Aktivitäten, deren Aktivitäts- oder Segmentbeginn im Intervall der alten oder neuen Montage liegt
///   (eine Montage wirkt nur innerhalb ihres Intervalls, A-07).
public struct LedgerProjection: Sendable {
    public private(set) var input: LedgerInput
    public private(set) var entries: [UsageLedgerEntry]
    /// Anzahl der Aktivitäten, die die letzte Änderung neu berechnet hat (Nachweis, dass nicht alles neu gebaut wird).
    public private(set) var lastRecomputedActivityCount = 0

    public init(input: LedgerInput = LedgerInput()) {
        self.input = input
        self.entries = LedgerBuilder.build(input).entries
    }

    /// Sicherheitsnetz (ARCHITEKTUR 4 `rebuildAll()`): verwirft den Zwischenstand und baut aus den Wahrheitsdaten neu.
    public mutating func rebuildAll() {
        entries = LedgerBuilder.build(input).entries
        lastRecomputedActivityCount = input.activities.count
    }

    public mutating func apply(_ change: LedgerChange) {
        var affected = Set<UUID>()

        switch change {
        case let .upsertActivity(new):
            affected.insert(new.id)
            Self.upsert(new, in: &input.activities)
        case let .removeActivity(activityID):
            affected.insert(activityID)
            input.activities.removeAll { $0.id == activityID }
        case let .upsertSegment(new):
            affected.insert(new.activityID)
            if let old = input.segments.first(where: { $0.id == new.id }) { affected.insert(old.activityID) }
            Self.upsert(new, in: &input.segments)
        case let .removeSegment(segmentID):
            if let old = input.segments.first(where: { $0.id == segmentID }) { affected.insert(old.activityID) }
            input.segments.removeAll { $0.id == segmentID }
        case let .upsertAssignment(new):
            affected.insert(new.activityID)
            if let old = input.assignments.first(where: { $0.id == new.id }) { affected.insert(old.activityID) }
            Self.upsert(new, in: &input.assignments)
        case let .removeAssignment(assignmentID):
            if let old = input.assignments.first(where: { $0.id == assignmentID }) { affected.insert(old.activityID) }
            input.assignments.removeAll { $0.id == assignmentID }
        case let .upsertInstallation(new):
            if let old = input.installations.first(where: { $0.id == new.id }) {
                affected.formUnion(activitiesTouching(old))
            }
            affected.formUnion(activitiesTouching(new))
            Self.upsert(new, in: &input.installations)
        case let .removeInstallation(installationID):
            if let old = input.installations.first(where: { $0.id == installationID }) {
                affected.formUnion(activitiesTouching(old))
            }
            input.installations.removeAll { $0.id == installationID }
        }

        entries.removeAll { affected.contains($0.activityID) }
        entries += LedgerBuilder.build(input, only: affected).entries
        entries.sort { $0.key < $1.key }
        lastRecomputedActivityCount = affected.count
    }

    /// Konsistenzprobleme der Eingabedaten (aufwendig, nur für Diagnose).
    public var issues: [LedgerIssue] { LedgerBuilder.build(input).issues }

    // MARK: Intern

    private func activitiesTouching(_ installation: Installation) -> Set<UUID> {
        func inWindow(_ t: Date) -> Bool { installation.isActive(at: t) }
        var result = Set<UUID>()
        for activity in input.activities where inWindow(activity.startAt) { result.insert(activity.id) }
        for segment in input.segments where inWindow(segment.startAt) { result.insert(segment.activityID) }
        return result
    }

    private static func upsert<T: Identifiable>(_ item: T, in list: inout [T]) where T.ID == UUID {
        if let index = list.firstIndex(where: { $0.id == item.id }) {
            list[index] = item
        } else {
            list.append(item)
        }
    }
}
