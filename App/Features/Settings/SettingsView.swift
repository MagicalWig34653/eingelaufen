import SwiftData
import SwiftUI

/// Einstellungen (SPEC S08), Stand M2: Datenschutz-Hinweis, Health-Status, Über. Weitere Abschnitte kommen mit M3 bis M8.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [AppSettingsEntity]

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return v
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Health") {
                    LabeledContent("Status", value: "Nicht verbunden")
                    Text("Die Verbindung richtest du in einer späteren Version ein. Bis dahin trägst du Aktivitäten von Hand ein.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Datenschutz") {
                    Text("Alle Daten bleiben auf diesem Gerät. Kein Konto, kein Server, kein Tracking.")
                }
                Section("Über Eingelaufen") {
                    LabeledContent("Version", value: version)
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() }.accessibilityIdentifier("settingsDone") }
            }
        }
    }
}
