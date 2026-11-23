import GearCore
import SwiftData
import SwiftUI

/// Übersicht (SPEC S02). Leer: keine Statistiken, keine Warnungen, nur der Einstieg (SPEC 1.3).
struct OverviewView: View {
    @Binding var showSettings: Bool
    @Query(sort: \GearEntity.createdAt) private var gear: [GearEntity]
    @Query(sort: \ActivityEntity.startAt, order: .reverse) private var activities: [ActivityEntity]
    @Query(sort: \LedgerEntryEntity.occurredAt, order: .reverse) private var ledger: [LedgerEntryEntity]
    @State private var showAddGear = false
    @State private var showAddActivity = false

    private var activeGear: [GearEntity] { gear.filter { $0.statusRaw != GearStatus.archived.rawValue } }

    var body: some View {
        Group {
            if activeGear.isEmpty && activities.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Ausrüstung", systemImage: "figure.outdoor.cycle")
                } description: {
                    Text("Lege dein erstes Ausrüstungsteil an. Mit einer Vorlage genügt ein Name.")
                } actions: {
                    Button("Erstes Ausrüstungsteil hinzufügen") { showAddGear = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("addFirstGear")
                }
            } else {
                List {
                    Section("Status") {
                        LabeledContent("Ausrüstung", value: "\(activeGear.count)")
                        LabeledContent("Aktivitäten", value: "\(activities.count)")
                    }
                    if !recentGear.isEmpty {
                        Section("Zuletzt verwendet") {
                            ForEach(recentGear, id: \.id) { g in
                                NavigationLink { GearDetailView(gearID: g.id) } label: { GearRow(gear: g) }
                            }
                        }
                    }
                    if let last = activities.first {
                        Section("Letzte Aktivität") { ActivityRow(activity: last) }
                    }
                }
            }
        }
        .navigationTitle("Übersicht")
        .toolbar {
            SettingsToolbarButton(showSettings: $showSettings)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Ausrüstung hinzufügen", systemImage: "plus.circle") { showAddGear = true }
                        .accessibilityIdentifier("menuAddGear")
                    Button("Aktivität eintragen", systemImage: "figure.run") { showAddActivity = true }
                        .accessibilityIdentifier("menuAddActivity")
                } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Hinzufügen")
                    .accessibilityIdentifier("addMenu")
            }
        }
        .sheet(isPresented: $showAddGear) { AddGearView() }
        .sheet(isPresented: $showAddActivity) { ManualActivityView(preselectedGearID: nil) }
    }

    /// Bis zu drei zuletzt genutzte Gegenstände (nur belegte Nutzung, keine Schätzung).
    private var recentGear: [GearEntity] {
        var seen: [UUID] = []
        for entry in ledger where !seen.contains(entry.gearID) { seen.append(entry.gearID) }
        let byID = Dictionary(activeGear.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return seen.compactMap { byID[$0] }.prefix(3).map { $0 }
    }
}
