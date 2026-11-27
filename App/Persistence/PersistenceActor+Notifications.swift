import Foundation
import GearCore
import SwiftData

// M6: Einstellungen und Buchführung der Benachrichtigungen. Die Entscheidung, was gezeigt wird, trifft der Kern
// (`NotificationPlanner`); hier liegen nur Einstellungen (Befehl) und gesendete Meldungen (`NotificationRecord`).

extension PersistenceActor {

    func notificationPreferences() throws -> NotificationPreferences {
        NotificationPreferences()
    }

    func notificationRecords() throws -> [SentNotification] {
        []
    }

    /// Nach dem Einplanen (Seiteneffekt nach Commit): gesendete Meldungen merken, Grundlage für Idempotenz und Cooldown.
    func recordNotifications(_ records: [SentNotification]) throws {
    }

    func setNotificationPreferences(_ preferences: NotificationPreferences, now: Date) throws -> CommandOutcome {
        CommandOutcome()
    }
}
