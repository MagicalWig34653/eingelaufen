import Foundation
import GearCore
import SwiftData
import Testing
import UserNotifications
@testable import Eingelaufen

/// M6: Benachrichtigungen in der App. Koordinator gegen eine aufzeichnende Mitteilungszentrale, Antworten laufen über
/// denselben Befehl wie der Posteingang (`resolvePending`: Eintrag, Ledger und Outbox in einem Commit), T-10 in der App.
private let cycling = SportCategory.cycling.defaultSportType

actor RecordingNotificationCenter: NotificationCenterClient {
    var status: NotificationAuthorization
    var grantOnRequest = true
    private(set) var requests = 0
    private(set) var added: [NotificationRequestValue] = []
    private(set) var removed: [String] = []
    private var live: Set<String> = []

    init(status: NotificationAuthorization = .authorized) { self.status = status }

    func authorization() async -> NotificationAuthorization { status }
    func requestAuthorization() async -> Bool {
        requests += 1
        status = grantOnRequest ? .authorized : .denied
        return grantOnRequest
    }
    private var slow = false
    func setSlow() { slow = true }
    func identifiers() async -> Set<String> {
        if slow { try? await Task.sleep(for: .milliseconds(100)) }
        return live
    }
    func add(_ request: NotificationRequestValue) async throws {
        added.append(request)
        live.insert(request.identifier)
    }
    func remove(_ identifiers: [String]) async {
        removed += identifiers
        live.subtract(identifiers)
    }
}

private struct World {
    let p: PersistenceActor
    let center: RecordingNotificationCenter
    let coordinator: NotificationCoordinator
    let bikeA: GearItem, bikeB: GearItem
    let ride: ActivityRecord
    let pendingID: UUID
}

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// Zwei Räder, eine Fahrt mit offenem Vorschlag „Rad A“ (Revision 1); optional eine fällige Wartungsregel an Rad B.
private func world(status: NotificationAuthorization = .authorized, pending: Bool = true,
                   maintenanceRule: Bool = false, onboarded: Bool = true) async throws -> World {
    let p = try makePersistence()
    let bikeA = GearItem(name: "Rad A", createdAt: day(-100), category: .cycling, subtype: .roadBike)
    let bikeB = GearItem(name: "Rad B", createdAt: day(-99), category: .cycling, subtype: .roadBike)
    let ride = ActivityRecord(source: .healthKit, sourceID: "W1", sportType: cycling, startAt: day(1),
                              endAt: day(1).addingTimeInterval(3_600), distanceMeters: 30_000, durationSeconds: 3_600)
    var d = GearDataset()
    d.gear = [bikeA, bikeB]
    d.statusChanges = d.gear.map { GearStatusChange(gearID: $0.id, status: .active, effectiveAt: day(-100)) }
    d.activities = [ride]
    let entry = PendingAssignment(activityID: ride.id, state: .suggested, proposedGearIDs: [bikeA.id], alternatives: [[bikeB.id]],
                                  reason: .history, confidence: .medium, createdAt: day(1))
    if pending { d.pendings = [entry] }
    if maintenanceRule {
        d.maintenanceRules = [MaintenanceRule(gearID: bikeB.id, kind: .inspected, metric: .calendarAge, intervalValue: 10)]
        d.maintenanceEvents = [MaintenanceEvent(gearID: bikeB.id, kind: .inspected, performedAt: day(-20))]
    }
    try await p.load(d)
    if onboarded { _ = try await p.apply(.completeOnboarding(OnboardingChoice(categories: [], health: .later)), now: day(0)) }
    let center = RecordingNotificationCenter(status: status)
    return World(p: p, center: center, coordinator: NotificationCoordinator(persistence: p, center: center, calendar: utc),
                 bikeA: bikeA, bikeB: bikeB, ride: ride, pendingID: entry.id)
}

private func info(_ w: World, revision: Int = 1) -> [String: String] {
    NotificationPayload(pendingID: w.pendingID, proposalRevision: revision, activityID: w.ride.id).userInfo
}

@Suite struct NotificationTests {

