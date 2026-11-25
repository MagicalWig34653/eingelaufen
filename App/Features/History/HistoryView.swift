import GearCore
import SwiftData
import SwiftUI

/// Verlauf (SPEC S06), Stand M2: Aktivitäten, neueste zuerst. Filter und Timeline mit Wartungen folgen in M9.
struct HistoryView: View {
    @Binding var showSettings: Bool
    @Query(filter: #Predicate<ActivityEntity> { $0.deletedAt == nil }, sort: \.startAt, order: .reverse)
    private var activities: [ActivityEntity]
    @State private var showAddActivity = false

    var body: some View {
        Group {
            if activities.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Aktivitäten", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Trage eine Aktivität ein oder verbinde Apple Health in den Einstellungen, damit deine Ausrüstung mitzählt.")
                } actions: {
                    Button("Aktivität eintragen") { showAddActivity = true }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("historyAdd")
                }
            } else {
                List(activities, id: \.id) { ActivityRow(activity: $0, showsGear: true) }
                    .accessibilityIdentifier("historyList")
            }
        }
        .navigationTitle("Verlauf")
        .toolbar {
            SettingsToolbarButton(showSettings: $showSettings)
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddActivity = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Aktivität eintragen")
                    .accessibilityIdentifier("historyAddButton")
            }
        }
        .sheet(isPresented: $showAddActivity) { ManualActivityView(preselectedGearID: nil) }
    }
}

struct ActivityRow: View {
    let activity: ActivityEntity
    var showsGear = false
    @Query private var assignments: [AssignmentEntity]
    @Query private var gear: [GearEntity]

    init(activity: ActivityEntity, showsGear: Bool = false) {
        self.activity = activity
        self.showsGear = showsGear
        let id = activity.id
        _assignments = Query(filter: #Predicate { $0.activityID == id })
    }

    private var category: SportCategory { SportCatalog.category(for: SportType(rawValue: activity.sportTypeRaw)) }

    private var gearNames: String {
        let ids = Set(assignments.map(\.gearID))
        let names = gear.filter { ids.contains($0.id) }.map(\.name).sorted()
        return names.isEmpty ? "Ohne Ausrüstung" : names.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            SymbolBadge(systemName: DisplayNames.symbol(for: category))
            VStack(alignment: .leading, spacing: 2) {
                Text(DisplayNames.name(for: category)).font(.body.weight(.semibold))
                Text(activity.startAt.formatted(date: .abbreviated, time: .shortened)).font(.footnote).foregroundStyle(.secondary)
                Text("\(DisplayNames.durationText(activity.durationSeconds)) · \(DisplayNames.distance(activity.distanceMeters.map { .measured($0, isComplete: true) } ?? .noData))")
                    .font(.footnote).foregroundStyle(.secondary)
                if showsGear { Text(gearNames).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }
}
