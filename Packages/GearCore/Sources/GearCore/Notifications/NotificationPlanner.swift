import Foundation

// M6: Lokale Benachrichtigungen (SPEC 7.2, 7.4; ARCHITEKTUR 6.2; PLATTFORM F-10). Rein: der Kern entscheidet, was
// angezeigt, ersetzt oder entfernt wird; die App übersetzt den Plan nur in `UNUserNotificationCenter`-Aufrufe.
// Der Posteingang bleibt die Wahrheit: eine Benachrichtigung zeigt nur Zustand an und trägt `(pendingID, proposalRevision)`.

/// Ruhezeit als Minuten nach Mitternacht in der lokalen Zeitzone; `start > end` läuft über Mitternacht, `start == end` = keine.
public struct QuietHours: Hashable, Codable, Sendable {
    public var startMinute: Int
    public var endMinute: Int

    public init(startMinute: Int, endMinute: Int) {
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if startMinute == endMinute { return false }
        return startMinute < endMinute ? (m >= startMinute && m < endMinute) : (m >= startMinute || m < endMinute)
    }

    /// Nächstes Ende der Ruhezeit ab `date` (oder `date` selbst, wenn gerade keine Ruhezeit ist).
    public func deliveryDate(for date: Date, calendar: Calendar) -> Date {
        guard contains(date, calendar: calendar) else { return date }
        let endToday = calendar.date(bySettingHour: endMinute / 60, minute: endMinute % 60, second: 0, of: date) ?? date
        return endToday > date ? endToday : calendar.date(byAdding: .day, value: 1, to: endToday) ?? date
    }
}

public struct NotificationPreferences: Hashable, Sendable {
    public var level: NotificationLevel
    public var quietHours: QuietHours?
    /// SPEC 7.4: Wiederholung erst nach Cooldown (Vorgabe 7 Tage).
    public static let maintenanceCooldown: TimeInterval = 7 * 86_400

    public init(level: NotificationLevel = .assignmentAndMaintenance, quietHours: QuietHours? = nil) {
        self.level = level
        self.quietHours = quietHours
    }
}

/// Registrierte Kategorien (`UNNotificationCategory`).
public enum NotificationCategory: String, CaseIterable, Sendable {
    /// Klare Empfehlung: „Vorschlag übernehmen“, „Andere auswählen“, „Später“.
    case proposal
    /// Mehrere gleich plausible Kandidaten: „Ausrüstung wählen“, „Später“ (SPEC 7.2).
    case choose
    /// Sammelmeldung für mehrere offene Zuordnungen; Tippen öffnet den Posteingang.
    case inboxSummary
    /// Wartung „Prüfen“, Deep Link zur Wartung (SPEC 7.4).
    case maintenance
    case maintenanceSummary
}

/// Aktions-IDs (`UNNotificationAction.identifier`). Titel liegen im String Catalog der App.
public enum NotificationAction: String, CaseIterable, Sendable {
    case confirm, choose, later, checkMaintenance

    /// `.foreground` nur, wo ein Bildschirm nötig ist (PLATTFORM C: nicht nur, um die App nach vorn zu holen).
    public var opensApp: Bool { self == .choose || self == .checkMaintenance }
}

public enum NotificationCatalog {
    /// Feste Reihenfolge: bei wenig Platz zeigt das System nur die ersten zwei (PLATTFORM F-10).
    public static func actions(for category: NotificationCategory) -> [NotificationAction] {
        switch category {
        case .proposal: [.confirm, .choose, .later]
        case .choose: [.choose, .later]
        case .inboxSummary, .maintenanceSummary: []
        case .maintenance: [.checkMaintenance]
        }
    }
}

/// Inhalt von `userInfo` (nur Strings, damit er unverändert durch das System läuft).
public struct NotificationPayload: Hashable, Sendable {
    public var pendingID: UUID?
    public var proposalRevision: Int?
    public var activityID: UUID?
    public var gearID: UUID?
    public var count: Int?

