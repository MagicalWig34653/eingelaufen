import GearCore
import SwiftData
import SwiftUI

/// Einstellungen > Apple Health (SPEC S08, ARCHITEKTUR 8): verbinden, Zeitraum, Import-Status, jetzt abgleichen.
struct HealthSettingsSection: View {
    @Environment(AppModel.self) private var model
    @Query private var settings: [AppSettingsEntity]
    @Query private var cursors: [ImportCursorEntity]
    @Query(filter: #Predicate<ActivityEntity> { $0.sourceRaw == "healthKit" && $0.deletedAt == nil })
    private var imported: [ActivityEntity]
    @State private var chosen = ImportWindow.standard
    @State private var busy = false

    private var isConnected: Bool { settings.first?.healthChoiceRaw == HealthChoice.connected.rawValue }

    private var window: ImportWindow {
        guard isConnected, let days = settings.first?.importWindowDays else { return chosen }
        return ImportWindow(days: days == 0 ? nil : days)
    }

    private var status: ImportStatus {
        let cursor = cursors.first
        let state = ImportState(isEnabled: isConnected, lastSuccessAt: cursor?.lastSuccessAt,
                                lastFailure: cursor?.lastError.flatMap(ImportFailure.init(rawValue:)))
        return ImportStatus.evaluate(state, workoutCount: imported.count)
    }

    var body: some View {
        Section {
            LabeledContent("Status", value: HealthTexts.title(status))
                .accessibilityIdentifier("healthStatus")
            if let hint = HealthTexts.hint(status) {
                Text(hint).font(.footnote).foregroundStyle(.secondary)
            }
            if isConnected {
                LabeledContent("Letzter Abgleich",
                               value: cursors.first?.lastSuccessAt?.formatted(date: .abbreviated, time: .shortened)
                                   ?? String(localized: "Noch keiner"))
                LabeledContent("Importierte Trainings", value: "\(imported.count)")
            }
            Picker("Zeitraum", selection: Binding(get: { window }, set: { select($0) })) {
                ForEach(ImportWindow.allCases, id: \.self) { Text(HealthTexts.window($0)).tag($0) }
            }
            .disabled(busy)
            .accessibilityIdentifier("healthWindow")
            if isConnected {
                Button("Jetzt abgleichen") { perform { await model.syncHealth() } }
                    .disabled(busy).accessibilityIdentifier("healthSync")
            } else {
                Button("Mit Apple Health verbinden") { perform { await model.connectHealth(chosen) } }
                    .disabled(busy).accessibilityIdentifier("healthConnect")
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text("Eingelaufen liest nur Trainings und schreibt nichts nach Health. Wann neue Trainings im Hintergrund ankommen, entscheidet iOS.")
        }
    }

    private func select(_ new: ImportWindow) {
        chosen = new
        if isConnected && new != window { perform { await model.connectHealth(new) } }
    }

    private func perform(_ work: @escaping @MainActor () async -> some Sendable) {
        busy = true
        Task {
            _ = await work()
            busy = false
        }
    }
}
