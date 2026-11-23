import Foundation
import GearCore
import SwiftData
@testable import Eingelaufen

/// Fester Bezugspunkt der Tests: kein Test liest die Systemuhr (SPEC 10.4).
let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func day(_ offset: Double) -> Date { t0.addingTimeInterval(offset * 86_400) }

func makePersistence() throws -> PersistenceActor {
    PersistenceActor(modelContainer: try Stores.makeContainer(inMemory: true))
}

/// Arrays nach ID sortiert, damit Vergleiche nicht von der Abfragereihenfolge abhängen.
func normalized(_ d: GearDataset) -> GearDataset {
    var n = GearDataset()
    n.gear = d.gear.sorted { $0.id.uuidString < $1.id.uuidString }
    n.statusChanges = d.statusChanges.sorted { $0.id.uuidString < $1.id.uuidString }
    n.installations = d.installations.sorted { $0.id.uuidString < $1.id.uuidString }
    n.presets = d.presets.sorted { $0.id.uuidString < $1.id.uuidString }
    n.sportProfiles = d.sportProfiles.sorted { $0.id.uuidString < $1.id.uuidString }
    n.activities = d.activities.sorted { $0.id.uuidString < $1.id.uuidString }
    n.segments = d.segments.sorted { $0.id.uuidString < $1.id.uuidString }
    n.assignments = d.assignments.sorted { $0.id.uuidString < $1.id.uuidString }
    n.maintenanceEvents = d.maintenanceEvents.sorted { $0.id.uuidString < $1.id.uuidString }
    n.maintenanceRules = d.maintenanceRules.sorted { $0.id.uuidString < $1.id.uuidString }
    n.assignmentRules = d.assignmentRules.sorted { $0.id.uuidString < $1.id.uuidString }
    n.pendings = d.pendings.sorted { $0.id.uuidString < $1.id.uuidString }
    return n
}

/// Zeichnet zugestellte Outbox-Einträge auf.
actor RecordingHandler: OutboxHandler {
    private(set) var seen: [OutboxItem] = []
    var failing: Set<OutboxKind> = []
    func fail(on kinds: Set<OutboxKind>) { failing = kinds }
    func handle(_ item: OutboxItem) async throws {
        if failing.contains(item.kind) { throw HandlerError.boom }
        seen.append(item)
    }
    enum HandlerError: Error { case boom }
}
