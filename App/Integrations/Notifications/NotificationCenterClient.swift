import Foundation
import GearCore
import UserNotifications

// M6: dünne Hülle um `UNUserNotificationCenter`, damit App-Tests den Koordinator ohne Systemdialog prüfen können.

enum NotificationAuthorization: Sendable, Equatable {
    case notDetermined, denied, authorized
}

/// Fertige Anfrage: Texte aus dem String Catalog, `userInfo` aus dem Kern-Payload.
struct NotificationRequestValue: Sendable, Equatable {
    var identifier: String
    var categoryIdentifier: String
    var threadIdentifier: String
    var title: String
    var body: String
    var userInfo: [String: String]
    /// `nil` = sofort.
    var deliverAt: Date?
}

protocol NotificationCenterClient: Sendable {
    func authorization() async -> NotificationAuthorization
    /// Systemdialog; `true`, wenn Mitteilungen erlaubt wurden.
    func requestAuthorization() async -> Bool
    /// Eigene geplante und zugestellte Meldungen.
    func identifiers() async -> Set<String>
    func add(_ request: NotificationRequestValue) async throws
    func remove(_ identifiers: [String]) async
}

/// Echte Mitteilungszentrale.
struct SystemNotificationCenter: NotificationCenterClient {
    /// Nur UI-Tests (DEBUG): Zustellung um so viele Sekunden verzögern, damit der Test zum Home-Bildschirm wechseln kann.
    var testDelay: TimeInterval?

    private var center: UNUserNotificationCenter { .current() }

    func authorization() async -> NotificationAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        // Provisional liefert nur still ins Mitteilungszentrum: für Rückfragen nicht ausreichend (PLATTFORM C).
        case .authorized, .ephemeral: .authorized
        default: .denied
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func identifiers() async -> Set<String> {
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        return Set(pending + delivered).filter(NotificationIdentifier.isOwn)
    }

    func add(_ request: NotificationRequestValue) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.categoryIdentifier = request.categoryIdentifier
        content.threadIdentifier = request.threadIdentifier
        content.userInfo = request.userInfo
        content.sound = .default
        let trigger: UNNotificationTrigger?
        if let testDelay {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: testDelay, repeats: false)
        } else if let at = request.deliverAt, at.timeIntervalSinceNow > 1 {
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: at)
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        } else {
            trigger = nil
        }
        // Gleicher Identifier ersetzt die frühere Meldung (ersetzen statt stapeln).
        try await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
    }

    func remove(_ identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// Kategorien müssen beim Start registriert sein (PLATTFORM C), Reihenfolge aus dem Kern (F-10).
    static func registerCategories() {
        UNUserNotificationCenter.current().setNotificationCategories(categories())
    }

    static func categories() -> Set<UNNotificationCategory> {
        Set(NotificationCategory.allCases.map { category in
            let actions = NotificationCatalog.actions(for: category).map { action in
                UNNotificationAction(identifier: action.rawValue, title: NotificationTexts.title(of: action, in: category),
                                     options: action.opensApp ? [.foreground] : [])
            }
            return UNNotificationCategory(identifier: category.rawValue, actions: actions, intentIdentifiers: [],
                                          options: [])
        })
    }
}

/// Tests und UI-Tests ohne `-UITestNotifications`: keine Systemdialoge, nichts wird angezeigt (wie „nicht erlaubt“).
struct SilentNotificationCenter: NotificationCenterClient {
    func authorization() async -> NotificationAuthorization { .denied }
    func requestAuthorization() async -> Bool { false }
    func identifiers() async -> Set<String> { [] }
    func add(_ request: NotificationRequestValue) async throws {}
    func remove(_ identifiers: [String]) async {}
}
