import GearCore
import SwiftData
import SwiftUI

/// Ausrüstungsliste (SPEC S03): nach Kategorie gruppiert, Suche, Archiv standardmäßig ausgeblendet (SPEC 4.2).
struct GearListView: View {
    @Binding var showSettings: Bool
    @Query(sort: \GearEntity.name) private var gear: [GearEntity]
    @State private var search = ""
    @State private var showArchived = false
    @State private var showAddGear = false

    private var visible: [GearEntity] {
        gear.filter { showArchived || $0.statusRaw != GearStatus.archived.rawValue }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var sections: [(SportCategory, [GearEntity])] {
        SportCategory.allCases.compactMap { c in
            let items = visible.filter { $0.categoryRaw == c.rawValue }
            return items.isEmpty ? nil : (c, items)
        }
    }

    var body: some View {
        Group {
            if gear.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Ausrüstung", systemImage: "figure.outdoor.cycle")
                } description: {
                    Text("Lege dein erstes Ausrüstungsteil an.")
                } actions: {
                    Button("Ausrüstung hinzufügen") { showAddGear = true }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("gearListAdd")
                }
            } else {
                List {
                    ForEach(sections, id: \.0) { category, items in
                        Section(DisplayNames.name(for: category)) {
                            ForEach(items, id: \.id) { g in
                                NavigationLink { GearDetailView(gearID: g.id) } label: { GearRow(gear: g) }
                                    .accessibilityIdentifier("gear.\(g.name)")
                            }
                        }
                    }
                }
                .overlay { if visible.isEmpty { ContentUnavailableView.search(text: search) } }
                .searchable(text: $search, prompt: "Ausrüstung suchen")
            }
        }
        .navigationTitle("Ausrüstung")
        .toolbar {
            SettingsToolbarButton(showSettings: $showSettings)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Archivierte anzeigen", isOn: $showArchived).accessibilityIdentifier("toggleArchived")
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                    .accessibilityLabel("Filter")
                    .accessibilityIdentifier("gearFilter")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddGear = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Ausrüstung hinzufügen")
                    .accessibilityIdentifier("gearAddButton")
            }
        }
        .sheet(isPresented: $showAddGear) { AddGearView() }
    }
}
