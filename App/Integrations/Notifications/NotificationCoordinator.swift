import Foundation
import GearCore

// M6: gleicht Posteingang und Wartung mit der Mitteilungszentrale ab (ARCHITEKTUR A-04: nach dem Commit) und führt
// Antworten auf Aktionen über denselben Befehl wie der Posteingang aus (`resolvePending`, Ledger und Outbox in einem Commit).

actor NotificationCoordinator {
    let persistence: PersistenceActor
    let center: any NotificationCenterClient
    private let calendar: Calendar
    private var last: Task<NotificationPlan, Never>?

    init(persistence: PersistenceActor, center: any NotificationCenterClient, calendar: Calendar = .current) {
        self.persistence = persistence
        self.center = center
        self.calendar = calendar
    }

    /// Plan berechnen und anwenden. `requestPermission`: nur aus der Oberfläche, und nur wenn der Kern den Kontext sieht.
    /// Abgleiche laufen nacheinander (wie beim Import): sonst sähen zwei denselben Stand und meldeten doppelt.
    @discardableResult
    func refresh(now: Date, requestPermission: Bool) async -> NotificationPlan {
        let previous = last
        let task = Task {
            _ = await previous?.value
            return await self.runOnce(now: now, requestPermission: requestPermission)
        }
        last = task
        return await task.value
    }

    private func runOnce(now: Date, requestPermission: Bool) async -> NotificationPlan {
        guard let dataset = try? await persistence.dataset(), let ledger = try? await persistence.ledger(),
              let preferences = try? await persistence.notificationPreferences(),
              let settings = try? await persistence.settings(),
              let records = try? await persistence.notificationRecords() else { return NotificationPlan() }
        let sent = NotificationPlanner.stillCounting(records, rules: dataset.maintenanceRules, events: dataset.maintenanceEvents)
        let open = InboxQuery.open(in: dataset).map(\.pending)
        let maintenance = NotificationPlanner.dueMaintenance(rules: dataset.maintenanceRules, events: dataset.maintenanceEvents,
                                                             entries: ledger, installations: dataset.installations,
                                                             gear: dataset.gear, now: now)
        var status = await center.authorization()
        // Erst nach dem Onboarding (SPEC 9: nicht alles beim allerersten Start).
        if requestPermission, settings.onboardingCompleted, NotificationPlanner.shouldRequestAuthorization(
            undetermined: status == .notDetermined, level: preferences.level, openAssignments: open.count,
            enabledMaintenanceRules: dataset.maintenanceRules.filter(\.enabled).count) {
            status = await center.requestAuthorization() ? .authorized : .denied
        }
        let plan = NotificationPlanner.plan(open: open, maintenance: maintenance, sent: sent, existing: await center.identifiers(),
                                            preferences: preferences, authorized: status == .authorized, now: now, calendar: calendar)
        await center.remove(plan.remove)
        var scheduled = Set<String>()
        for n in plan.schedule {
            let text = NotificationTexts.content(for: n, in: dataset, calendar: calendar)
            let request = NotificationRequestValue(identifier: n.identifier, categoryIdentifier: n.category.rawValue,
                                                   threadIdentifier: n.threadID, title: text.title, body: text.body,
                                                   userInfo: n.payload.userInfo, deliverAt: n.deliverAt > now ? n.deliverAt : nil)
            if (try? await center.add(request)) != nil { scheduled.insert(n.identifier) }
        }
        // Nur wirklich eingeplante Meldungen gelten als gesendet; sonst versucht es der nächste Abgleich erneut.
        try? await persistence.recordNotifications(plan.records.filter { scheduled.contains($0.identifier) })
        return plan
    }

    /// Antwort auf eine Benachrichtigung. Liefert die Wirkung, damit die Oberfläche bei „Andere auswählen“/„Prüfen“
    /// den richtigen Bildschirm öffnet.
    @discardableResult
    func handle(actionIdentifier: String, categoryIdentifier: String, userInfo: [String: String], now: Date) async -> NotificationResponse {
        let effect = NotificationResponse.effect(actionIdentifier: actionIdentifier, categoryIdentifier: categoryIdentifier, userInfo: userInfo)
        if case let .resolve(pendingID, action) = effect {
            // Derselbe Befehl wie im Posteingang: Eintrag neu laden, reduzieren, ein Commit (A-03). Erledigt oder veraltet
            // → keine Buchung (T-10). Unbekannter Eintrag (alte Meldung) → nichts.
            _ = try? await persistence.apply(.resolvePending(id: pendingID, action: action, remember: false), now: now)
            _ = await OutboxDispatcher(persistence: persistence).deliver(to: NoSideEffects(), now: now)
            await refresh(now: now, requestPermission: false)
        }
        return effect
    }
}

/// Texte der Benachrichtigungen (String Catalog). Keine Gesundheitswerte, nur Sportart, Datum und Ausrüstungsnamen.
enum NotificationTexts {
    static func title(of action: NotificationAction, in category: NotificationCategory) -> String {
        switch action {
        case .confirm: DisplayNames.string("notification.action.confirm")
        // Ohne klare Empfehlung heißt dieselbe Aktion „Ausrüstung wählen“ (SPEC 7.2).
        case .choose: DisplayNames.string(category == .choose ? "notification.action.chooseGear" : "notification.action.choose")
        case .later: DisplayNames.string("notification.action.later")
        case .checkMaintenance: DisplayNames.string("notification.action.check")
        }
    }

    static func content(for n: PlannedNotification, in dataset: GearDataset, calendar: Calendar) -> (title: String, body: String) {
        func s(_ key: String) -> String { DisplayNames.string(key) }
        func gearName(_ id: UUID?) -> String { dataset.gear.first { $0.id == id }?.name ?? "" }
        let activity = dataset.activities.first { $0.id == n.payload.activityID }
        let sport = activity.map { DisplayNames.name(for: SportCatalog.category(for: $0.sportType)) } ?? ""
        let date = activity.map { $0.startAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: calendar.timeZone)) } ?? ""
        switch n.category {
        case .proposal:
            let pending = dataset.pendings.first { $0.id == n.payload.pendingID }
            let names = (pending?.proposedGearIDs ?? []).map(gearName).joined(separator: ", ")
            return (s("notification.proposal.title"), String(format: s("notification.proposal.body"), sport, date, names))
        case .choose:
            return (s("notification.choose.title"), String(format: s("notification.choose.body"), sport, date))
        case .inboxSummary:
            return (s("notification.inboxSummary.title"), String(format: s("notification.inboxSummary.body"), n.payload.count ?? 0))
        case .maintenance:
            return (s("notification.maintenance.title"), String(format: s("notification.maintenance.body"), gearName(n.payload.gearID)))
        case .maintenanceSummary:
            return (s("notification.maintenance.title"), String(format: s("notification.maintenanceSummary.body"), n.payload.count ?? 0))
        }
    }
}
