import Foundation

// Komponenten montieren, ausbauen, umbauen, ersetzen (SPEC 4.3, 4.4, 8.4). Rein, ohne Systemuhr, ohne Persistenz:
// liefert einen Plan, den die App als einen Befehl in einer Transaktion schreibt. Rückdatieren ist ausdrücklich
// erlaubt (SPEC 4.5): das Ledger der berührten Aktivitäten wird danach neu berechnet.

public enum ComponentPlanError: Error, Equatable, Sendable {
    case sameGear, sameParent
    case gearNotFound(UUID), gearAlreadyExists(UUID)
    case emptyName
    case alreadyMounted(currentParent: UUID)
    case notMounted
    case wouldCreateCycle
    case overlapsExistingInstallation
    /// Ausbau/Umbau/Ersatz muss nach dem Beginn der aktuellen Montage liegen (Intervall `[start, end)`, I-03).
    case beforeInstallationStart
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
    /// Montiert `child` ab `at` auf `parent`. Eine schon montierte Komponente wird umgebaut, nicht neu montiert.
    public static func mount(child: UUID, parent: UUID, at: Date, graph: InstallationGraph, gear: [GearItem],
                             installationID: UUID = UUID()) throws -> ComponentPlan {
        try require([child, parent], in: gear)
        guard child != parent else { throw ComponentPlanError.sameGear }
        if let current = graph.currentInstallation(of: child) {
            throw ComponentPlanError.alreadyMounted(currentParent: current.parentGearID)
        }
        let started = Installation(id: installationID, parentGearID: parent, childGearID: child, startedAt: at)
        try check(adding: started, to: graph)
        var plan = ComponentPlan()
        plan.installations = [started]
        plan.maintenanceEvents = [MaintenanceEvent(gearID: parent, kind: .partInstalled, performedAt: at)]
        return plan
    }

    /// Beendet die offene Montage. Das Teil bleibt mit seiner Historie bestehen (SPEC 4.1).
    public static func unmount(child: UUID, at: Date, graph: InstallationGraph, gear: [GearItem]) throws -> ComponentPlan {
        try require([child], in: gear)
        let ended = try ending(child, at: at, graph: graph)
        var plan = ComponentPlan()
        plan.installations = [ended]
        plan.maintenanceEvents = [MaintenanceEvent(gearID: ended.parentGearID, kind: .partRemoved, performedAt: at)]
        return plan
    }

    /// Umbau: die bisherige Montage endet, die neue beginnt zum selben Zeitpunkt; Objekt und Lebensdauer bleiben (SPEC 4.3).
    public static func move(child: UUID, to newParent: UUID, at: Date, graph: InstallationGraph, gear: [GearItem],
                            installationID: UUID = UUID()) throws -> ComponentPlan {
        try require([child, newParent], in: gear)
        guard child != newParent else { throw ComponentPlanError.sameGear }
        let ended = try ending(child, at: at, graph: graph)
        guard ended.parentGearID != newParent else { throw ComponentPlanError.sameParent }
        let started = Installation(id: installationID, parentGearID: newParent, childGearID: child, startedAt: at)
        try check(adding: started, to: graph.replacing(ended))
        var plan = ComponentPlan()
        plan.installations = [ended, started]
        plan.maintenanceEvents = [
            MaintenanceEvent(gearID: ended.parentGearID, kind: .partRemoved, performedAt: at),
            MaintenanceEvent(gearID: newParent, kind: .partInstalled, performedAt: at),
        ]
        return plan
    }

    /// „Kette ersetzen“ (SPEC 4.4): alte Montage beenden, altes Teil optional einlagern/ausmustern, **neues** Teil anlegen,
    /// neue Montage am selben Elternteil starten. Der Verschleiß des alten Teils bleibt unverändert.
    public static func replace(old: UUID, with new: GearItem, oldBecomes: GearStatus?, at: Date, graph: InstallationGraph,
                               gear: [GearItem], installationID: UUID = UUID()) throws -> ComponentPlan {
        try require([old], in: gear)
        let ended = try ending(old, at: at, graph: graph)
        guard !gear.contains(where: { $0.id == new.id }) else { throw ComponentPlanError.gearAlreadyExists(new.id) }
        let name = new.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ComponentPlanError.emptyName }
        var item = new
        item.name = name
        let started = Installation(id: installationID, parentGearID: ended.parentGearID, childGearID: new.id, startedAt: at)
        var plan = ComponentPlan()
        plan.installations = [ended, started]
        plan.newGear = [item]
        if let status = oldBecomes { plan.statusChanges = [GearStatusChange(gearID: old, status: status, effectiveAt: at)] }
        plan.maintenanceEvents = [MaintenanceEvent(gearID: ended.parentGearID, kind: .partReplaced, performedAt: at)]
        return plan
    }

    // MARK: Intern

    private static func require(_ ids: [UUID], in gear: [GearItem]) throws {
        let known = Set(gear.map(\.id))
        for id in ids where !known.contains(id) { throw ComponentPlanError.gearNotFound(id) }
    }

    /// Die offene Montage, zum Zeitpunkt `at` beendet.
    private static func ending(_ child: UUID, at: Date, graph: InstallationGraph) throws -> Installation {
        guard var current = graph.currentInstallation(of: child) else { throw ComponentPlanError.notMounted }
        guard at > current.startedAt else { throw ComponentPlanError.beforeInstallationStart }
        current.endedAt = at
        return current
    }

    private static func check(adding installation: Installation, to graph: InstallationGraph) throws {
        for issue in graph.validating(adding: installation) {
            switch issue {
            case .cycle: throw ComponentPlanError.wouldCreateCycle
            case .overlappingChildInstallations: throw ComponentPlanError.overlapsExistingInstallation
            case .selfInstallation: throw ComponentPlanError.sameGear
            default: continue
            }
        }
    }
}

extension InstallationGraph {
    /// Kopie des Graphen, in der die Montage mit gleicher ID ersetzt ist.
    func replacing(_ installation: Installation) -> InstallationGraph {
        InstallationGraph(installations.filter { $0.id != installation.id } + [installation])
    }
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
    public static func entries(parent: UUID, installations: [Installation]) -> [ComponentHistoryEntry] {
        installations.filter { $0.parentGearID == parent }
            .map { ComponentHistoryEntry(installationID: $0.id, childID: $0.childGearID, startedAt: $0.startedAt, endedAt: $0.endedAt) }
            .sorted { a, b in
                if a.isCurrent != b.isCurrent { return a.isCurrent }
                return (b.endedAt ?? .distantPast, b.startedAt, b.installationID.uuidString)
                    < (a.endedAt ?? .distantPast, a.startedAt, a.installationID.uuidString)
            }
    }
}
