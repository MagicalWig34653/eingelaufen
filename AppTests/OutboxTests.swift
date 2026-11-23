import Foundation
import GearCore
import Testing
@testable import Eingelaufen

/// Outbox (ARCHITEKTUR A-04): Seiteneffekte erst nach Commit, im selben Commit vorgemerkt, idempotent zugestellt.
@Suite struct OutboxTests {
    @Test func commandWritesOutboxEntryInTheSameCommit() async throws {
        let p = try makePersistence()
        let g = GearItem(name: "Rad", createdAt: t0, category: .cycling)
        _ = try await p.apply(.createGear(g), now: t0)
        let items = try await p.outbox(pendingOnly: true)
        #expect(items.count == 1)
        #expect(items[0].kind == .gearChanged)
        #expect(items[0].subjectIDs == [g.id])
        #expect(items[0].createdAt == t0)
        #expect(items[0].attempts == 0)
    }

    @Test func manualActivityMarksActivityAndAffectedGear() async throws {
        let p = try makePersistence()
        let g = GearItem(name: "Rad", createdAt: t0, category: .cycling)
        _ = try await p.apply(.createGear(g), now: t0)
        let a = ManualActivityInput(sportType: SportCategory.cycling.defaultSportType, startAt: day(1),
                                    durationSeconds: 600, distanceMeters: nil, gearIDs: [g.id])
        _ = try await p.apply(.addManualActivity(a), now: day(2))
        let item = try #require(try await p.outbox(pendingOnly: true).first { $0.kind == .activityChanged })
        #expect(item.subjectIDs.contains(a.id))
        #expect(item.subjectIDs.contains(g.id))
    }

    @Test func dispatcherDeliversInOrderThenMarksProcessed() async throws {
        let p = try makePersistence()
        _ = try await p.apply(.createGear(GearItem(name: "A", createdAt: t0)), now: t0)
        _ = try await p.apply(.createGear(GearItem(name: "B", createdAt: day(1))), now: day(1))
        let handler = RecordingHandler()
        let delivered = await OutboxDispatcher(persistence: p).deliver(to: handler, now: day(2))
        #expect(delivered == 2)
        #expect(await handler.seen.map(\.createdAt) == [t0, day(1)])
        #expect(try await p.outbox(pendingOnly: true).isEmpty)
        #expect(try await p.outbox(pendingOnly: false).count == 2, "Zugestellte Einträge bleiben als Nachweis")
    }

    @Test func deliveringTwiceDoesNotRepeatSideEffects() async throws {
        let p = try makePersistence()
        _ = try await p.apply(.createGear(GearItem(name: "A", createdAt: t0)), now: t0)
        let handler = RecordingHandler()
        let dispatcher = OutboxDispatcher(persistence: p)
        _ = await dispatcher.deliver(to: handler, now: day(1))
        let second = await dispatcher.deliver(to: handler, now: day(2))
        #expect(second == 0)
        #expect(await handler.seen.count == 1)
    }

    @Test func failedDeliveryIsKeptAndRetried() async throws {
        let p = try makePersistence()
        _ = try await p.apply(.createGear(GearItem(name: "A", createdAt: t0)), now: t0)
        let handler = RecordingHandler()
        await handler.fail(on: [.gearChanged])
        let dispatcher = OutboxDispatcher(persistence: p)
        #expect(await dispatcher.deliver(to: handler, now: day(1)) == 0)
        var pending = try await p.outbox(pendingOnly: true)
        #expect(pending.count == 1)
        #expect(pending[0].attempts == 1)
        #expect(pending[0].lastError != nil)

        await handler.fail(on: [])
        #expect(await dispatcher.deliver(to: handler, now: day(2)) == 1)
        pending = try await p.outbox(pendingOnly: true)
        #expect(pending.isEmpty)
    }

    @Test func oneFailingEntryDoesNotBlockTheOthers() async throws {
        let p = try makePersistence()
        _ = try await p.apply(.createGear(GearItem(name: "A", createdAt: t0)), now: t0)
        _ = try await p.apply(.completeOnboarding(OnboardingChoice(categories: [.running], health: .later)), now: day(1))
        let handler = RecordingHandler()
        await handler.fail(on: [.gearChanged])
        #expect(await OutboxDispatcher(persistence: p).deliver(to: handler, now: day(2)) == 1)
        #expect(await handler.seen.map(\.kind) == [.onboardingCompleted])
    }
}
