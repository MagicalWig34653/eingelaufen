import Foundation
import GearCore

// M6: gleicht Posteingang und Wartung mit der Mitteilungszentrale ab (ARCHITEKTUR A-04: nach dem Commit) und führt
// Antworten auf Aktionen über denselben Befehl wie der Posteingang aus (`resolvePending`, Ledger und Outbox in einem Commit).

actor NotificationCoordinator {
    let persistence: PersistenceActor
    let center: any NotificationCenterClient
    private let calendar: Calendar

    init(persistence: PersistenceActor, center: any NotificationCenterClient, calendar: Calendar = .current) {
        self.persistence = persistence
        self.center = center
        self.calendar = calendar
    }

    /// Plan berechnen und anwenden. `requestPermission`: nur im Vordergrund, und nur wenn der Kern den Kontext sieht.
    @discardableResult
    func refresh(now: Date, requestPermission: Bool) async -> NotificationPlan {
        NotificationPlan()
    }

    /// Antwort auf eine Benachrichtigung. Liefert die Wirkung, damit die Oberfläche bei „Andere auswählen“/„Prüfen“
    /// den richtigen Bildschirm öffnet.
    @discardableResult
    func handle(actionIdentifier: String, categoryIdentifier: String, userInfo: [String: String], now: Date) async -> NotificationResponse {
        .none
    }
}

/// Texte der Benachrichtigungen (String Catalog). Keine Gesundheitswerte, nur Sportart, Datum und Ausrüstungsnamen.
enum NotificationTexts {
    static func title(of action: NotificationAction, in category: NotificationCategory) -> String {
        ""
    }

    static func content(for n: PlannedNotification, in dataset: GearDataset) -> (title: String, body: String) {
        ("", "")
    }
}
