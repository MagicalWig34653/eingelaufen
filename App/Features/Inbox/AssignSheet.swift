import GearCore
import SwiftData
import SwiftUI

/// Auswahl der Ausrüstung für eine Aktivität in **einem** Dialog (SPEC S05): mehrere Teile, Sets als Abkürzung.
/// Dient dem Posteingang („Ändern“, „Ausrüstung wählen“) und der Korrektur aus dem Verlauf.
struct AssignSheet: View {
    let activity: ActivityEntity
    let initial: Set<UUID>
    /// Nur im Posteingang: „Für ähnliche Aktivitäten merken“ (SPEC S05). In der Korrektur gibt es das nicht.
    let showsRemember: Bool
    var rememberInitially = false
    /// Korrektur darf auf „keine Ausrüstung“ stellen, der Posteingang nutzt dafür „Nicht zuordnen“.
    let allowsEmpty: Bool
    let onSave: (_ gear: [UUID], _ remember: Bool) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GearEntity.name) private var allGear: [GearEntity]
    @Query private var statusChanges: [GearStatusChangeEntity]
    @Query private var presets: [GearPresetEntity]
    @Query private var profiles: [SportProfileEntity]
    @State private var selected: Set<UUID> = []
    @State private var remember = false
    @State private var saving = false
    @State private var didLoad = false

    private var sport: SportType { SportType(rawValue: activity.sportTypeRaw) }
    private var category: SportCategory { SportCatalog.category(for: sport) }

    private var dataset: GearDataset {
        var d = GearDataset()
        d.gear = allGear.map(\.value)
        d.statusChanges = statusChanges.map(\.value)
        d.presets = presets.map(\.value)
        d.sportProfiles = profiles.map(\.value)
        return d
    }

    private var offers: [PresetOffer] { PresetPlanner.offered(for: activity.value, in: dataset) }

    /// Zum Aktivitätszeitpunkt zuweisbar (T-12) oder schon ausgewählt, damit eine frühere Wahl sichtbar bleibt.
    private var candidates: [GearEntity] {
        let d = dataset, context = AssignmentContext(dataset: d)
        return allGear.filter { g in
            selected.contains(g.id) || initial.contains(g.id) || AssignmentEngine.isAvailable(g.value, at: activity.startAt, in: context)
        }
    }
    private var matching: [GearEntity] { candidates.filter { $0.categoryRaw == category.rawValue } }
    private var others: [GearEntity] { candidates.filter { $0.categoryRaw != category.rawValue } }

    private var canSave: Bool { !saving && (allowsEmpty || !selected.isEmpty) }

    var body: some View {
        NavigationStack {
            Form {
                if !offers.isEmpty {
                    Section {
                        ForEach(offers, id: \.preset.id) { offer in
                            Button {
                                selected = Set(offer.availableGearIDs)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(offer.preset.name).foregroundStyle(.primary)
                                        if offer.isDefault { Text("Standard").font(.footnote).foregroundStyle(.secondary) }
                                    }
                                    Text(names(offer.availableGearIDs)).font(.footnote).foregroundStyle(.secondary)
                                    if !offer.unavailableGearIDs.isEmpty {
                                        Text("Nicht verfügbar: \(names(offer.unavailableGearIDs))").font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(minHeight: 44, alignment: .leading)
                            }
                            .accessibilityIdentifier("presetOffer.\(offer.preset.name)")
                        }
                    } header: {
                        Text("Sets")
                    } footer: {
                        Text("Ein Set wählt seine Teile aus. Du kannst die Auswahl danach ändern.")
                    }
                }
                gearSection("Passende Ausrüstung", matching)
                gearSection("Weitere Ausrüstung", others)
                if showsRemember {
                    Section {
                        Toggle("Für ähnliche Aktivitäten merken", isOn: $remember).accessibilityIdentifier("assignRemember")
                    } footer: {
                        Text("Legt eine Regel für künftige Aktivitäten an. Frühere Zuordnungen ändern sich nicht.")
                    }
                }
            }
            .navigationTitle("Ausrüstung wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.accessibilityIdentifier("assignCancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zuordnen") { save() }.disabled(!canSave).accessibilityIdentifier("assignConfirm")
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                selected = initial
                remember = rememberInitially
            }
        }
    }

    @ViewBuilder
    private func gearSection(_ title: LocalizedStringKey, _ items: [GearEntity]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items, id: \.id) { g in
                    Toggle(isOn: Binding(get: { selected.contains(g.id) },
                                         set: { on in if on { selected.insert(g.id) } else { selected.remove(g.id) } })) {
                        VStack(alignment: .leading) {
                            Text(g.name)
                            Text(DisplayNames.name(for: SportCategory(rawValue: g.categoryRaw) ?? .other))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("gearToggle.\(g.name)")
                }
            }
        }
    }

    private func names(_ ids: [UUID]) -> String {
        let byID = Dictionary(allGear.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byID[$0] }.joined(separator: ", ")
    }

    private func save() {
        saving = true
        // Reihenfolge der Auswahl folgt der Anzeige, nicht der Menge (stabil, nachvollziehbar).
        let ordered = (matching + others).map(\.id).filter(selected.contains)
        Task {
            if await onSave(ordered, remember) { dismiss() } else { saving = false }
        }
    }
}
