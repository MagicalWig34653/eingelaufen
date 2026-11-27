import SwiftData
import SwiftUI

/// Einstellungen (SPEC S08), Stand M8: Apple Health mit Import-Status, Zuordnung, Mitteilungen, Daten (Backup, Löschen), Datenschutz-Hinweis, Über.
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
                AssignmentSettingsSection()
                NotificationSettingsSection()
                DataSettingsSection()
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
