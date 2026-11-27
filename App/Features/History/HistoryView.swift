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
                List(activities, id: \.id) { ActivityRow(activity: $0, showsGear: true, linked: true) }
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
    /// Im Verlauf öffnet die Zeile die Aktivität (Korrektur der Ausrüstung, SPEC 6.3).
    var linked = false
    @Query private var assignments: [AssignmentEntity]
    @Query private var pendings: [PendingEntity]
    @Query private var gear: [GearEntity]

    init(activity: ActivityEntity, showsGear: Bool = false, linked: Bool = false) {
        self.activity = activity
        self.showsGear = showsGear
        self.linked = linked
        let id = activity.id
        _assignments = Query(filter: #Predicate { $0.activityID == id })
        _pendings = Query(filter: #Predicate { $0.activityID == id })
    }

    private var isOpen: Bool {
        pendings.contains { $0.stateRaw != PendingState.resolved.rawValue && $0.stateRaw != PendingState.dismissed.rawValue
            && $0.stateRaw != PendingState.obsolete.rawValue }
    }

    private var category: SportCategory { SportCatalog.category(for: SportType(rawValue: activity.sportTypeRaw)) }

    private var gearNames: String {
        let ids = Set(assignments.map(\.gearID))
        let names = gear.filter { ids.contains($0.id) }.map(\.name).sorted()
        if names.isEmpty { return isOpen ? "Zuordnung offen" : "Ohne Ausrüstung" }
        return names.joined(separator: ", ")
    }

    var body: some View {
        if linked {
            NavigationLink(value: ActivityRoute(id: activity.id)) { content }
                .accessibilityIdentifier("activityRow.\(gearNames)")
        } else {
            content
        }
    }

    private var content: some View {
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

/// Aktivität öffnen und Ausrüstung korrigieren (SPEC S06, 6.3, US-07): Nutzung des alten Teils sinkt, die des neuen steigt.
struct ActivityDetailView: View {
    let activityID: UUID
    @Environment(AppModel.self) private var model
    @Query private var activities: [ActivityEntity]
    @Query private var assignments: [AssignmentEntity]
    @Query private var pendings: [PendingEntity]
    @Query private var gear: [GearEntity]
    @State private var showChange = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    init(activityID: UUID) {
        self.activityID = activityID
        _activities = Query(filter: #Predicate { $0.id == activityID })
        _assignments = Query(filter: #Predicate { $0.activityID == activityID })
        _pendings = Query(filter: #Predicate { $0.activityID == activityID })
    }

    private var assigned: [GearEntity] {
        let ids = Set(assignments.filter { $0.segmentID == nil }.map(\.gearID))
        return gear.filter { ids.contains($0.id) }.sorted { $0.name < $1.name }
    }
    private var hasOpenEntry: Bool { !InboxEntries.open(pendings: pendings, activities: activities).isEmpty }

    var body: some View {
        Group {
            if let activity = activities.first, activity.deletedAt == nil {
                List {
                    Section("Aktivität") {
                        let category = SportCatalog.category(for: SportType(rawValue: activity.sportTypeRaw))
                        LabeledContent("Sportart", value: DisplayNames.name(for: category))
                        LabeledContent("Beginn", value: activity.startAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Dauer", value: DisplayNames.durationText(activity.durationSeconds))
                        LabeledContent("Distanz", value: DisplayNames.distance(activity.distanceMeters.map { .measured($0, isComplete: true) } ?? .noData))
                    }
                    Section {
                        Text(assigned.isEmpty ? (hasOpenEntry ? "Zuordnung offen" : "Ohne Ausrüstung") : assigned.map(\.name).joined(separator: ", "))
                            .accessibilityIdentifier("activityGearList")
                        Button("Ausrüstung ändern", systemImage: "pencil") { showChange = true }
                            .accessibilityIdentifier("changeGear")
                    } header: {
                        Text("Ausrüstung")
                    } footer: {
                        Text("Eine Änderung gilt rückwirkend: die Nutzung des alten Teils sinkt, die des neuen steigt.")
                    }
                    Section {
                        Button("Aktivität löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
                            .accessibilityIdentifier("activityDelete")
                            .confirmationDialog("Aktivität löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                                Button("Löschen", role: .destructive) {
                                    Task { if await model.run(.deleteActivity(activity.id)) != nil { dismiss() } }
                                }
                                .accessibilityIdentifier("confirmDeleteActivity")
                                Button("Abbrechen", role: .cancel) {}
                            } message: {
                                Text(activity.sourceRaw == ActivitySource.healthKit.rawValue
                                     ? "Die Aktivität zählt nicht mehr für deine Ausrüstung. In Apple Health bleibt sie erhalten."
                                     : "Die Aktivität wird endgültig gelöscht und zählt nicht mehr für deine Ausrüstung.")
                            }
                    }
                }
                .sheet(isPresented: $showChange) {
                    AssignSheet(activity: activity, initial: Set(assigned.map(\.id)), showsRemember: false, allowsEmpty: true) { ids, _ in
                        await model.run(.setActivityGear(activity: activity.id, gear: ids)) != nil
                    }
                }
            } else {
                ContentUnavailableView("Aktivität nicht gefunden", systemImage: "questionmark.circle")
            }
        }
        .navigationTitle("Aktivität")
        .navigationBarTitleDisplayMode(.inline)
    }
}