    public init(pendingID: UUID? = nil, proposalRevision: Int? = nil, activityID: UUID? = nil, gearID: UUID? = nil, count: Int? = nil) {
        self.pendingID = pendingID
        self.proposalRevision = proposalRevision
        self.activityID = activityID
        self.gearID = gearID
        self.count = count
    }

    public var userInfo: [String: String] {
        var info: [String: String] = [:]
        info["pendingID"] = pendingID?.uuidString
        info["proposalRevision"] = proposalRevision.map(String.init)
        info["activityID"] = activityID?.uuidString
        info["gearID"] = gearID?.uuidString
        info["count"] = count.map(String.init)
        return info
    }

    /// Unlesbare Werte werden `nil` (nie geraten).
    public init(userInfo: [String: String]) {
        pendingID = userInfo["pendingID"].flatMap(UUID.init(uuidString:))
        proposalRevision = userInfo["proposalRevision"].flatMap { Int($0) }
        activityID = userInfo["activityID"].flatMap(UUID.init(uuidString:))
        gearID = userInfo["gearID"].flatMap(UUID.init(uuidString:))
        count = userInfo["count"].flatMap { Int($0) }
    }
}

public struct PlannedNotification: Hashable, Sendable {
    /// Stabil je Gegenstand der Meldung: eine neue Meldung ersetzt die alte, statt zu stapeln.
    public var identifier: String
    public var category: NotificationCategory
    public var threadID: String
    /// Jetzt oder Ende der Ruhezeit.
    public var deliverAt: Date
    public var payload: NotificationPayload
}

/// Gesendete Meldung (`NotificationRecord`, SPEC 5.1): Grundlage für Idempotenz und Cooldown.
public struct SentNotification: Hashable, Codable, Sendable {
    /// Posteingangs-Eintrag oder Wartungsregel (bei Messgrenze ohne Regel: der Gegenstand).
    public var relatedID: UUID
    /// `proposalRevision` bzw. `RuleState.rawValue`.
    public var revision: Int
    public var identifier: String
    public var sentAt: Date

    public init(relatedID: UUID, revision: Int, identifier: String, sentAt: Date) {
        self.relatedID = relatedID
        self.revision = revision
        self.identifier = identifier
        self.sentAt = sentAt
    }
}

public struct NotificationPlan: Equatable, Sendable {
    public var schedule: [PlannedNotification] = []
    /// Identifier, die aus Mitteilungszentrale und Warteschlange verschwinden sollen.
    public var remove: [String] = []
    /// Neu zu speichernde Datensätze (im selben Commit wie nichts anderes: reine Anzeige-Buchführung).
    public var records: [SentNotification] = []

    public init(schedule: [PlannedNotification] = [], remove: [String] = [], records: [SentNotification] = []) {
        self.schedule = schedule
        self.remove = remove
        self.records = records
    }
}

public enum NotificationIdentifier {
    public static let inboxThread = "inbox"
    public static let maintenanceThread = "maintenance"
    public static let inboxSummary = "inbox.summary"
    public static let maintenanceSummary = "maintenance.summary"
    public static func pending(_ id: UUID) -> String { "pending.\(id.uuidString)" }
    public static func maintenance(_ id: UUID) -> String { "maintenance.\(id.uuidString)" }
    /// Alle Identifier, die die App selbst vergibt (fremde bleiben unberührt).
    public static func isOwn(_ identifier: String) -> Bool { isInbox(identifier) || isMaintenance(identifier) }
    static func isInbox(_ identifier: String) -> Bool { identifier == inboxSummary || identifier.hasPrefix("pending.") }
    static func isMaintenance(_ identifier: String) -> Bool { identifier.hasPrefix("maintenance.") }
}