    // MARK: Einstellungen und Migration

    @Test func preferencesArePersistedAsCommandWithOutbox() async throws {
        let p = try makePersistence()
        #expect(try await p.notificationPreferences() == NotificationPreferences(level: .assignmentAndMaintenance, quietHours: nil))
        let prefs = NotificationPreferences(level: .assignmentOnly, quietHours: QuietHours(startMinute: 21 * 60, endMinute: 6 * 60 + 30))
        _ = try await p.apply(.setNotificationPreferences(prefs), now: day(1))
        #expect(try await p.notificationPreferences() == prefs)
        #expect(try await p.outbox(pendingOnly: true).contains { $0.kind == .notificationSettingsChanged })
        _ = try await p.apply(.setNotificationPreferences(NotificationPreferences(level: .off, quietHours: nil)), now: day(2))
        #expect(try await p.notificationPreferences() == NotificationPreferences(level: .off, quietHours: nil))
    }

    @Test func storeWrittenWithSchemaV1OpensAsV2WithSettingsIntact() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("v1v2-\(UUID().uuidString).store")
        defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        do {
            let c1 = try ModelContainer(for: Schema(versionedSchema: SchemaV1.self), configurations: ModelConfiguration(url: url))
            let ctx = ModelContext(c1)
            let s = SchemaV1.AppSettingsEntity()
            s.onboardingCompleted = true
            s.importWindowDays = 90
            ctx.insert(s)
            try ctx.save()
        }
        let c2 = try Stores.makeContainer(inMemory: false, url: url)
        let rows = try ModelContext(c2).fetch(FetchDescriptor<AppSettingsEntity>())
        #expect(rows.count == 1)
        #expect(rows.first?.onboardingCompleted == true && rows.first?.importWindowDays == 90)
        #expect(rows.first?.notificationPreferences == NotificationPreferences(level: .assignmentAndMaintenance, quietHours: nil))
    }

    // MARK: Kategorien und Aktionen (F-10)

    @Test func categoriesRegisterActionsInFixedOrder() {
        let cats = Dictionary(uniqueKeysWithValues: SystemNotificationCenter.categories().map { ($0.identifier, $0) })
        let proposal = try! #require(cats["proposal"])
        #expect(proposal.actions.map(\.identifier) == ["confirm", "choose", "later"])
        #expect(proposal.actions.map(\.title) == ["Vorschlag übernehmen", "Andere auswählen", "Später"])
        // Bestätigen läuft im Hintergrund ohne Entsperren (P-06), Auswählen öffnet die App.
        #expect(!proposal.actions[0].options.contains(.foreground) && !proposal.actions[0].options.contains(.authenticationRequired))
        #expect(proposal.actions[1].options.contains(.foreground))
        #expect(cats["choose"]?.actions.map(\.title) == ["Ausrüstung wählen", "Später"])
        #expect(cats["maintenance"]?.actions.map(\.title) == ["Prüfen"])
    }

    // MARK: Einplanen

    @Test func openEntryIsScheduledOnceWithPendingAndRevision() async throws {
        let w = try await world()
        await w.coordinator.refresh(now: day(2), requestPermission: false)
        let added = await w.center.added
        #expect(added.count == 1)
        let n = try #require(added.first)
        #expect(n.identifier == NotificationIdentifier.pending(w.pendingID))
        #expect(n.categoryIdentifier == "proposal" && n.threadIdentifier == "inbox")
        #expect(n.userInfo["pendingID"] == w.pendingID.uuidString && n.userInfo["proposalRevision"] == "1")
        #expect(n.title == "Ausrüstung bestätigen")
        #expect(n.body.contains("Rad A"))
        #expect(!n.body.contains("30") && !n.body.contains("km"), "keine Gesundheitswerte im Text: \(n.body)")
        #expect(try await w.p.notificationRecords().map(\.relatedID) == [w.pendingID])

        await w.coordinator.refresh(now: day(2).addingTimeInterval(60), requestPermission: false)
        #expect(await w.center.added.count == 1, "dieselbe Revision wird nicht noch einmal gemeldet")
    }

    @Test func quietHoursMoveDeliveryToTheirEnd() async throws {
        let w = try await world()
        let now = utc.date(bySettingHour: 23, minute: 0, second: 0, of: day(2))!
        _ = try await w.p.apply(.setNotificationPreferences(NotificationPreferences(
            level: .assignmentAndMaintenance, quietHours: QuietHours(startMinute: 22 * 60, endMinute: 7 * 60))), now: now)
        await w.coordinator.refresh(now: now, requestPermission: false)
        let expected = utc.date(bySettingHour: 7, minute: 0, second: 0, of: utc.date(byAdding: .day, value: 1, to: now)!)!
        #expect(await w.center.added.first?.deliverAt == expected)
    }

    @Test func levelOffRemovesWhatWasScheduled() async throws {
        let w = try await world()
        await w.coordinator.refresh(now: day(2), requestPermission: false)
        _ = try await w.p.apply(.setNotificationPreferences(NotificationPreferences(level: .off)), now: day(2))
        await w.coordinator.refresh(now: day(2), requestPermission: false)
        #expect(await w.center.removed.contains(NotificationIdentifier.pending(w.pendingID)))
    }

    @Test func maintenanceIsCheckedOnceWithinTheCooldown() async throws {
        let w = try await world(pending: false, maintenanceRule: true)
        await w.coordinator.refresh(now: day(2), requestPermission: false)
        let first = await w.center.added
        #expect(first.map(\.categoryIdentifier) == ["maintenance"])
        #expect(first.first?.title == "Wartung prüfen")
        #expect(first.first?.body.contains("Rad B") == true)
        #expect(first.first?.userInfo["gearID"] == w.bikeB.id.uuidString)
        await w.center.remove(first.map(\.identifier))      // vom Nutzer weggewischt
        await w.coordinator.refresh(now: day(5), requestPermission: false)
        #expect(await w.center.added.count == 1, "innerhalb von 7 Tagen keine Wiederholung")
        await w.coordinator.refresh(now: day(9), requestPermission: false)
        #expect(await w.center.added.count == 2)
    }

    // MARK: Berechtigung

    @Test func permissionIsAskedOnlyInContextAndAppWorksWithout() async throws {
        let empty = try await world(status: .notDetermined, pending: false)
        await empty.coordinator.refresh(now: day(2), requestPermission: true)
        #expect(await empty.center.requests == 0, "ohne offene Zuordnung oder Wartungsregel keine Anfrage")

        let w = try await world(status: .notDetermined)
        await w.coordinator.refresh(now: day(2), requestPermission: false)
        #expect(await w.center.requests == 0, "im Hintergrund nie fragen")
        await w.center.setGrant(false)
        await w.coordinator.refresh(now: day(2), requestPermission: true)
        #expect(await w.center.requests == 1)
        #expect(await w.center.added.isEmpty, "abgelehnt: nichts wird geplant")
        #expect(try await w.p.notificationRecords().isEmpty)
        // Posteingang bleibt vollständig nutzbar.
        _ = try await w.p.apply(.resolvePending(id: w.pendingID, action: .confirm(proposalRevision: 1), remember: false), now: day(3))
        #expect(try await w.p.dataset().assignments.map(\.gearID) == [w.bikeA.id])
    }

    @Test func noPermissionPromptBeforeOnboardingIsDone() async throws {
        let w = try await world(status: .notDetermined, onboarded: false)
        await w.coordinator.refresh(now: day(2), requestPermission: true)
        #expect(await w.center.requests == 0, "nicht alles beim allerersten Start (SPEC 9)")
    }

    /// Start, Vordergrund, Import und Aktion gleichen oft gleichzeitig ab: trotzdem genau eine Meldung.
    @Test func concurrentRefreshesScheduleOnce() async throws {
        let w = try await world()
        await w.center.setSlow()
        async let a = w.coordinator.refresh(now: day(2), requestPermission: false)
        async let b = w.coordinator.refresh(now: day(2), requestPermission: false)
        async let c = w.coordinator.refresh(now: day(2), requestPermission: false)
        _ = await (a, b, c)
        #expect(await w.center.added.count == 1)
        #expect(try await w.p.notificationRecords().count == 1)
    }

    // MARK: Antworten (T-10 in der App)

    @Test func T10_confirmFromNotificationRunsInboxCommandOnce() async throws {
        let w = try await world()
        await w.coordinator.refresh(now: day(2), requestPermission: false)
        let effect = await w.coordinator.handle(actionIdentifier: "confirm", categoryIdentifier: "proposal", userInfo: info(w), now: day(3))
        #expect(effect == .resolve(pendingID: w.pendingID, action: .confirm(proposalRevision: 1)))
        var d = try await w.p.dataset()
        #expect(d.pendings.first?.state == .resolved && d.pendings.first?.resolution == .confirmedProposal)
        #expect(d.assignments.map(\.gearID) == [w.bikeA.id])
        #expect(d.assignments.first?.origin == .confirmedProposal)
        #expect(try await w.p.ledger().filter { $0.gearID == w.bikeA.id }.count == 1)
        let outbox = try await w.p.outbox(pendingOnly: false)
        #expect(outbox.contains { $0.kind == .pendingChanged && $0.subjectIDs == [w.pendingID] })
        #expect(await w.center.removed.contains(NotificationIdentifier.pending(w.pendingID)), "erledigt: Meldung verschwindet")

        // Doppelt getippt (oder Watch und iPhone): wirkt höchstens einmal.
        await w.coordinator.handle(actionIdentifier: "confirm", categoryIdentifier: "proposal", userInfo: info(w), now: day(3))
        d = try await w.p.dataset()
        #expect(d.assignments.count == 1)
        #expect(try await w.p.ledger().filter { $0.gearID == w.bikeA.id }.count == 1)
        #expect(try await w.p.usage(of: w.bikeA.id).uses == 1)
    }

    @Test func T10_staleRevisionAfterEditIsDiscarded() async throws {
        let w = try await world()
        await w.coordinator.refresh(now: day(2), requestPermission: false)
        _ = try await w.p.apply(.resolvePending(id: w.pendingID, action: .propose(gear: [w.bikeB.id], alternatives: [],
                                                                                   reason: .history, confidence: .medium),
                                                remember: false), now: day(2))
        await w.coordinator.handle(actionIdentifier: "confirm", categoryIdentifier: "proposal", userInfo: info(w, revision: 1), now: day(3))
        let d = try await w.p.dataset()
        #expect(d.assignments.isEmpty, "veraltete Meldung bucht nichts")
        #expect(d.pendings.first?.state == .suggested && d.pendings.first?.proposalRevision == 2)
        // Neue Revision wird neu gemeldet (gleicher Identifier, ersetzt die alte).
        let added = await w.center.added
        #expect(added.count == 2)
        #expect(added.last?.userInfo["proposalRevision"] == "2" && added.last?.body.contains("Rad B") == true)
    }

    @Test func laterKeepsTheEntryAndChooseOpensTheInbox() async throws {
        let w = try await world()
        await w.coordinator.handle(actionIdentifier: "later", categoryIdentifier: "proposal", userInfo: info(w), now: day(3))
        #expect(try await w.p.dataset().pendings.first?.state == .ignored)
        let effect = await w.coordinator.handle(actionIdentifier: "choose", categoryIdentifier: "proposal", userInfo: info(w), now: day(3))
        #expect(effect == .openInbox(pendingID: w.pendingID))
        #expect(try await w.p.dataset().assignments.isEmpty)
    }

    @Test func unknownPendingFromOldNotificationDoesNothing() async throws {
        let w = try await world()
        let stale = NotificationPayload(pendingID: UUID(), proposalRevision: 1).userInfo
        await w.coordinator.handle(actionIdentifier: "confirm", categoryIdentifier: "proposal", userInfo: stale, now: day(3))
        #expect(try await w.p.dataset().assignments.isEmpty)
    }
}

extension RecordingNotificationCenter {
    func setGrant(_ grant: Bool) { grantOnRequest = grant }
}
