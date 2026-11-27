import GearCore
import SwiftData
import SwiftUI

/// Einstellungen › Mitteilungen (SPEC 7.2, US-08): Stufe, Ruhezeiten, Hinweis auf die Systemerlaubnis.
/// Ohne Erlaubnis bleibt alles bedienbar; der Posteingang ist die Wahrheit.
struct NotificationSettingsSection: View {
    @Query private var settings: [AppSettingsEntity]
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization: NotificationAuthorization?

    private var preferences: NotificationPreferences { settings.first?.notificationPreferences ?? NotificationPreferences() }
    private var startMinute: Int { settings.first?.quietStartMinute ?? 22 * 60 }
    private var endMinute: Int { settings.first?.quietEndMinute ?? 7 * 60 }

    var body: some View {
        Section {
            Picker("Erinnern an", selection: Binding(get: { preferences.level }, set: { save(level: $0) })) {
                Text("Aus").tag(NotificationLevel.off)
                Text("Nur Zuordnung").tag(NotificationLevel.assignmentOnly)
                Text("Zuordnung und Wartung").tag(NotificationLevel.assignmentAndMaintenance)
            }
            .accessibilityIdentifier("notificationLevel")

            if preferences.level != .off {
                Toggle("Ruhezeit", isOn: Binding(get: { preferences.quietHours != nil }, set: { save(quiet: $0) }))
                    .accessibilityIdentifier("quietHoursToggle")
                if preferences.quietHours != nil {
                    DatePicker("Von", selection: time(\.startMinute), displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("quietHoursStart")
                    DatePicker("Bis", selection: time(\.endMinute), displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("quietHoursEnd")
                }
            }
            if let authorization {
                Label(statusText(authorization), systemImage: authorization == .authorized ? "bell" : "bell.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("notificationStatus")
            }
        } header: {
            Text("Mitteilungen")
        } footer: {
            Text("In der Ruhezeit bleibt es still, Hinweise kommen danach. Mehrere offene Zuordnungen kommen als eine Mitteilung, an Wartung wird höchstens alle 7 Tage erinnert.")
        }
        .task(id: scenePhase) { authorization = await model.notificationAuthorization() }
    }

    private func statusText(_ a: NotificationAuthorization) -> LocalizedStringKey {
        switch a {
        case .authorized: "Mitteilungen sind erlaubt."
        case .notDetermined: "Eingelaufen fragt, sobald es etwas zuzuordnen oder zu prüfen gibt."
        case .denied: "Mitteilungen sind in den iOS-Einstellungen aus. Offene Zuordnungen findest du immer in der Übersicht."
        }
    }

    private struct Minutes { var startMinute: Int; var endMinute: Int }

    /// Uhrzeit-Auswahl auf Minuten nach Mitternacht abgebildet (lokale Zeitzone).
    private func time(_ key: WritableKeyPath<Minutes, Int>) -> Binding<Date> {
        Binding(get: {
            let m = Minutes(startMinute: startMinute, endMinute: endMinute)[keyPath: key]
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            var m = Minutes(startMinute: startMinute, endMinute: endMinute)
            m[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            run(NotificationPreferences(level: preferences.level, quietHours: QuietHours(startMinute: m.startMinute, endMinute: m.endMinute)))
        })
    }

    private func save(level: NotificationLevel) {
        run(NotificationPreferences(level: level, quietHours: preferences.quietHours))
    }

    private func save(quiet: Bool) {
        run(NotificationPreferences(level: preferences.level,
                                    quietHours: quiet ? QuietHours(startMinute: startMinute, endMinute: endMinute) : nil))
    }

    private func run(_ prefs: NotificationPreferences) {
        Task { await model.run(.setNotificationPreferences(prefs)) }
    }
}
