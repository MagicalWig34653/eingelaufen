import Foundation

// M4: Posteingang auf Datensatz-Ebene (SPEC 6.3, 7.1, S05). Rein: lädt den Eintrag aus dem Bestand, reduziert ihn
// (`InboxReducer`) und liefert Eintrag, neue Zuordnungen und – nur auf Wunsch – die gemerkte Regel. Der
// PersistenceActor schreibt alles in einem Commit (A-03) und baut danach das Ledger der Aktivität neu.

public struct InboxResolution: Sendable, Equatable {
    public var pending: PendingAssignment
    public var assignments: [ActivityGearAssignment]
    /// Nur nach erfolgreichem Bestätigen/Wählen mit „merken“, nie bei Dismiss/Später/No-op/Duplikat.
    public var rule: AssignmentRule?
    public var result: InboxResult
}

public struct InboxEntry: Sendable, Equatable, Identifiable {
    public var pending: PendingAssignment
    public var activity: ActivityRecord
    public var id: UUID { pending.id }
}

public enum InboxResolver {

    /// `nil`, wenn es den Eintrag nicht gibt (z. B. veraltete Notification nach Wiederherstellung).
    public static func resolve(_ pendingID: UUID, action: InboxAction, remember: Bool, in dataset: GearDataset, now: Date,
                               makeID: () -> UUID = UUID.init) -> InboxResolution? {
        guard let pending = dataset.pendings.first(where: { $0.id == pendingID }) else { return nil }
        func outcome(_ o: InboxOutcome, rule: AssignmentRule? = nil) -> InboxResolution {
            InboxResolution(pending: o.pending, assignments: o.assignments, rule: rule, result: o.result)
        }

        // Training gelöscht oder unbekannt: nie buchen, der Eintrag wird hinfällig (SPEC 7.1 `obsolete`).
        let activity = dataset.activities.first { $0.id == pending.activityID }
        if activity == nil || activity?.deletedAt != nil {
            return outcome(InboxReducer.reduce(pending, .markObsolete, now: now, makeID: makeID))
        }

        // Auswahl nur aus vorhandenen Gegenständen (Schutz vor veralteten Dialogen).
        if case let .choose(gear) = action {
            let known = Set(dataset.gear.map(\.id))
            if gear.contains(where: { !known.contains($0) }) {
                return InboxResolution(pending: pending, assignments: [], rule: nil, result: .noOp(.unknownGear))
            }
        }

        let reduced = InboxReducer.reduce(pending, action, now: now, makeID: makeID)
        guard remember, reduced.result == .applied, !reduced.assignments.isEmpty, let activity else {
            return outcome(reduced)
        }
        let rule = RuleLearning.rememberRule(for: activity, gear: reduced.assignments.map(\.gearID),
                                             existing: dataset.assignmentRules, now: now, id: makeID())
        return outcome(reduced, rule: rule)
    }

    /// Schreibt das Ergebnis in den Bestand. Bei `noOp` ändert sich nur, was der Reducer ausdrücklich zurückgibt (nichts).
    public static func apply(_ resolution: InboxResolution, to dataset: GearDataset) -> GearDataset {
        guard resolution.result == .applied else { return dataset }
        var next = dataset
        if let i = next.pendings.firstIndex(where: { $0.id == resolution.pending.id }) { next.pendings[i] = resolution.pending }
        next.assignments += resolution.assignments
        if let rule = resolution.rule { next.assignmentRules.append(rule) }
        return next
    }
}

public enum InboxQuery {
    /// Offene Einträge (unresolved, suggested, ignored) mit lebender Aktivität, neueste Aktivität zuerst (S05).
    public static func open(in dataset: GearDataset) -> [InboxEntry] {
        let activities = Dictionary(dataset.activities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return dataset.pendings.compactMap { p -> InboxEntry? in
            guard !p.state.isFinal, let a = activities[p.activityID], a.deletedAt == nil else { return nil }
            return InboxEntry(pending: p, activity: a)
        }.sorted {
            $0.activity.startAt != $1.activity.startAt ? $0.activity.startAt > $1.activity.startAt
                                                       : $0.pending.id.uuidString < $1.pending.id.uuidString
        }
    }

    public static func openCount(in dataset: GearDataset) -> Int { open(in: dataset).count }
}
