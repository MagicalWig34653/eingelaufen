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
        []
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

    public var userInfo: [String: String] { [:] }

    public init(userInfo: [String: String]) {}
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
    public static func isOwn(_ identifier: String) -> Bool { false }
}

public enum NotificationPlanner {
    public static func plan(open: [PendingAssignment], maintenance: [MaintenanceHint], sent: [SentNotification],
                            existing: Set<String>, preferences: NotificationPreferences, authorized: Bool,
                            now: Date, calendar: Calendar) -> NotificationPlan {
        NotificationPlan()
    }

    /// Fällige Wartung nur aus aktivierten Regeln (SPEC 7.4), Vorwarnung zählt nicht.
    public static func dueMaintenance(rules: [MaintenanceRule], events: [MaintenanceEvent], entries: [UsageLedgerEntry],
                                      installations: [Installation], gear: [GearItem], now: Date) -> [MaintenanceHint] {
        []
    }

    /// Kontextbezogene Erstanfrage (SPEC 9, ARCHITEKTUR 6.2): erst bei erster offener Zuordnung oder erster Wartungsregel.
    public static func shouldRequestAuthorization(undetermined: Bool, level: NotificationLevel, openAssignments: Int,
                                                  enabledMaintenanceRules: Int) -> Bool {
        false
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
        .none
    }
}
