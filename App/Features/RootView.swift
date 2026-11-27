import SwiftData
import SwiftUI

/// Wurzel: Onboarding bis zum ersten Abschluss, danach drei Haupttabs (SPEC 1.2) mit Einstellungen oben rechts.
struct RootView: View {
    @Query private var settings: [AppSettingsEntity]
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if settings.first?.onboardingCompleted == true {
                MainTabs()
            } else {
                OnboardingView()
            }
        }
        .alert("Hinweis", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

enum AppTab: Hashable { case overview, gear, history }

struct MainTabs: View {
    @State private var selection: AppTab = .overview
    @State private var showSettings = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("Übersicht", systemImage: "square.grid.2x2", value: AppTab.overview) {
                NavigationStack {
                    OverviewView(showSettings: $showSettings)
                        .navigationDestination(for: GearRoute.self) { GearDetailView(gearID: $0.id) }
                        .navigationDestination(for: InboxRoute.self) { _ in InboxView() }
                }
            }
            Tab("Ausrüstung", systemImage: "figure.outdoor.cycle", value: AppTab.gear) {
                NavigationStack { GearListView(showSettings: $showSettings).navigationDestination(for: GearRoute.self) { GearDetailView(gearID: $0.id) } }
            }
            Tab("Verlauf", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                NavigationStack {
                    HistoryView(showSettings: $showSettings)
                        .navigationDestination(for: GearRoute.self) { GearDetailView(gearID: $0.id) }
                        .navigationDestination(for: ActivityRoute.self) { ActivityDetailView(activityID: $0.id) }
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}

/// Einstellungen oben rechts auf jedem Tab, kein vierter Tab (SPEC 1.2).
struct SettingsToolbarButton: ToolbarContent {
    @Binding var showSettings: Bool
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Einstellungen")
                .accessibilityIdentifier("settingsButton")
        }
    }
}
