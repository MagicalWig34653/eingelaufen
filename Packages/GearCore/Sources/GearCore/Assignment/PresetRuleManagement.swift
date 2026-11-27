import Foundation

// M4 (Stub für den roten Lauf): Presets und Regeln verwalten.

public enum PresetError: Error, Equatable {
    case emptyName, noMembers, noSportTypes
    case unknownGear(UUID)
    case presetNotFound(UUID)
    case presetDoesNotCover(SportType)
}

public struct PresetOffer: Sendable, Equatable {
    public var preset: GearPreset
    public var availableGearIDs: [UUID]
    public var unavailableGearIDs: [UUID]
    public var isDefault: Bool
}

public enum PresetPlanner {
    public static func create(name: String, sportTypes: [SportType], members: [UUID], in dataset: GearDataset,
                              id: UUID = UUID()) throws -> GearPreset {
        GearPreset(id: id, name: name, sportTypes: sportTypes, memberGearIDs: members)
    }
    public static func offered(for activity: ActivityRecord, in dataset: GearDataset) -> [PresetOffer] { [] }
    public static func setDefault(_ presetID: UUID?, for sport: SportType, in dataset: GearDataset,
                                  profileID: UUID = UUID()) throws -> SportProfile {
        SportProfile(id: profileID, sportType: sport)
    }
    public static func remove(_ presetID: UUID, from dataset: GearDataset) -> GearDataset { dataset }
}

public enum RuleError: Error, Equatable { case notFound(UUID) }

public enum RuleManager {
    public static func setEnabled(_ ruleID: UUID, _ enabled: Bool, in dataset: GearDataset) throws -> GearDataset { dataset }
    public static func remove(_ ruleID: UUID, from dataset: GearDataset) throws -> GearDataset { dataset }
}
