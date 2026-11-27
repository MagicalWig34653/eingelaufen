import Foundation
import GearCore
import SwiftData

/// SchemaV2 (M6): wie V1, `AppSettingsEntity` bekommt die Einstellungen für Benachrichtigungen (SPEC 5.1 `reminders`,
/// `quietHours`). Nur neue Attribute mit Vorgabewert, damit V1 → V2 leichtgewichtig migriert (Build 1 liegt in TestFlight).
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV1.models.filter { $0 != SchemaV1.AppSettingsEntity.self } + [AppSettingsEntity.self]
    }

    /// Genau eine Zeile (feste ID). Nutzereinstellungen, die nicht im Kern liegen.
    @Model final class AppSettingsEntity {
        static let singletonID = SchemaV1.AppSettingsEntity.singletonID
        var id = AppSettingsEntity.singletonID
        var onboardingCompleted = false
        var healthChoiceRaw = HealthChoice.undecided.rawValue
        /// Zeitraum des Erstimports in Tagen (M3); `nil` = noch nicht gewählt, 0 = alle verfügbaren.
        var importWindowDays: Int?
        /// Fester Beginn dieses Zeitraums (SPEC 5.1 `healthImportStartAt`); `nil` bei „alle“.
        var healthImportStartAt: Date?
        var createdAt = Date(timeIntervalSince1970: 0)
        // M6: Benachrichtigungen (SPEC 7.2). Vorgabe „Zuordnung und Wartung“, Ruhezeit 22–7 Uhr vorbelegt, aber aus.
        var notificationLevelRaw = NotificationLevel.assignmentAndMaintenance.rawValue
        var quietHoursEnabled = false
        var quietStartMinute = 22 * 60
        var quietEndMinute = 7 * 60

        init() {}

        var notificationPreferences: NotificationPreferences {
            NotificationPreferences(level: NotificationLevel(rawValue: notificationLevelRaw) ?? .assignmentAndMaintenance,
                                    quietHours: quietHoursEnabled ? QuietHours(startMinute: quietStartMinute, endMinute: quietEndMinute) : nil)
        }
    }
}
