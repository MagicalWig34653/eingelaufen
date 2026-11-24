import Foundation

// Komponenten montieren, ausbauen, umbauen, ersetzen (SPEC 4.3, 4.4, 8.4). Rein, ohne Systemuhr, ohne Persistenz:
// liefert einen Plan, den die App als einen Befehl in einer Transaktion schreibt.

public enum ComponentPlanError: Error, Equatable, Sendable {
    case notImplemented
    case sameGear, sameParent, gearNotFound(UUID), gearAlreadyExists(UUID), emptyName
    case alreadyMounted(currentParent: UUID), notMounted
    case wouldCreateCycle, overlapsExistingInstallation, beforeInstallationStart
}

/// Ergebnis einer Montage-Aktion. `installations` sind Upserts (beendete und neue Montagen).
public struct ComponentPlan: Equatable, Sendable {
    public var installations: [Installation] = []
    public var newGear: [GearItem] = []
    public var statusChanges: [GearStatusChange] = []
    public var maintenanceEvents: [MaintenanceEvent] = []
    public init() {}
}

public enum ComponentPlanner {
    public static func mount(child: UUID, parent: UUID, at: Date, graph: InstallationGraph, gear: [GearItem],
                             installationID: UUID = UUID()) throws -> ComponentPlan { ComponentPlan() }
    public static func unmount(child: UUID, at: Date, graph: InstallationGraph, gear: [GearItem]) throws -> ComponentPlan { ComponentPlan() }
    public static func move(child: UUID, to newParent: UUID, at: Date, graph: InstallationGraph, gear: [GearItem],
                            installationID: UUID = UUID()) throws -> ComponentPlan { ComponentPlan() }
    public static func replace(old: UUID, with new: GearItem, oldBecomes: GearStatus?, at: Date, graph: InstallationGraph,
                               gear: [GearItem], installationID: UUID = UUID()) throws -> ComponentPlan { ComponentPlan() }
}

public struct ComponentHistoryEntry: Equatable, Sendable {
    public var installationID: UUID
    public var childID: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var isCurrent: Bool { endedAt == nil }
}

public enum ComponentHistory {
    /// Alle Komponenten eines Gegenstands, aktuelle zuerst, danach ausgebaute (jüngster Ausbau zuerst).
    public static func entries(parent: UUID, installations: [Installation]) -> [ComponentHistoryEntry] { [] }
}
