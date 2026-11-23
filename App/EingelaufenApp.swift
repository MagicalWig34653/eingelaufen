import SwiftData
import SwiftUI

@main
struct EingelaufenApp: App {
    private let container: ModelContainer
    @State private var model: AppModel
    @State private var ready = false
    private let fixture: String?

    init() {
        let args = ProcessInfo.processInfo.arguments
        // Tests und UI-Tests starten mit -EingelaufenInMemory: nichts berührt den echten Speicher.
        let inMemory = args.contains("-EingelaufenInMemory")
        do {
            container = try Stores.makeContainer(inMemory: inMemory)
        } catch {
            fatalError("Eingelaufen: Speicher kann nicht geöffnet werden: \(error)")
        }
        _model = State(initialValue: AppModel(container: container))
        #if DEBUG
        fixture = args.firstIndex(of: "-UITestFixture").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        #else
        fixture = nil
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if ready { RootView() } else { ProgressView().task { await prepare() } }
            }
            .environment(model)
        }
        .modelContainer(container)
    }

    private func prepare() async {
        #if DEBUG
        if let fixture { await Fixtures.apply(fixture, to: model.persistence) }
        #endif
        ready = true
    }
}
