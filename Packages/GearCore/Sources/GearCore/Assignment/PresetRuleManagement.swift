import Foundation

// M4: Presets (SPEC 4.1) und Zuordnungsregeln (SPEC 6.3) verwalten. Rein; der PersistenceActor schreibt das Ergebnis.
// Ein Preset ist eine Gruppierung, keine physische Montage und keine Nutzung (SPEC 4.1).

public enum PresetError: Error, Equatable {
    case emptyName, noMembers, noSportTypes
    case unknownGear(UUID)
    case presetNotFound(UUID)
    case presetDoesNotCover(SportType)
}

/// Angebot für den Zuordnungsdialog (S05: „einzelne Rollen/Preset anbieten“).
public struct PresetOffer: Sendable, Equatable {
    public var preset: GearPreset
    /// Zum Aktivitätszeitpunkt verfügbare Mitglieder, in Preset-Reihenfolge (T-12).
    public var availableGearIDs: [UUID]
    public var unavailableGearIDs: [UUID]
    public var isDefault: Bool
}

public enum PresetPlanner {

    public static func create(name: String, sportTypes: [SportType], members: [UUID], in dataset: GearDataset,
                              id: UUID = UUID()) throws -> GearPreset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PresetError.emptyName }
        let sports = unique(sportTypes)
        guard !sports.isEmpty else { throw PresetError.noSportTypes }
        let gear = unique(members)
        guard !gear.isEmpty else { throw PresetError.noMembers }
        let known = Set(dataset.gear.map(\.id))
        if let missing = gear.first(where: { !known.contains($0) }) { throw PresetError.unknownGear(missing) }
        return GearPreset(id: id, name: trimmed, sportTypes: sports, memberGearIDs: gear)
    }

    /// Aktive Presets der Sportart; Standard-Preset zuerst, sonst Reihenfolge nach Name. Presets ohne ein einziges
    /// verfügbares Mitglied werden nicht angeboten.
    public static func offered(for activity: ActivityRecord, in dataset: GearDataset) -> [PresetOffer] {
        let context = AssignmentContext(dataset: dataset)
        let byID = Dictionary(dataset.gear.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let defaultID = dataset.sportProfiles.first { $0.sportType == activity.sportType }?.defaultPresetID
        let offers = dataset.presets.filter { $0.isEnabled && $0.sportTypes.contains(activity.sportType) }.compactMap { p -> PresetOffer? in
            let available = p.memberGearIDs.filter { g in
                byID[g].map { AssignmentEngine.isAvailable($0, at: activity.startAt, in: context) } ?? false
            }
            guard !available.isEmpty else { return nil }
            return PresetOffer(preset: p, availableGearIDs: available,
                               unavailableGearIDs: p.memberGearIDs.filter { !available.contains($0) }, isDefault: p.id == defaultID)
        }
        return offers.sorted {
            if $0.isDefault != $1.isDefault { return $0.isDefault }
            return ($0.preset.name, $0.preset.id.uuidString) < ($1.preset.name, $1.preset.id.uuidString)
        }
    }

    /// Setzt oder löscht (`nil`) das Standard-Preset einer Sportart und liefert das neue Sportprofil (legt es an, wenn es fehlt).
    public static func setDefault(_ presetID: UUID?, for sport: SportType, in dataset: GearDataset,
                                  profileID: UUID = UUID()) throws -> SportProfile {
        if let presetID {
            guard let preset = dataset.presets.first(where: { $0.id == presetID }) else { throw PresetError.presetNotFound(presetID) }
            guard preset.sportTypes.contains(sport) else { throw PresetError.presetDoesNotCover(sport) }
        }
        var profile = dataset.sportProfiles.first { $0.sportType == sport } ?? SportProfile(id: profileID, sportType: sport)
        profile.defaultPresetID = presetID
        return profile
    }

    /// Entfernt ein Preset und löst Standard-Verweise. Bereits gebuchte Zuordnungen bleiben (kein rückwirkender Eingriff).
    public static func remove(_ presetID: UUID, from dataset: GearDataset) -> GearDataset {
        var next = dataset
        next.presets.removeAll { $0.id == presetID }
        for i in next.sportProfiles.indices where next.sportProfiles[i].defaultPresetID == presetID {
            next.sportProfiles[i].defaultPresetID = nil
        }
        return next
    }

    private static func unique<T: Hashable>(_ items: [T]) -> [T] {
        var seen = Set<T>()
        return items.filter { seen.insert($0).inserted }
    }
}

public enum RuleError: Error, Equatable { case notFound(UUID) }

public enum RuleManager {

    public static func setEnabled(_ ruleID: UUID, _ enabled: Bool, in dataset: GearDataset) throws -> GearDataset {
        var next = dataset
        guard let i = next.assignmentRules.firstIndex(where: { $0.id == ruleID }) else { throw RuleError.notFound(ruleID) }
        next.assignmentRules[i].enabled = enabled
        return next
    }

    /// Entfernt nur die Regel; abgeschlossene Zuordnungen bleiben (SPEC 6.3).
    public static func remove(_ ruleID: UUID, from dataset: GearDataset) throws -> GearDataset {
        var next = dataset
        guard next.assignmentRules.contains(where: { $0.id == ruleID }) else { throw RuleError.notFound(ruleID) }
        next.assignmentRules.removeAll { $0.id == ruleID }
        return next
    }
}
