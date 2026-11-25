import Foundation
import GearCore

/// Texte zum Import (SPEC 6.1/11, PLATTFORM F-04): neutral, nie eine Aussage darüber, was in Health erlaubt ist.
enum HealthTexts {
    static func window(_ window: ImportWindow) -> String {
        switch window {
        case .days30: String(localized: "Letzte 30 Tage")
        case .days90: String(localized: "Letzte 90 Tage")
        case .days365: String(localized: "Letzte 365 Tage")
        case .all: String(localized: "Alle verfügbaren")
        }
    }

    static func title(_ status: ImportStatus) -> String {
        switch status {
        case .notConnected: String(localized: "Nicht verbunden")
        case .waiting: String(localized: "Abgleich steht aus")
        case .pendingUnlock: String(localized: "Import ausstehend")
        case .noWorkoutsVisible: String(localized: "Keine Trainings sichtbar")
        case .upToDate: String(localized: "Abgeglichen")
        case .failed(.unavailable): String(localized: "Health nicht verfügbar")
        case .failed: String(localized: "Abgleich fehlgeschlagen")
        }
    }

    static func hint(_ status: ImportStatus) -> String? {
        switch status {
        case .notConnected, .waiting, .upToDate:
            nil
        case .pendingUnlock:
            String(localized: "Das Gerät war gesperrt. Der Abgleich wird nach dem Entsperren oder beim nächsten Öffnen nachgeholt.")
        case .noWorkoutsVisible:
            String(localized: "Prüfe in der Health-App, ob Eingelaufen Trainings lesen darf. Vielleicht gibt es im gewählten Zeitraum auch noch keine.")
        case .failed(.unavailable):
            String(localized: "Auf diesem Gerät gibt es kein Apple Health. Aktivitäten kannst du von Hand eintragen.")
        case .failed(.storeError):
            String(localized: "Die Trainings konnten nicht gespeichert werden. Es geht nichts verloren, der Abgleich wird wiederholt.")
        case .failed:
            String(localized: "Health hat nicht geantwortet. Der Abgleich wird beim nächsten Öffnen wiederholt.")
        }
    }
}
