import Foundation
import GearCore
import Testing
@testable import Eingelaufen

/// Komponenten montieren, umbauen, ersetzen gegen die echte Persistenz (PLAN M5, SPEC 4.3/4.4, T-02).
@Suite struct ComponentCommandTests {
    private let bike = GearItem(name: "Canyon Endurace", createdAt: day(-30), category: .cycling, subtype: .roadBike)
    private let bike2 = GearItem(name: "Gravel", createdAt: day(-30), category: .cycling, subtype: .gravel)
    private let chain = GearItem(name: "Kette", createdAt: day(-30), category: .cycling)
    private let newChain = GearItem(name: "Kette neu", createdAt: day(10), category: .cycling)
    private let now = day(30)

    private func setup(mounted: Bool = true) async throws -> PersistenceActor {
        let p = try makePersistence()
        for g in [bike, bike2, chain] { _ = try await p.apply(.createGear(g), now: now) }
        if mounted { _ = try await p.apply(.mountComponent(child: chain.id, parent: bike.id, at: day(0)), now: now) }
        return p
    }

    private func ride(_ p: PersistenceActor, _ d: Double, km: Double = 20) async throws {
        _ = try await p.apply(.addManualActivity(ManualActivityInput(
            sportType: SportCategory.cycling.defaultSportType, startAt: day(d), durationSeconds: 3_600,
            distanceMeters: km * 1_000, gearIDs: [bike.id])), now: now)
    }

    @Test func addComponentCreatesPartAndMountsItInOneCommand() async throws {
        let p = try makePersistence()
        _ = try await p.apply(.createGear(bike), now: now)
        let outcome = try await p.apply(.addComponent(parent: bike.id, item: chain, at: day(1)), now: now)
        #expect(outcome.gearID == chain.id)
        let ds = try await p.dataset()
        #expect(ds.gear.count == 2)
        #expect(ds.installations.count == 1)
        #expect(ds.installations[0].parentGearID == bike.id && ds.installations[0].childGearID == chain.id)
        #expect(ds.installations[0].startedAt == day(1) && ds.installations[0].endedAt == nil)
        #expect(ds.maintenanceEvents.map(\.kind) == [.partInstalled])
        #expect(try await p.usage(of: chain.id).distanceMeters == .noData)   // T-09
    }

    @Test func mountUnmountMoveKeepOnePartAndAllHistory() async throws {
        let p = try await setup()
        _ = try await p.apply(.moveComponent(child: chain.id, to: bike2.id, at: day(5)), now: now)
        var ds = try await p.dataset()
        #expect(ds.gear.count == 3)    // dasselbe Teil, kein Duplikat
        #expect(ds.installations.count == 2)
        #expect(ds.installations.filter { $0.endedAt == nil }.map(\.parentGearID) == [bike2.id])
        #expect(InstallationGraph(ds.installations).validate().isEmpty)
        _ = try await p.apply(.unmountComponent(child: chain.id, at: day(8)), now: now)
        ds = try await p.dataset()
        #expect(ds.installations.allSatisfy { $0.endedAt != nil })
        let kinds = ds.maintenanceEvents.map(\.kind)
        #expect(kinds.filter { $0 == .partInstalled }.count == 2)
        #expect(kinds.filter { $0 == .partRemoved }.count == 2)
    }

    @Test func replaceCreatesNewPartKeepsOldAndStoresOldAway() async throws {
        let p = try await setup()
        let outcome = try await p.apply(.replaceComponent(old: chain.id, with: newChain, oldBecomes: .stored, at: day(10)), now: now)
        #expect(outcome.gearID == newChain.id)
        let ds = try await p.dataset()
        #expect(ds.gear.count == 4)
        #expect(ds.gear.first { $0.id == chain.id }?.status == .stored)
        #expect(ds.gear.first { $0.id == newChain.id }?.status == .active)
        #expect(ds.statusChanges.filter { $0.gearID == chain.id }.map(\.status).contains(.stored))
        let open = ds.installations.filter { $0.endedAt == nil }
        #expect(open.map(\.childGearID) == [newChain.id] && open.map(\.parentGearID) == [bike.id])
        #expect(ds.maintenanceEvents.map(\.kind).contains(.partReplaced))
    }

    @Test func t02_chainChangeIsHistoricallyConsistentInPersistence() async throws {
        let p = try await setup()
        try await ride(p, 1); try await ride(p, 2)
        _ = try await p.apply(.replaceComponent(old: chain.id, with: newChain, oldBecomes: .retired, at: day(10)), now: now)
        try await ride(p, 12)
        #expect(try await p.usage(of: chain.id).uses == 2)
        #expect(try await p.usage(of: chain.id).distanceMeters == .measured(40_000, isComplete: true))   // nicht zurückgesetzt
        #expect(try await p.usage(of: newChain.id).uses == 1)
        #expect(try await p.usage(of: newChain.id).distanceMeters == .measured(20_000, isComplete: true))
        #expect(try await p.usage(of: bike.id).uses == 3)
    }

    @Test func backdatedReplaceRecomputesAffectedUsageAndEqualsFullRebuild() async throws {
        let p = try await setup()
        try await ride(p, 1); try await ride(p, 2)
        #expect(try await p.usage(of: chain.id).uses == 2)
        _ = try await p.apply(.replaceComponent(old: chain.id, with: newChain, oldBecomes: nil, at: day(1.5)), now: now)
        #expect(try await p.usage(of: chain.id).uses == 1)
        #expect(try await p.usage(of: newChain.id).uses == 1)
        let incremental = try await p.ledger()
        try await p.rebuildAll(now: now)
        #expect(try await p.ledger() == incremental)    // I-10
        #expect(try await p.usage(of: chain.id).uses == 1)
    }

    @Test func invalidComponentCommandsRollBackCompletely() async throws {
        let p = try await setup()
        let before = normalized(try await p.dataset())
        let outboxBefore = try await p.outbox(pendingOnly: false).count
        await #expect(throws: PersistenceError.component(.beforeInstallationStart)) {
            _ = try await p.apply(.unmountComponent(child: chain.id, at: day(0)), now: now)
        }
        await #expect(throws: PersistenceError.component(.alreadyMounted(currentParent: bike.id))) {
            _ = try await p.apply(.mountComponent(child: chain.id, parent: bike2.id, at: day(3)), now: now)
        }
        await #expect(throws: PersistenceError.component(.wouldCreateCycle)) {
            _ = try await p.apply(.mountComponent(child: bike.id, parent: chain.id, at: day(3)), now: now)
        }
        await #expect(throws: PersistenceError.component(.emptyName)) {
            _ = try await p.apply(.replaceComponent(old: chain.id, with: GearItem(name: " "), oldBecomes: nil, at: day(3)), now: now)
        }
        #expect(normalized(try await p.dataset()) == before)
        #expect(try await p.outbox(pendingOnly: false).count == outboxBefore)
    }
}
