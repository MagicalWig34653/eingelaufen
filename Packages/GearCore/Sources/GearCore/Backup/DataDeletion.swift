import Foundation

public enum DeletionError: Error, Equatable, Sendable {
    case gearNotFound(UUID)
    case activityNotFound(UUID)
}

public enum DataDeletion {
    public static func deleteGear(_ id: UUID, in dataset: GearDataset) throws -> GearDataset { dataset }
    public static func deleteActivity(_ id: UUID, in dataset: GearDataset, now: Date) throws -> GearDataset { dataset }
}
