import GearCore
import SwiftData
import SwiftUI
import UIKit

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
            return AppModel(container: container, healthSource: DebugHealthSource.scenario(value(of: "-UITestHealth")))
        }
        #endif
        return AppModel(container: container)
    }()
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Beobachter bei **jedem** Start registrieren, auch wenn HealthKit die App im Hintergrund weckt (F-02).
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task { await AppEnvironment.model.startHealth() }
        return true
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        Task { await AppEnvironment.model.retryHealthIfPending() }
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
            if phase == .active { Task { await AppEnvironment.model.startHealth() } }
        }
    }

    private func prepare() async {
        #if DEBUG
        if let fixture = AppEnvironment.value(of: "-UITestFixture") {
            await Fixtures.apply(fixture, to: AppEnvironment.model.persistence)
        }
        #endif
        ready = true
    }
}