public enum NotificationPlanner {
    public static func plan(open: [PendingAssignment], maintenance: [MaintenanceHint], sent: [SentNotification],
                            existing: Set<String>, preferences: NotificationPreferences, authorized: Bool,
                            now: Date, calendar: Calendar) -> NotificationPlan {
        let own = existing.filter(NotificationIdentifier.isOwn)
        guard authorized, preferences.level != .off else { return NotificationPlan(remove: own.sorted()) }
        let deliverAt = preferences.quietHours?.deliveryDate(for: now, calendar: calendar) ?? now
        var plan = NotificationPlan()
        planInbox(open, sent: sent, existing: own, deliverAt: deliverAt, now: now, into: &plan)
        if preferences.level == .assignmentAndMaintenance {
            planMaintenance(maintenance, sent: sent, existing: own, deliverAt: deliverAt, now: now, into: &plan)
        } else {
            plan.remove += own.filter(NotificationIdentifier.isMaintenance).sorted()
        }
        return plan
    }

    /// Offene Einträge mit etwas zum Bestätigen oder Wählen; „Ohne Ausrüstung“ stört nie (SPEC 6.2).
    private static func notifiable(_ p: PendingAssignment) -> Bool {
        !p.state.isFinal && (!p.proposedGearIDs.isEmpty || !p.candidateGearIDs.isEmpty)
    }

    private static func planInbox(_ open: [PendingAssignment], sent: [SentNotification], existing: Set<String>,
                                  deliverAt: Date, now: Date, into plan: inout NotificationPlan) {
        let eligible = open.filter(notifiable).sorted { $0.id.uuidString < $1.id.uuidString }
        let alreadySent = Set(sent.map { Key(id: $0.relatedID, revision: $0.revision) })
        let fresh = eligible.filter { !alreadySent.contains(Key(id: $0.id, revision: $0.proposalRevision)) }
        let eligibleIdents = Set(eligible.map { NotificationIdentifier.pending($0.id) })
        let summary = eligible.count >= 2

        var remove = existing.filter { $0.hasPrefix("pending.") && (!eligibleIdents.contains($0) || (summary && !fresh.isEmpty)) }
        if !summary, existing.contains(NotificationIdentifier.inboxSummary) { remove.insert(NotificationIdentifier.inboxSummary) }
        plan.remove += remove.sorted()
        guard !fresh.isEmpty else { return }

        if summary {
            plan.schedule.append(PlannedNotification(identifier: NotificationIdentifier.inboxSummary, category: .inboxSummary,
                                                     threadID: NotificationIdentifier.inboxThread, deliverAt: deliverAt,
                                                     payload: NotificationPayload(count: eligible.count)))
            plan.records += fresh.map { SentNotification(relatedID: $0.id, revision: $0.proposalRevision,
                                                          identifier: NotificationIdentifier.inboxSummary, sentAt: now) }
        } else if let p = fresh.first {
            let ident = NotificationIdentifier.pending(p.id)
            let category: NotificationCategory = p.state != .unresolved && !p.proposedGearIDs.isEmpty ? .proposal : .choose
            plan.schedule.append(PlannedNotification(identifier: ident, category: category, threadID: NotificationIdentifier.inboxThread,
                                                     deliverAt: deliverAt,
                                                     payload: NotificationPayload(pendingID: p.id, proposalRevision: p.proposalRevision,
                                                                                  activityID: p.activityID)))
            plan.records.append(SentNotification(relatedID: p.id, revision: p.proposalRevision, identifier: ident, sentAt: now))
        }
    }

    private static func planMaintenance(_ hints: [MaintenanceHint], sent: [SentNotification], existing: Set<String>,
                                        deliverAt: Date, now: Date, into plan: inout NotificationPlan) {
        func key(_ h: MaintenanceHint) -> UUID { h.ruleID ?? h.gearID }
        let due = hints.filter { $0.state == .due }.sorted { key($0).uuidString < key($1).uuidString }
        let lastSent = Dictionary(sent.map { ($0.relatedID, $0.sentAt) }, uniquingKeysWith: max)
        let fresh = due.filter { h in
            lastSent[key(h)].map { now.timeIntervalSince($0) >= NotificationPreferences.maintenanceCooldown } ?? true
        }
        let dueIdents = Set(due.map { NotificationIdentifier.maintenance(key($0)) })
        let summary = fresh.count >= 2
        var remove = existing.filter { NotificationIdentifier.isMaintenance($0) && $0 != NotificationIdentifier.maintenanceSummary
                                       && (!dueIdents.contains($0) || summary) }
        if due.count < 2, existing.contains(NotificationIdentifier.maintenanceSummary) { remove.insert(NotificationIdentifier.maintenanceSummary) }
        plan.remove += remove.sorted()
        guard !fresh.isEmpty else { return }

        let ident = summary ? NotificationIdentifier.maintenanceSummary : NotificationIdentifier.maintenance(key(fresh[0]))
        let payload = summary ? NotificationPayload(count: due.count) : NotificationPayload(gearID: fresh[0].gearID)
        plan.schedule.append(PlannedNotification(identifier: ident, category: summary ? .maintenanceSummary : .maintenance,
                                                 threadID: NotificationIdentifier.maintenanceThread, deliverAt: deliverAt, payload: payload))
        plan.records += fresh.map { SentNotification(relatedID: key($0), revision: $0.state.rawValue, identifier: ident, sentAt: now) }
    }

