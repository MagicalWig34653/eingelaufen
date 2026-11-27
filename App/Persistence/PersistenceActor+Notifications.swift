import Foundation
import GearCore
import SwiftData

// M6: Einstellungen und Buchführung der Benachrichtigungen. Die Entscheidung, was gezeigt wird, trifft der Kern
// (`NotificationPlanner`); hier liegen nur Einstellungen (Befehl) und gesendete Meldungen (`NotificationRecord`).

extension PersistenceActor {

    func notificationPreferences() throws -> NotificationPreferences {
        try fetchAll(AppSettingsEntity.self).first?.notificationPreferences ?? NotificationPreferences()
    }

    func notificationRecords() throws -> [SentNotification] {
        try fetchAll(NotificationRecordEntity.self).map {
            SentNotification(relatedID: $0.pendingID, revision: $0.proposalRevision, identifier: $0.identifier, sentAt: $0.scheduledAt)
        }.sorted { ($0.sentAt, $0.relatedID.uuidString) < ($1.sentAt, $1.relatedID.uuidString) }
    }

    /// Nach dem Einplanen (Seiteneffekt nach Commit): gesendete Meldungen merken, Grundlage für Idempotenz und Cooldown.
    /// `NotificationRecordEntity.pendingID` hält den Bezug (Posteingangs-Eintrag oder Wartungsregel/Gegenstand).
    func recordNotifications(_ records: [SentNotification]) throws {
        guard !records.isEmpty else { return }
        for r in records {
            let row = NotificationRecordEntity()
            row.pendingID = r.relatedID
            row.proposalRevision = r.revision
            row.identifier = r.identifier
            row.scheduledAt = r.sentAt
            modelContext.insert(row)
        }
        try modelContext.save()
    }

    func setNotificationPreferences(_ preferences: NotificationPreferences, now: Date) throws -> CommandOutcome {
        let row = try settingsRow(now: now)
        row.notificationLevelRaw = preferences.level.rawValue
        row.quietHoursEnabled = preferences.quietHours != nil
        if let quiet = preferences.quietHours {
            row.quietStartMinute = quiet.startMinute
            row.quietEndMinute = quiet.endMinute
        }
        try enqueue(.notificationSettingsChanged, [AppSettingsEntity.singletonID], now: now)
        return CommandOutcome()
    }
}
