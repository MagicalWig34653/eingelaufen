import Foundation

// M4 (Stub für den roten Lauf): Posteingang auf Datensatz-Ebene.

public struct InboxResolution: Sendable, Equatable {
    public var pending: PendingAssignment
    public var assignments: [ActivityGearAssignment]
    public var rule: AssignmentRule?
    public var result: InboxResult
}

public struct InboxEntry: Sendable, Equatable, Identifiable {
    public var pending: PendingAssignment
    public var activity: ActivityRecord
    public var id: UUID { pending.id }
}

public enum InboxResolver {
    public static func resolve(_ pendingID: UUID, action: InboxAction, remember: Bool, in dataset: GearDataset, now: Date,
                               makeID: () -> UUID = UUID.init) -> InboxResolution? { nil }
    public static func apply(_ resolution: InboxResolution, to dataset: GearDataset) -> GearDataset { dataset }
}

public enum InboxQuery {
    public static func open(in dataset: GearDataset) -> [InboxEntry] { [] }
    public static func openCount(in dataset: GearDataset) -> Int { 0 }
}
