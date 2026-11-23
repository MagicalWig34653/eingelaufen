import Foundation
import GearCore
import Testing
@testable import Eingelaufen

/// Ausrüstung anlegen, umbenennen, archivieren (PLAN M2, Spec Phase 0, SPEC 4.2, 1.3).
@Suite struct GearCommandTests {
    @Test func createGearStoresItemStatusHistoryAndEmptySummary() async throws {
        let p = try makePersistence()
        let bike = GearItem(name: "  Canyon Endurace ", createdAt: t0, category: .cycling, subtype: .roadBike)
        let outcome = try await p.apply(.createGear(bike), now: t0)
        #expect(outcome.gearID == bike.id)

        let ds = try await p.dataset()
        #expect(ds.gear.count == 1)
        #expect(ds.gear[0].name == "Canyon Endurace")
        #expect(ds.gear[0].category == .cycling)
        #expect(ds.gear[0].subtype == .roadBike)
        #expect(ds.gear[0].status == .active)
        #expect(ds.statusChanges.map(\.status) == [.active])
        #expect(ds.statusChanges[0].effectiveAt == t0)

        let usage = try await p.usage(of: bike.id)
        #expect(usage.uses == 0)
        #expect(usage.distanceMeters == .noData)   // T-09: nie „0 km“ erfinden
        #expect(usage.durationSeconds == .noData)
    }

    @Test func createGearNeedsOnlyAName() async throws {
        let p = try makePersistence()
        _ = try await p.apply(.createGear(GearItem(name: "Laufschuhe", createdAt: t0)), now: t0)
        let ds = try await p.dataset()
        #expect(ds.gear.count == 1)
        #expect(ds.gear[0].category == .other)
        #expect(ds.gear[0].purchaseDate == nil)
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func createGearRejectsEmptyNameAndStoresNothing(name: String) async throws {
        let p = try makePersistence()
        await #expect(throws: PersistenceError.emptyName) {
            _ = try await p.apply(.createGear(GearItem(name: name, createdAt: t0)), now: t0)
        }
        #expect(try await p.dataset().gear.isEmpty)
        #expect(try await p.outbox(pendingOnly: false).isEmpty)
    }

    @Test func createGearRejectsDuplicateID() async throws {
        let p = try makePersistence()
        let g = GearItem(name: "A", createdAt: t0)
        _ = try await p.apply(.createGear(g), now: t0)
        await #expect(throws: PersistenceError.gearAlreadyExists(g.id)) {
            _ = try await p.apply(.createGear(g), now: t0)
        }
        #expect(try await p.dataset().gear.count == 1)
    }

    @Test func renameGearTrimsAndKeepsEverythingElse() async throws {
        let p = try makePersistence()
        let g = GearItem(name: "Alt", createdAt: t0, category: .running)
        _ = try await p.apply(.createGear(g), now: t0)
        _ = try await p.apply(.renameGear(id: g.id, name: " Neu "), now: day(1))
        let item = try #require(try await p.dataset().gear.first)
        #expect(item.name == "Neu")
        #expect(item.category == .running)
        await #expect(throws: PersistenceError.gearNotFound(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)) {
            _ = try await p.apply(.renameGear(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "x"), now: t0)
        }
    }

    @Test func archivingKeepsGearAndHistoryAndIsReversible() async throws {
        let p = try makePersistence()
        let g = GearItem(name: "Alte Schuhe", createdAt: t0, category: .running)
        _ = try await p.apply(.createGear(g), now: t0)
        _ = try await p.apply(.setGearStatus(id: g.id, status: .archived, effectiveAt: day(10)), now: day(10))

        var ds = try await p.dataset()
        #expect(ds.gear.count == 1, "Archivieren löscht nichts (SPEC 4.2)")
        #expect(ds.gear[0].status == .archived)
        #expect(ds.statusChanges.map(\.status).sorted { $0.rawValue < $1.rawValue } == [.active, .archived])

        _ = try await p.apply(.setGearStatus(id: g.id, status: .active, effectiveAt: day(20)), now: day(20))
        ds = try await p.dataset()
        #expect(ds.gear[0].status == .active)
        #expect(ds.statusChanges.count == 3)
    }

    @Test func settingTheSameStatusIsANoOp() async throws {
        let p = try makePersistence()
        let g = GearItem(name: "X", createdAt: t0)
        _ = try await p.apply(.createGear(g), now: t0)
        let before = try await p.outbox(pendingOnly: false).count
        _ = try await p.apply(.setGearStatus(id: g.id, status: .active, effectiveAt: day(1)), now: day(1))
        #expect(try await p.dataset().statusChanges.count == 1)
        #expect(try await p.outbox(pendingOnly: false).count == before)
    }

    @Test func statusOfUnknownGearIsRejected() async throws {
        let p = try makePersistence()
        let unknown = UUID()
        await #expect(throws: PersistenceError.gearNotFound(unknown)) {
            _ = try await p.apply(.setGearStatus(id: unknown, status: .archived, effectiveAt: t0), now: t0)
        }
    }

    @Test func gearOfAllTwelveCategoriesCanBeCreated() async throws {
        let p = try makePersistence()
        for category in SportCategory.allCases {
            _ = try await p.apply(.createGear(GearItem(name: category.rawValue, createdAt: t0, category: category)), now: t0)
        }
        let ds = try await p.dataset()
        #expect(Set(ds.gear.map(\.category)) == Set(SportCategory.allCases))
    }
}
