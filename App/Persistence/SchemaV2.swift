import Foundation
import GearCore
import SwiftData

/// SchemaV2: wie V1, `AppSettingsEntity` bekommt die Einstellungen für Benachrichtigungen (M6, SPEC 5.1 `reminders`,
/// `quietHours`), `ActivityEntity` merkt sich das Löschen durch den Nutzer (M8). Nur neue Attribute mit Vorgabewert,
/// damit V1 → V2 leichtgewichtig migriert (Build 1 liegt in TestFlight mit V1; V2 ist noch nicht ausgeliefert).
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV1.models.filter { $0 != SchemaV1.AppSettingsEntity.self && $0 != SchemaV1.ActivityEntity.self }
            + [AppSettingsEntity.self, ActivityEntity.self]
    }

    @Model final class ActivityEntity {
        var id = UUID()
        var sourceRaw = ActivitySource.manual.rawValue
        var sourceID: String?
        var sportTypeRaw = 0
        var startAt = Date(timeIntervalSince1970: 0)
        var endAt = Date(timeIntervalSince1970: 0)
        /// `nil` = nicht gemessen (SPEC 5.2).
        var distanceMeters: Double?
        var durationSeconds = 0.0
        var deletedAt: Date?
        var isIndoor: Bool?
        var revision = 1
        // Für den HealthKit-Import (M3); manuelle Aktivitäten lassen sie leer.
        var sourceBundleID: String?
        var sourceName: String?
        var missingInSourceSince: Date?
        /// Neu in V2 (M8): vom Nutzer gelöscht, kein Import holt sie zurück.
        var removedByUser: Bool?

        init() {}
        init(_ a: ActivityRecord) { update(from: a) }

        func update(from a: ActivityRecord) {
            id = a.id
            sourceRaw = a.source.rawValue
            sourceID = a.sourceID
            sportTypeRaw = a.sportType.rawValue
            startAt = a.startAt
            endAt = a.endAt
            distanceMeters = a.distanceMeters
            durationSeconds = a.durationSeconds
            deletedAt = a.deletedAt
            isIndoor = a.isIndoor
            revision = a.revision
            sourceBundleID = a.sourceBundleID
            sourceName = a.sourceName
            removedByUser = a.removedByUser
        }

        var value: ActivityRecord {
            ActivityRecord(id: id, source: ActivitySource(rawValue: sourceRaw) ?? .manual, sourceID: sourceID,
                           sportType: SportType(rawValue: sportTypeRaw), startAt: startAt, endAt: endAt,
                           distanceMeters: distanceMeters, durationSeconds: durationSeconds, deletedAt: deletedAt,
                           isIndoor: isIndoor, revision: revision, sourceBundleID: sourceBundleID, sourceName: sourceName,
                           removedByUser: removedByUser)
        }
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
