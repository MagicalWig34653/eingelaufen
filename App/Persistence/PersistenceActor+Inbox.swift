import Foundation
import GearCore
import SwiftData

// M4: Posteingang, Korrektur aus dem Verlauf, Presets und Regeln. Rechenlogik liegt im Kern (`InboxResolver`,
// `AssignmentCorrection`, `PresetPlanner`, `RuleManager`); hier wird nur der Unterschied zwischen altem und neuem
// Bestand in **einem** Commit geschrieben, das Ledger der betroffenen Aktivität neu gebaut und die Outbox gefüllt (A-03, A-04).

extension PersistenceActor {

    // MARK: Posteingang

    func resolvePending(_ id: UUID, _ action: InboxAction, remember: Bool, now: Date) throws -> CommandOutcome {
        // ponytail: lädt den ganzen Bestand je Tap; erst eingrenzen, wenn die M9-Messung es verlangt (wie beim Import).
        let before = try dataset()
        guard let resolution = InboxResolver.resolve(id, action: action, remember: remember, in: before, now: now) else {
            throw PersistenceError.pendingNotFound
        }
        let activityID = resolution.pending.activityID
        // Wiederholte Aktion, veralteter Vorschlag, unbekannte Auswahl: nichts schreiben, keine Seiteneffekte (I-09, T-10).
        guard resolution.result == .applied else { return CommandOutcome(activityID: activityID) }
        try write(InboxResolver.apply(resolution, to: before), replacing: before, activities: [activityID], pendings: [id], now: now)
        return CommandOutcome(activityID: activityID)
    }

    /// Korrektur aus dem Verlauf. Ein offener Posteingangs-Eintrag der Aktivität wird dabei mit erledigt, damit nichts
    /// doppelt zählt und nichts offen bleibt.
    func setActivityGear(_ activityID: UUID, _ gear: [UUID], now: Date) throws -> CommandOutcome {
        let before = try dataset()
        guard let activity = before.activities.first(where: { $0.id == activityID }), activity.deletedAt == nil else {
            throw PersistenceError.activityNotFound
        }
        let known = Set(before.gear.map(\.id))
        if let missing = gear.first(where: { !known.contains($0) }) { throw PersistenceError.gearNotFound(missing) }

        var after = before
        var touched: [UUID] = []
        if let open = before.pendings.first(where: { $0.activityID == activityID && !$0.state.isFinal }) {
            let action: InboxAction = gear.isEmpty ? .dismiss : .choose(gear: gear)
            if let resolution = InboxResolver.resolve(open.id, action: action, remember: false, in: before, now: now) {
                after = InboxResolver.apply(resolution, to: before)
                if resolution.result == .applied { touched.append(open.id) }
            }
        }
        let changes = AssignmentCorrection.setAssignments(activityID: activityID, gear: gear,
                                                          current: after.assignments, now: now)
        for change in changes {
            switch change {
            case .upsertAssignment(let a): after.assignments.append(a)
            case .removeAssignment(let id): after.assignments.removeAll { $0.id == id }
            default: break
            }
        }
        guard after != before else { return CommandOutcome(activityID: activityID) }
        try write(after, replacing: before, activities: [activityID], pendings: touched, now: now)
        return CommandOutcome(activityID: activityID)
    }

    // MARK: Presets (SPEC 4.1)

    func createPreset(_ name: String, _ sports: [SportType], _ members: [UUID], now: Date) throws -> CommandOutcome {
        let before = try dataset()
        let preset: GearPreset
        do { preset = try PresetPlanner.create(name: name, sportTypes: sports, members: members, in: before) }
        catch let error as PresetError { throw PersistenceError.preset(error) }
        var after = before
        after.presets.append(preset)
        try writeConfiguration(after, replacing: before, subjects: [preset.id], now: now)
        return CommandOutcome()
    }

    func removePreset(_ id: UUID, now: Date) throws -> CommandOutcome {
        let before = try dataset()
        guard before.presets.contains(where: { $0.id == id }) else { throw PersistenceError.preset(.presetNotFound(id)) }
        try writeConfiguration(PresetPlanner.remove(id, from: before), replacing: before, subjects: [id], now: now)
        return CommandOutcome()
    }

