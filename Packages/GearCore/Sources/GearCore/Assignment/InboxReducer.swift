import Foundation

// Zustandsmaschine des Posteingangs (SPEC 7.1, ARCHITEKTUR 6.2, I-09).
// Der persistente Eintrag ist die Wahrheit; Notification und Live Activity zeigen nur Zustand an und tragen
// `(pendingID, proposalRevision)`. Der Reducer ist rein: der PersistenceActor lädt den Eintrag neu, reduziert und
// schreibt Eintrag + Zuordnungen in einem Commit (A-03).

public enum InboxAction: Hashable, Sendable {
    /// Neuer oder geänderter Vorschlag (Engine, neues Wissen). Erhöht `proposalRevision`.
    case propose(gear: [UUID], alternatives: [[UUID]], reason: AssignmentReason, confidence: Confidence)
    /// „Vorschlag übernehmen“. `proposalRevision` stammt aus der angezeigten Notification/Live Activity.
    case confirm(proposalRevision: Int)
    /// „Andere auswählen“ bzw. manuelle Auswahl, auch mehrere Gegenstände auf einmal.
    case choose(gear: [UUID])
    /// „Nicht zuordnen“: bewusst ohne Ausrüstung.
    case dismiss
    /// „Später“: bleibt im Posteingang.
    case later
    /// Training gelöscht oder zusammengeführt.
    case markObsolete
    /// Benachrichtigung wurde zugestellt (nur Zeitstempel).
    case notified
}

public enum InboxNoOp: Hashable, Sendable {
    case alreadyFinal(PendingState)
    case staleRevision
    case invalidTransition
    case emptySelection
    /// Auswahl enthält einen Gegenstand, den es nicht gibt (M4).
    case unknownGear
}

public enum InboxResult: Hashable, Sendable {
    case applied
    case noOp(InboxNoOp)
}

public struct InboxOutcome: Sendable, Equatable {
    public var pending: PendingAssignment
    /// Neu zu schreibende Zuordnungen (leer bei `noOp`, `dismiss`, `later` …).
    public var assignments: [ActivityGearAssignment]
    public var result: InboxResult
}

public enum InboxReducer {
    public static func reduce(_ pending: PendingAssignment, _ action: InboxAction, now: Date,
                              makeID: () -> UUID = UUID.init) -> InboxOutcome {
        func noOp(_ why: InboxNoOp) -> InboxOutcome { InboxOutcome(pending: pending, assignments: [], result: .noOp(why)) }
        func applied(_ p: PendingAssignment, _ a: [ActivityGearAssignment] = []) -> InboxOutcome {
            InboxOutcome(pending: p, assignments: a, result: .applied)
        }

        // Endzustände sind gegen jede erneute Aktion idempotent (I-09, T-10).
        if pending.state.isFinal { return noOp(.alreadyFinal(pending.state)) }

        var next = pending
        switch action {
        case let .propose(gear, alternatives, reason, confidence):
            let unique = dedup(gear)
            guard !unique.isEmpty else { return noOp(.emptySelection) }
            next.state = .suggested
            next.proposedGearIDs = unique
            next.alternatives = alternatives
            next.reason = reason
            next.confidence = confidence
            next.proposalRevision += 1
            return applied(next)

        case let .confirm(revision):
            guard next.state == .suggested || next.state == .ignored, !next.proposedGearIDs.isEmpty else {
                return noOp(.invalidTransition)
            }
            guard revision == next.proposalRevision else { return noOp(.staleRevision) }
            next.state = .resolved
            next.resolution = .confirmedProposal
            return applied(next, assignments(for: next.proposedGearIDs, pending: next, origin: .confirmedProposal, now: now, makeID))

        case let .choose(gear):
            let unique = dedup(gear)
            guard !unique.isEmpty else { return noOp(.emptySelection) }
            next.state = .resolved
            next.resolution = .chosen
            next.proposalRevision += 1
            return applied(next, assignments(for: unique, pending: next, origin: .manual, now: now, makeID))

        case .dismiss:
            next.state = .dismissed
            next.resolution = .dismissed
            next.proposalRevision += 1
            return applied(next)

        case .later:
            guard next.state != .ignored else { return noOp(.invalidTransition) }
            next.state = .ignored
            return applied(next)

        case .markObsolete:
            next.state = .obsolete
            next.resolution = .obsolete
            next.proposalRevision += 1
            return applied(next)

        case .notified:
            next.lastPromptAt = now
            return applied(next)
        }
    }

    private static func dedup(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func assignments(for gear: [UUID], pending: PendingAssignment, origin: AssignmentOrigin,
                                    now: Date, _ makeID: () -> UUID) -> [ActivityGearAssignment] {
        gear.map { ActivityGearAssignment(id: makeID(), activityID: pending.activityID, gearID: $0, origin: origin, createdAt: now) }
    }
}