    private struct Key: Hashable { var id: UUID; var revision: Int }

    /// Fällige Wartung nur aus aktivierten Regeln (SPEC 7.4), Vorwarnung zählt nicht.
    public static func dueMaintenance(rules: [MaintenanceRule], events: [MaintenanceEvent], entries: [UsageLedgerEntry],
                                      installations: [Installation], gear: [GearItem], now: Date) -> [MaintenanceHint] {
        let gearIDs = Set(rules.filter(\.enabled).map(\.gearID))
        let reports = gear.filter { gearIDs.contains($0.id) }.map {
            MaintenanceEvaluator.report(gearID: $0.id, rules: rules, events: events, entries: entries,
                                        installations: installations, gear: gear, now: now)
        }
        return MaintenanceEvaluator.topHints(reports, limit: .max).filter { $0.state == .due }
    }

    /// Kontextbezogene Erstanfrage (SPEC 9, ARCHITEKTUR 6.2): erst bei erster offener Zuordnung oder erster Wartungsregel.
    public static func shouldRequestAuthorization(undetermined: Bool, level: NotificationLevel, openAssignments: Int,
                                                  enabledMaintenanceRules: Int) -> Bool {
        guard undetermined else { return false }
        switch level {
        case .off: return false
        case .assignmentOnly: return openAssignments > 0
        case .assignmentAndMaintenance: return openAssignments > 0 || enabledMaintenanceRules > 0
        }
    }
}

/// Antwort auf eine Benachrichtigung. Die Ausführung lädt den Eintrag neu (Posteingang = Wahrheit); eine veraltete
/// `proposalRevision` endet im Reducer als `staleRevision` ohne Buchung (T-10).
public enum NotificationResponse: Equatable, Sendable {
    case resolve(pendingID: UUID, action: InboxAction)
    case openInbox(pendingID: UUID?)
    case openMaintenance(gearID: UUID)
    case none

    public static let defaultActionIdentifier = "com.apple.UNNotificationDefaultActionIdentifier"
    public static let dismissActionIdentifier = "com.apple.UNNotificationDismissActionIdentifier"

    public static func effect(actionIdentifier: String, categoryIdentifier: String, userInfo: [String: String]) -> NotificationResponse {
        let payload = NotificationPayload(userInfo: userInfo)
        switch NotificationAction(rawValue: actionIdentifier) {
        case .confirm:
            guard let id = payload.pendingID, let revision = payload.proposalRevision else { return .none }
            return .resolve(pendingID: id, action: .confirm(proposalRevision: revision))
        case .later:
            guard let id = payload.pendingID else { return .none }
            return .resolve(pendingID: id, action: .later)
        case .choose:
            return .openInbox(pendingID: payload.pendingID)
        case .checkMaintenance:
            return payload.gearID.map { .openMaintenance(gearID: $0) } ?? .openInbox(pendingID: nil)
        case nil:
            guard actionIdentifier == defaultActionIdentifier else { return .none }
            if let gear = payload.gearID { return .openMaintenance(gearID: gear) }
            if categoryIdentifier == NotificationCategory.maintenanceSummary.rawValue { return .none }
            return .openInbox(pendingID: payload.pendingID)
        }
    }
}