    func setDefaultPreset(_ sport: SportType, _ presetID: UUID?, now: Date) throws -> CommandOutcome {
        let before = try dataset()
        let profile: SportProfile
        do { profile = try PresetPlanner.setDefault(presetID, for: sport, in: before) }
        catch let error as PresetError { throw PersistenceError.preset(error) }
        var after = before
        if let i = after.sportProfiles.firstIndex(where: { $0.id == profile.id }) { after.sportProfiles[i] = profile } else { after.sportProfiles.append(profile) }
        try writeConfiguration(after, replacing: before, subjects: [profile.id], now: now)
        return CommandOutcome()
    }

    // MARK: Regeln (SPEC 6.3)

    func setRuleEnabled(_ id: UUID, _ enabled: Bool, now: Date) throws -> CommandOutcome {
        let before = try dataset()
        let after: GearDataset
        do { after = try RuleManager.setEnabled(id, enabled, in: before) }
        catch RuleError.notFound { throw PersistenceError.ruleNotFound(id) }
        try writeConfiguration(after, replacing: before, subjects: [id], now: now)
        return CommandOutcome()
    }

    func removeAssignmentRule(_ id: UUID, now: Date) throws -> CommandOutcome {
        let before = try dataset()
        let after: GearDataset
        do { after = try RuleManager.remove(id, from: before) }
        catch RuleError.notFound { throw PersistenceError.ruleNotFound(id) }
        try writeConfiguration(after, replacing: before, subjects: [id], now: now)
        return CommandOutcome()
    }

    // MARK: Schreiben

    /// Eintrag, Zuordnungen und Regel in einem Commit; danach Ledger der Aktivität und Outbox.
    private func write(_ after: GearDataset, replacing before: GearDataset, activities: [UUID], pendings: [UUID], now: Date) throws {
        try persist(after.pendings, was: before.pendings, id: \PendingEntity.id,
                    insert: PendingEntity.init, update: { $0.update(from: $1) })
        try persist(after.assignments, was: before.assignments, id: \AssignmentEntity.id,
                    insert: AssignmentEntity.init, update: { _, _ in })   // unveränderlich: nur neu oder weg
        try persist(after.assignmentRules, was: before.assignmentRules, id: \AssignmentRuleEntity.id,
                    insert: AssignmentRuleEntity.init, update: { $0.enabled = $1.enabled })
        let affectedGear = try rebuildLedger(for: Set(activities), now: now)
        try enqueue(.activityChanged, activities + affectedGear.sorted { $0.uuidString < $1.uuidString }, now: now)
        if !pendings.isEmpty { try enqueue(.pendingChanged, pendings, now: now) }
        if after.assignmentRules != before.assignmentRules { try enqueue(.rulesChanged, after.assignmentRules.map(\.id), now: now) }
    }

    private func writeConfiguration(_ after: GearDataset, replacing before: GearDataset, subjects: [UUID], now: Date) throws {
        try persist(after.presets, was: before.presets, id: \GearPresetEntity.id, insert: GearPresetEntity.init,
                    update: { row, p in row.name = p.name; row.sportTypeRaws = p.sportTypes.map(\.rawValue)
                              row.memberGearIDs = p.memberGearIDs; row.isEnabled = p.isEnabled })
        try persist(after.sportProfiles, was: before.sportProfiles, id: \SportProfileEntity.id, insert: SportProfileEntity.init,
                    update: { row, s in row.enabled = s.enabled; row.defaultPresetID = s.defaultPresetID
                              row.notificationLevelRaw = s.notificationLevel.rawValue })
        try persist(after.assignmentRules, was: before.assignmentRules, id: \AssignmentRuleEntity.id,
                    insert: AssignmentRuleEntity.init, update: { $0.enabled = $1.enabled })
        try enqueue(.rulesChanged, subjects, now: now)
    }
}
