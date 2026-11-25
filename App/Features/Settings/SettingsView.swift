import SwiftData
import SwiftUI

/// Einstellungen (SPEC S08), Stand M3: Apple Health mit Import-Status, Datenschutz-Hinweis, Über. Weiteres bis M8.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return v
    }

    var body: some View {
        NavigationStack {
            Form {
                HealthSettingsSection()
                Section("Datenschutz") {
                    Text("Alle Daten bleiben auf diesem Gerät. Kein Konto, kein Server, kein Tracking.")
                }
                Section("Über Eingelaufen") {
                    LabeledContent("Version", value: version)
                }
            }
            .healthErrorAlert()
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() }.accessibilityIdentifier("settingsDone") }
            }
        }
    }
}
