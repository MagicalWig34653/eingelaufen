import GearCore
import SwiftData
import SwiftUI

/// Manuelle Aktivität (SPEC 6.4): Sportart, Beginn, Dauer, optional Distanz und Ausrüstung. Ohne HealthKit nutzbar.
struct ManualActivityView: View {
    let preselectedGearID: UUID?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GearEntity.name) private var allGear: [GearEntity]
    @State private var category: SportCategory = .cycling
    @State private var startAt = Date()
    @State private var minutesText = ""
    @State private var distanceText = ""
    @State private var selected: Set<UUID> = []
    @State private var saving = false
    @State private var didPreselect = false
    @FocusState private var numberFocused: Bool

    private var candidates: [GearEntity] {
        allGear.filter { $0.statusRaw == GearStatus.active.rawValue || $0.statusRaw == GearStatus.stored.rawValue }
            .sorted { a, b in
                let ma = a.categoryRaw == category.rawValue, mb = b.categoryRaw == category.rawValue
                return ma != mb ? ma : a.name < b.name
            }
    }

    private var minutes: Double? { Self.number(minutesText).flatMap { $0 > 0 ? $0 : nil } }
    /// Leer = nicht gemessen (nil), nie 0. Ungültiger Text sperrt „Speichern“.
    private var distanceKm: Double?? {
        let t = distanceText.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return .some(nil) }
        guard let v = Self.number(t), v >= 0 else { return nil }
        return .some(v)
    }
    private var canSave: Bool { minutes != nil && distanceKm != nil && !saving }

    var body: some View {
        NavigationStack {
            Form {
                Section("Aktivität") {
                    Picker("Sportart", selection: $category) {
                        ForEach(SportCategory.allCases, id: \.self) { Text(DisplayNames.name(for: $0)).tag($0) }
                    }
                    .accessibilityIdentifier("activitySport")
                    DatePicker("Beginn", selection: $startAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    TextField("Dauer in Minuten", text: $minutesText)
                        .keyboardType(.decimalPad).focused($numberFocused)
                        .accessibilityIdentifier("activityMinutes")
                    TextField("Distanz in km (optional)", text: $distanceText)
                        .keyboardType(.decimalPad).focused($numberFocused)
                        .accessibilityIdentifier("activityDistance")
                }
                Section {
                    if candidates.isEmpty {
                        Text("Noch keine Ausrüstung. Die Aktivität wird ohne Ausrüstung gespeichert.").foregroundStyle(.secondary)
                    }
                    ForEach(candidates, id: \.id) { g in
                        Toggle(isOn: Binding(get: { selected.contains(g.id) },
                                             set: { on in if on { selected.insert(g.id) } else { selected.remove(g.id) } })) {
                            VStack(alignment: .leading) {
                                Text(g.name)
                                Text(DisplayNames.name(for: SportCategory(rawValue: g.categoryRaw) ?? .other))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("pick.\(g.name)")
                    }
                } header: {
                    Text("Ausrüstung")
                } footer: {
                    Text("Wähle alles, was du benutzt hast. Ohne Auswahl wird nur die Aktivität gespeichert.")
                }
            }
            .navigationTitle("Neue Aktivität")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.accessibilityIdentifier("activityCancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }.disabled(!canSave).accessibilityIdentifier("activitySave")
                }
            }
            .keyboardDoneButton($numberFocused)
            .onAppear(perform: preselect)
        }
    }

    private func preselect() {
        guard !didPreselect, let id = preselectedGearID, let g = allGear.first(where: { $0.id == id }) else { return }
        didPreselect = true
        selected = [id]
        category = SportCategory(rawValue: g.categoryRaw) ?? .cycling
    }

    private func save() {
        guard let minutes, let distance = distanceKm else { return }
        saving = true
        let input = ManualActivityInput(sportType: category.defaultSportType, startAt: startAt, durationSeconds: minutes * 60,
                                        distanceMeters: distance.map { $0 * 1_000 },
                                        gearIDs: candidates.map(\.id).filter(selected.contains))
        Task {
            if await model.run(.addManualActivity(input)) != nil { dismiss() } else { saving = false }
        }
    }

    /// Dezimalkomma und -punkt akzeptieren.
    static func number(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let v = Double(t), v.isFinite else { return nil }
        return v
    }
}
