import Foundation

// Löschen durch den Nutzer (SPEC 11): Ausrüstung und einzelne Aktivitäten entfernen, ohne Verweise ins Leere zu
// hinterlassen. Ergebnis ist ein gültiger Bestand (BackupValidator ohne Fehler); das Ledger baut der Aufrufer neu.
// „Alle App-Daten löschen“ ist der leere Bestand und gehört der App (Einstellungen, Anker, Fotos).

public enum DeletionError: Error, Equatable, Sendable {
    case gearNotFound(UUID)
    case activityNotFound(UUID)
}

public enum DataDeletion {

    /// Entfernt den Gegenstand mit seiner Historie: Status, Montagen (als Eltern- oder Kindteil), Zuordnungen,
    /// Wartung und Wartungsregeln. Montierte Teile bleiben als eigene Gegenstände. Aus Regeln, Sets und dem
    /// Posteingang verschwindet er als Mitglied; leere Regeln und Sets entfallen. Ändert sich ein offener
    /// Vorschlag, steigt dessen Revision (veraltete Mitteilungen buchen dann nicht mehr, T-10).
    public static func deleteGear(_ id: UUID, in dataset: GearDataset) throws -> GearDataset {
        guard dataset.gear.contains(where: { $0.id == id }) else { throw DeletionError.gearNotFound(id) }
        var d = dataset
        d.gear.removeAll { $0.id == id }
        d.statusChanges.removeAll { $0.gearID == id }
        d.installations.removeAll { $0.parentGearID == id || $0.childGearID == id }
        d.assignments.removeAll { $0.gearID == id }
        d.maintenanceEvents.removeAll { $0.gearID == id }
        d.maintenanceRules.removeAll { $0.gearID == id }

        for i in d.assignmentRules.indices { d.assignmentRules[i].gearIDs.removeAll { $0 == id } }
        d.assignmentRules.removeAll { $0.gearIDs.isEmpty }

        for i in d.presets.indices { d.presets[i].memberGearIDs.removeAll { $0 == id } }
        let emptyPresets = Set(d.presets.filter { $0.memberGearIDs.isEmpty }.map(\.id))
        d.presets.removeAll { emptyPresets.contains($0.id) }
        for i in d.sportProfiles.indices where d.sportProfiles[i].defaultPresetID.map(emptyPresets.contains) == true {
            d.sportProfiles[i].defaultPresetID = nil
        }

        d.pendings = d.pendings.map { without(id, in: $0) }
        return d
    }

    /// Manuelle Aktivitäten verschwinden vollständig. Importierte bleiben als Grabstein (`deletedAt`, I-08) mit
    /// ihrer Quell-ID und `removedByUser`, damit kein späterer Import sie zurückholt; ihre Zuordnungen entfallen, der
    /// Posteingang wird hinfällig.
    public static func deleteActivity(_ id: UUID, in dataset: GearDataset, now: Date) throws -> GearDataset {
        guard let index = dataset.activities.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw DeletionError.activityNotFound(id)
        }
        var d = dataset
        d.assignments.removeAll { $0.activityID == id }
        if d.activities[index].source == .manual {
            d.activities.remove(at: index)
            d.segments.removeAll { $0.activityID == id }
            d.pendings.removeAll { $0.activityID == id }
        } else {
            d.activities[index].deletedAt = now
            d.activities[index].removedByUser = true
            d.activities[index].revision += 1
            for i in d.pendings.indices where d.pendings[i].activityID == id && !d.pendings[i].state.isFinal {
                d.pendings[i].state = .obsolete
                d.pendings[i].resolution = .obsolete
                d.pendings[i].proposalRevision += 1
            }
        }
        return d
    }

    private static func without(_ id: UUID, in pending: PendingAssignment) -> PendingAssignment {
        var p = pending
        p.proposedGearIDs.removeAll { $0 == id }
        p.alternatives = p.alternatives.map { $0.filter { $0 != id } }.filter { !$0.isEmpty }
        p.candidateGearIDs.removeAll { $0 == id }
        guard p != pending, !p.state.isFinal else { return p }
        // Ohne Vorschlag fragt der Eintrag neu nach: übrige Alternativen werden gleichrangige Kandidaten.
        if p.state == .suggested, p.proposedGearIDs.isEmpty {
            var candidates: [UUID] = []
            for gear in p.candidateGearIDs + p.alternatives.flatMap({ $0 }) where !candidates.contains(gear) { candidates.append(gear) }
            p.state = .unresolved
            p.candidateGearIDs = candidates
            p.alternatives = []
        }
        p.proposalRevision += 1
        return p
    }
}
