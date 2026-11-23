import Foundation

// Rückwirkende Korrektur und Regel-Lernen (SPEC 6.3). Rein: liefert Änderungen, die der Actor in einem Commit
// schreibt und das Ledger inkrementell nachführt (LedgerProjection, I-10).

public enum AssignmentCorrection {

    /// Setzt die Ausrüstung einer Aktivität (Aktivitätsebene) auf `gear`. Nur Unterschiede werden zu Änderungen;
    /// Segmentzuordnungen bleiben unberührt. Verlauf › Aktivität › Ausrüstung nutzt das für jede Korrektur.
    public static func setAssignments(activityID: UUID, gear: [UUID], current: [ActivityGearAssignment],
                                      origin: AssignmentOrigin = .manual, now: Date,
                                      makeID: () -> UUID = UUID.init) -> [LedgerChange] {
        let direct = current.filter { $0.activityID == activityID && $0.segmentID == nil }
        let wanted = unique(gear)
        var changes: [LedgerChange] = []
        var covered = Set<UUID>()
        for a in direct.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            if wanted.contains(a.gearID), covered.insert(a.gearID).inserted { continue }
            changes.append(.removeAssignment(a.id))               // nicht mehr gewollt oder doppelt vorhanden
        }
        for g in wanted where !covered.contains(g) {
            changes.append(.upsertAssignment(ActivityGearAssignment(id: makeID(), activityID: activityID, gearID: g,
                                                                    origin: origin, createdAt: now)))
        }
        return changes
    }

    /// „Falsch“: ersetzt `from` durch `to`, alle übrigen Zuordnungen der Aktivität bleiben.
    public static func reassign(activityID: UUID, from: UUID, to: UUID, current: [ActivityGearAssignment],
                                now: Date, makeID: () -> UUID = UUID.init) -> [LedgerChange] {
        let direct = current.filter { $0.activityID == activityID && $0.segmentID == nil }
        var gear = direct.map(\.gearID).map { $0 == from ? to : $0 }
        if !direct.contains(where: { $0.gearID == from }) { gear.append(to) }
        return setAssignments(activityID: activityID, gear: gear, current: current, now: now, makeID: makeID)
    }

    private static func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}

public enum RuleLearning {

    /// „Für ähnliche Aktivitäten merken“ (SPEC 6.3): legt eine nachvollziehbare Regel an. `nil`, wenn es nichts zu
    /// merken gibt oder eine gleiche aktive Regel schon existiert. Die Regel wirkt nur auf *neue* Importe
    /// (der Reconciler entscheidet nur für neu angelegte Aktivitäten), nie rückwirkend auf abgeschlossene.
    public static func rememberRule(for activity: ActivityRecord, gear: [UUID], existing: [AssignmentRule],
                                    now: Date, id: UUID = UUID()) -> AssignmentRule? {
        var seen = Set<UUID>()
        let members = gear.filter { seen.insert($0).inserted }
        guard !members.isEmpty else { return nil }
        // Indoor nur, wenn belegt (SPEC 3.3); Wochentag/Ort werden nie stillschweigend geraten.
        let conditions = RuleConditions(isIndoor: activity.isIndoor)
        let duplicate = existing.contains {
            $0.enabled && $0.sportType == activity.sportType && $0.conditions == conditions && Set($0.gearIDs) == Set(members)
        }
        if duplicate { return nil }
        return AssignmentRule(id: id, sportType: activity.sportType, kind: .remembered, conditions: conditions,
                              gearIDs: members, priority: 0, enabled: true, createdAt: now)
    }
}

public enum AssignmentHistory {
    /// Bestätigte frühere Zuordnungen für die Gewohnheit der Engine: nur ausdrückliche Nutzerentscheidungen
    /// (manuell, bestätigter Vorschlag), nie Regel-/Preset-Automatik (kein Rückkopplungseffekt).
    public static func confirmed(from dataset: GearDataset) -> [ConfirmedAssignment] {
        let activities = Dictionary(dataset.activities.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let confirmed = dataset.assignments.filter { ($0.origin == .manual || $0.origin == .confirmedProposal) && $0.segmentID == nil }
        return Dictionary(grouping: confirmed, by: \.activityID).compactMap { activityID, items in
            guard let activity = activities[activityID], activity.deletedAt == nil else { return nil }
            let at = items.map(\.createdAt).max() ?? activity.startAt
            return ConfirmedAssignment(sportType: activity.sportType,
                                       gearIDs: items.map(\.gearID).sorted { $0.uuidString < $1.uuidString }, confirmedAt: at)
        }.sorted { ($0.confirmedAt, $0.gearIDs.first?.uuidString ?? "") < ($1.confirmedAt, $1.gearIDs.first?.uuidString ?? "") }
    }
}
