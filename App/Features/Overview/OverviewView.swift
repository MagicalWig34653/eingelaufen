import GearCore
import SwiftData
import SwiftUI

/// Übersicht (SPEC S02). Leer: keine Statistiken, keine Warnungen, nur der Einstieg (SPEC 1.3).
struct OverviewView: View {
    @Binding var showSettings: Bool
    @Query(sort: \GearEntity.createdAt) private var gear: [GearEntity]
    @Query(filter: #Predicate<ActivityEntity> { $0.deletedAt == nil }, sort: \.startAt, order: .reverse)
    private var activities: [ActivityEntity]
    @Query(sort: \LedgerEntryEntity.occurredAt, order: .reverse) private var ledger: [LedgerEntryEntity]
    @Query private var rules: [MaintenanceRuleEntity]
    @Query private var events: [MaintenanceEventEntity]
    @Query private var installations: [InstallationEntity]
    @Query private var pendings: [PendingEntity]
    @State private var showAddGear = false
    @State private var showAddActivity = false

    private var openAssignments: Int { InboxEntries.open(pendings: pendings, activities: activities).count }
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
                    if openAssignments > 0 {
                        Section("Zuordnung offen") {
                            NavigationLink(value: InboxRoute()) {
                                Label(openAssignments == 1 ? "1 Aktivität wartet auf Zuordnung" : "\(openAssignments) Aktivitäten warten auf Zuordnung",
                                      systemImage: "tray")
                                    .font(.body.weight(.semibold))
                                    .frame(minHeight: 44, alignment: .leading)
                            }
                            .accessibilityIdentifier("inboxLink")
                        }
                    }
                    Section("Status") {
                        LabeledContent("Ausrüstung", value: "\(activeGear.count)")
                        LabeledContent("Aktivitäten", value: "\(activities.count)")
                    }
                    if !hints.isEmpty {
                        Section {
                            ForEach(hints, id: \.id) { hint in
                                NavigationLink(value: GearRoute(id: hint.gearID)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(hint.gearName).font(.body.weight(.semibold))
                                        let style = DisplayNames.statusStyle(for: hint.state)
                                        Label {
                                            Text(hint.text).foregroundStyle(.secondary)
                                        } icon: {
                                            Image(systemName: style.symbol).foregroundStyle(style.color)
                                        }
                                        .font(.footnote)
                                    }
                                    .frame(minHeight: 44, alignment: .leading)
                                }
                                .accessibilityIdentifier("hint.\(hint.gearName)")
                            }
                        } header: {
                            Text("Wartung prüfen")
                        } footer: {
                            Text("Hinweise beruhen auf deinen eigenen Intervallen, nicht auf dem tatsächlichen Verschleiß.")
                        }
                    }
                    if !recentGear.isEmpty {
                        Section("Zuletzt verwendet") {
                            ForEach(recentGear, id: \.id) { g in
                                NavigationLink(value: GearRoute(id: g.id)) { GearRow(gear: g) }
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

    private struct Hint { var gearID: UUID; var gearName: String; var text: String; var state: RuleState; var id: String { "\(gearID)" } }

    /// Höchstens drei Hinweise (SPEC S02), nur für aktive Ausrüstung; Text sagt „Prüfen“, nicht „Ersetzen“.
    private var hints: [Hint] {
        let reports = MaintenanceReports.build(gear: activeGear, rules: rules, events: events, ledger: ledger,
                                               installations: installations, now: Date())
        let byGear = Dictionary(reports.map { ($0.gearID, $0) }, uniquingKeysWith: { a, _ in a })
        return MaintenanceEvaluator.topHints(reports, limit: 3).compactMap { h in
            guard let name = activeGear.first(where: { $0.id == h.gearID })?.name, let report = byGear[h.gearID] else { return nil }
            let text: String
            switch h.source {
            case .interval:
                text = report.intervals.first { $0.rule.id == h.ruleID }.map(DisplayNames.summary) ?? DisplayNames.name(for: h.state)
            case .measurement:
                text = String(localized: "Messgrenze erreicht: Prüfen")
            }
            return Hint(gearID: h.gearID, gearName: name, text: text, state: h.state)
        }
    }

    /// Bis zu drei zuletzt genutzte Gegenstände (nur belegte Nutzung, keine Schätzung).
    private var recentGear: [GearEntity] {
        var seen: [UUID] = []
        for entry in ledger where !seen.contains(entry.gearID) { seen.append(entry.gearID) }
        let byID = Dictionary(activeGear.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return seen.compactMap { byID[$0] }.prefix(3).map { $0 }
    }
}
