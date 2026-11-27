import GearCore
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// Einmal je Prozess: Speicher und Modell, gemeinsam für App-Delegate (Hintergrundstart) und Oberfläche.
@MainActor
enum AppEnvironment {
    static let arguments = ProcessInfo.processInfo.arguments

    static func value(of flag: String) -> String? {
        arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }

    static let container: ModelContainer = {
        do {
            // Tests und UI-Tests starten mit -EingelaufenInMemory: nichts berührt den echten Speicher.
            return try Stores.makeContainer(inMemory: arguments.contains("-EingelaufenInMemory"))
        } catch {
            fatalError("Eingelaufen: Speicher kann nicht geöffnet werden: \(error)")
        }
    }()

    static let model: AppModel = {
        #if DEBUG
        // Tests berühren auch HealthKit nie.
        if arguments.contains("-EingelaufenInMemory") {
            return AppModel(container: container, healthSource: DebugHealthSource.scenario(value(of: "-UITestHealth")),
                            notificationCenter: notificationCenter)
        }
        #endif
        return AppModel(container: container)
    }()

    #if DEBUG
    /// UI-Tests: echte Mitteilungszentrale nur mit `-UITestNotifications`, sonst still (keine Systemdialoge in fremden Tests).
    static var notificationCenter: any NotificationCenterClient {
        guard arguments.contains("-EingelaufenInMemory") else { return SystemNotificationCenter() }
        guard arguments.contains("-UITestNotifications") else { return SilentNotificationCenter() }
        return SystemNotificationCenter(testDelay: value(of: "-UITestNotificationDelay").flatMap(TimeInterval.init))
    }
    #else
    static var notificationCenter: any NotificationCenterClient { SystemNotificationCenter() }
    #endif
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Beobachter bei **jedem** Start registrieren, auch wenn HealthKit die App im Hintergrund weckt (F-02).
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Delegate und Kategorien so früh wie möglich, sonst gehen Aktionen verloren (PLATTFORM C).
        UNUserNotificationCenter.current().delegate = self
        SystemNotificationCenter.registerCategories()
        Task { await AppEnvironment.model.startHealth() }
        return true
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        Task { await AppEnvironment.model.retryHealthIfPending() }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Aktion oder Tippen: im Hintergrund (Bestätigen, Später) oder im Vordergrund (Auswählen, Prüfen).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        let action = response.actionIdentifier
        let category = content.categoryIdentifier
        var info: [String: String] = [:]
        for (key, value) in content.userInfo { if let k = key as? String, let v = value as? String { info[k] = v } }
        let model = await MainActor.run { AppEnvironment.model }
        await model.handleNotification(actionIdentifier: action, categoryIdentifier: category, userInfo: info)
    }

    /// Auch bei offener App sichtbar (der Posteingang bleibt die Wahrheit).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

@main
struct EingelaufenApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var ready = false

    var body: some Scene {
        WindowGroup {
            Group {
                if ready { RootView() } else { ProgressView().task { await prepare() } }
            }
            .environment(AppEnvironment.model)
        }
        .modelContainer(AppEnvironment.container)
        // Konsistenzabgleich bei jedem Wechsel in den Vordergrund (SPEC 6.1 Punkt 5).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await AppEnvironment.model.startHealth()
                    // Zeitabhängiges (Wartung nach Kalender, Ende der Ruhezeit) bei jedem Öffnen neu abgleichen.
                    await AppEnvironment.model.refreshNotifications(requestPermission: true)
                }
            }
        }
    }

    private func prepare() async {
        #if DEBUG
        if let fixture = AppEnvironment.value(of: "-UITestFixture") {
            await Fixtures.apply(fixture, to: AppEnvironment.model.persistence)
        }
        #endif
        ready = true
        await AppEnvironment.model.refreshNotifications(requestPermission: true)
    }
}
