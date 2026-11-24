import Foundation
import GearCore
import Testing
@testable import Eingelaufen

/// Wartung erfassen und Regeln pflegen (PLAN M5, SPEC 8.1, 8.3, S07).
@Suite struct MaintenanceCommandTests {
    private let bike = GearItem(name: "Canyon Endurace", createdAt: day(-30), category: .cycling, subtype: .roadBike)
    private let now = day(30)

    private func setup() async throws -> PersistenceActor {
        let p = try makePersistence()
        _ = try await p.apply(.createGear(bike), now: now)
        return p
    }

    @Test func quickActionSavesImmediatelyWithNowAndNoInventedValues() async throws {
        let p = try await setup()
        let id = UUID()
        _ = try await p.apply(.recordMaintenance(MaintenanceInput(id: id, gearID: bike.id, kind: .lubricated)), now: now)
        let events = try await p.dataset().maintenanceEvents
        #expect(events == [MaintenanceEvent(id: id, gearID: bike.id, kind: .lubricated, performedAt: now)])
        #expect(try await p.outbox(pendingOnly: false).map(\.kind).contains(.maintenanceChanged))
    }

    @Test func optionalDateMeasurementCostAndNoteArePersisted() async throws {
        let p = try await setup()
        _ = try await p.apply(.recordMaintenance(MaintenanceInput(
            gearID: bike.id, kind: .wearMeasured, performedAt: day(25), measurement: 0.5, costMinor: 1_500, notes: " Lehre ")), now: now)
        let e = try #require(try await p.dataset().maintenanceEvents.first)
        #expect(e.performedAt == day(25) && e.measurement == 0.5 && e.costMinor == 1_500 && e.notes == "Lehre")
    }

    @Test func invalidMaintenanceStoresNothing() async throws {
        let p = try await setup()
        await #expect(throws: PersistenceError.maintenance(.noteRequired)) {
            _ = try await p.apply(.recordMaintenance(MaintenanceInput(gearID: bike.id, kind: .custom)), now: now)
        }
        await #expect(throws: PersistenceError.maintenance(.performedInFuture)) {
            _ = try await p.apply(.recordMaintenance(MaintenanceInput(gearID: bike.id, kind: .cleaned, performedAt: day(40))), now: now)
        }
        let missing = UUID()
        await #expect(throws: PersistenceError.gearNotFound(missing)) {
            _ = try await p.apply(.recordMaintenance(MaintenanceInput(gearID: missing, kind: .cleaned)), now: now)
        }
        #expect(try await p.dataset().maintenanceEvents.isEmpty)
        #expect(try await p.outbox(pendingOnly: false).filter { $0.kind == .maintenanceChanged }.isEmpty)
    }

    @Test func maintenanceDoesNotChangeUsageOrLifetime() async throws {
        let p = try await setup()
        _ = try await p.apply(.addManualActivity(ManualActivityInput(
            sportType: SportCategory.cycling.defaultSportType, startAt: day(20), durationSeconds: 3_600,
            distanceMeters: 30_000, gearIDs: [bike.id])), now: now)
        _ = try await p.apply(.recordMaintenance(MaintenanceInput(gearID: bike.id, kind: .lubricated)), now: now)
        #expect(try await p.usage(of: bike.id).distanceMeters == .measured(30_000, isComplete: true))   // T-11
    }

    @Test func ruleCanBeSetReplacedAndRemoved() async throws {
        let p = try await setup()
        var rule = MaintenanceRule(gearID: bike.id, kind: .lubricated, metric: .distance, intervalValue: 350_000, warningLeadValue: 50_000)
        _ = try await p.apply(.setMaintenanceRule(rule), now: now)
        #expect(try await p.dataset().maintenanceRules == [rule])
        rule.intervalValue = 400_000
        rule.enabled = false
        _ = try await p.apply(.setMaintenanceRule(rule), now: now)
        #expect(try await p.dataset().maintenanceRules == [rule])
        _ = try await p.apply(.removeMaintenanceRule(rule.id), now: now)
        #expect(try await p.dataset().maintenanceRules.isEmpty)
        await #expect(throws: PersistenceError.ruleNotFound(rule.id)) {
            _ = try await p.apply(.removeMaintenanceRule(rule.id), now: now)
        }
    }

    @Test func invalidRulesAreRejected() async throws {
        let p = try await setup()
        for bad in [0.0, -5, .nan, .infinity] {
            await #expect(throws: PersistenceError.invalidRule) {
                _ = try await p.apply(.setMaintenanceRule(MaintenanceRule(gearID: bike.id, kind: .cleaned, metric: .distance, intervalValue: bad)), now: now)
            }
        }
        await #expect(throws: PersistenceError.invalidRule) {   // Vorwarnung darf das Intervall nicht überschreiten
            _ = try await p.apply(.setMaintenanceRule(MaintenanceRule(gearID: bike.id, kind: .cleaned, metric: .distance,
                                                                       intervalValue: 100, warningLeadValue: 200)), now: now)
        }
        let missing = UUID()
        await #expect(throws: PersistenceError.gearNotFound(missing)) {
            _ = try await p.apply(.setMaintenanceRule(MaintenanceRule(gearID: missing, kind: .cleaned, metric: .distance, intervalValue: 1)), now: now)
        }
        #expect(try await p.dataset().maintenanceRules.isEmpty)
    }
}
