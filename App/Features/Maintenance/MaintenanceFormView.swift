import GearCore
import SwiftUI

/// Wartung mit Eingaben (SPEC S07): Datum, Messwert, Kosten, Notiz. Messen braucht den Wert, „Eigene Wartung“ eine Bezeichnung.
struct MaintenanceFormView: View {
    let gearID: UUID
    let kind: MaintenanceKind
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var measurementText = ""
    @State private var costText = ""
    @State private var notes = ""
    @State private var saving = false
    @FocusState private var numberFocused: Bool

    private var measurement: Double?? {
        let t = measurementText.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return .some(nil) }
        guard let v = ManualActivityView.number(t), v >= 0 else { return nil }
        return .some(v)
    }
    private var costMinor: Int?? {
        let t = costText.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return .some(nil) }
        guard let v = ManualActivityView.number(t), v >= 0 else { return nil }
        return .some(Int((v * 100).rounded()))
    }
    private var canSave: Bool {
        guard let m = measurement, costMinor != nil, !saving else { return false }
        if kind == .wearMeasured, m == nil { return false }
        if kind == .custom, notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Datum", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    TextField(kind == .wearMeasured ? "Messwert" : "Messwert (optional)", text: $measurementText)
                        .keyboardType(.decimalPad).focused($numberFocused)
                        .accessibilityIdentifier("maintenanceMeasurement")
                    TextField("Kosten in € (optional)", text: $costText)
                        .keyboardType(.decimalPad).focused($numberFocused)
                        .accessibilityIdentifier("maintenanceCost")
                    TextField(kind == .custom ? "Bezeichnung" : "Notiz (optional)", text: $notes, axis: .vertical)
                        .accessibilityIdentifier("maintenanceNotes")
                } footer: {
                    if kind == .wearMeasured { Text("Die Einheit legst du selbst fest, zum Beispiel Prozent Kettenlängung.") }
                }
            }
            .navigationTitle(DisplayNames.name(for: kind))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.accessibilityIdentifier("maintenanceCancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }.disabled(!canSave).accessibilityIdentifier("maintenanceSave")
                }
            }
            .keyboardDoneButton($numberFocused)
        }
    }

    private func save() {
        guard let m = measurement, let c = costMinor else { return }
        saving = true
        let input = MaintenanceInput(gearID: gearID, kind: kind, performedAt: date, measurement: m, costMinor: c,
                                     notes: notes.isEmpty ? nil : notes)
        Task { if await model.run(.recordMaintenance(input)) != nil { dismiss() } else { saving = false } }
    }
}

/// Wartungsregel anlegen oder ändern (SPEC 8.3). Vorlagenwerte wären Startwerte, hier trägt der Nutzer selbst ein.
struct RuleFormView: View {
    let gearID: UUID
    let editing: MaintenanceRule?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind: MaintenanceKind = .cleaned
    @State private var metric: UsageMetricKind = .distance
    @State private var intervalText = ""
    @State private var leadText = ""
    @State private var enabled = true
    @State private var loaded = false
    @FocusState private var numberFocused: Bool

    private static let kinds: [MaintenanceKind] = [.cleaned, .lubricated, .inspected, .repaired, .wearMeasured]
    private var isLimit: Bool { kind == .wearMeasured }

    /// Eingabe in Anzeigeeinheit → Basiseinheit (A-08): km → m, Stunden → s.
    private var factor: Double {
        if isLimit { return 1 }
        switch metric { case .distance: return 1_000; case .duration: return 3_600; default: return 1 }
    }
    private var unitLabel: String {
        if isLimit { return "" }
        switch metric { case .distance: return "km"; case .duration: return "Stunden"; case .uses: return "Nutzungen"; case .calendarAge: return "Tage" }
    }
    private var interval: Double? { ManualActivityView.number(intervalText).flatMap { $0 > 0 ? $0 * factor : nil } }
    private var lead: Double?? {
        let t = leadText.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return .some(nil) }
        guard let v = ManualActivityView.number(t), v >= 0 else { return nil }
        return .some(v * factor)
    }
    private var canSave: Bool {
        guard let i = interval, let l = lead else { return false }
        return isLimit || (l ?? 0) <= i
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Art", selection: $kind) {
                        ForEach(Self.kinds, id: \.self) { k in
                            Text(k == .wearMeasured ? String(localized: "Messgrenze") : DisplayNames.name(for: k)).tag(k)
                        }
                    }
                    .accessibilityIdentifier("ruleKind")
                    if !isLimit {
                        Picker("Messgröße", selection: $metric) {
                            Text("Distanz").tag(UsageMetricKind.distance)
                            Text("Dauer").tag(UsageMetricKind.duration)
                            Text("Anzahl").tag(UsageMetricKind.uses)
                            Text("Kalender").tag(UsageMetricKind.calendarAge)
                        }
                        .accessibilityIdentifier("ruleMetric")
                    }
                    TextField(isLimit ? "Grenzwert" : "Intervall (\(unitLabel))", text: $intervalText)
                        .keyboardType(.decimalPad).focused($numberFocused)
                        .accessibilityIdentifier("ruleInterval")
                    if !isLimit {
                        TextField("Vorwarnung (\(unitLabel), optional)", text: $leadText)
                            .keyboardType(.decimalPad).focused($numberFocused)
                            .accessibilityIdentifier("ruleLead")
                    }
                    Toggle("Regel aktiv", isOn: $enabled).accessibilityIdentifier("ruleEnabled")
                } footer: {
                    Text("Ein Intervall ist ein Hinweis zum Prüfen, keine Aussage über den tatsächlichen Verschleiß.")
                }
                if let editing {
                    Section {
                        Button("Regel löschen", role: .destructive) {
                            Task { if await model.run(.removeMaintenanceRule(editing.id)) != nil { dismiss() } }
                        }
                        .accessibilityIdentifier("ruleDelete")
                    }
                }
            }
            .navigationTitle(editing == nil ? "Neue Regel" : "Regel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.accessibilityIdentifier("ruleCancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }.disabled(!canSave).accessibilityIdentifier("ruleSave")
                }
            }
            .keyboardDoneButton($numberFocused)
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded, let r = editing else { return }
        loaded = true
        kind = r.kind
        metric = r.metric
        enabled = r.enabled
        let f = r.kind == .wearMeasured ? 1 : (r.metric == .distance ? 1_000.0 : r.metric == .duration ? 3_600.0 : 1)
        intervalText = DisplayNames.number(r.intervalValue / f)
        leadText = r.warningLeadValue.map { DisplayNames.number($0 / f) } ?? ""
    }

    private func save() {
        guard let i = interval, let l = lead else { return }
        let rule = MaintenanceRule(id: editing?.id ?? UUID(), gearID: gearID, kind: kind, metric: isLimit ? .distance : metric,
                                   intervalValue: i, warningLeadValue: isLimit ? nil : l, enabled: enabled)
        Task { if await model.run(.setMaintenanceRule(rule)) != nil { dismiss() } }
    }
}
