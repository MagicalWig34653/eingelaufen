import GearCore
import SwiftData
import SwiftUI

/// Ausrüstungsdetail (SPEC S04): Nutzung, Wartung (Schnellaktionen, Regeln, Status), Komponenten samt früherer, Verlauf.
struct GearDetailView: View {
    let gearID: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query private var rows: [GearEntity]
    @Query private var summaries: [GearUsageSummaryEntity]
    @Query private var ledger: [LedgerEntryEntity]
    @Query(sort: \ActivityEntity.startAt, order: .reverse) private var activities: [ActivityEntity]
    @State private var showRename = false
    @State private var newName = ""
    @State private var confirmArchive = false
    @State private var showAddActivity = false
    @State private var componentSheet: ComponentSheet?
    @Query private var mounted: [InstallationEntity]
    @Query private var childInstallations: [InstallationEntity]
    @Query private var allInstallations: [InstallationEntity]
    @Query private var allGear: [GearEntity]

    init(gearID: UUID) {
        self.gearID = gearID
        _rows = Query(filter: #Predicate { $0.id == gearID })
        _summaries = Query(filter: #Predicate { $0.gearID == gearID })
        _ledger = Query(filter: #Predicate { $0.gearID == gearID })
        _mounted = Query(filter: #Predicate { $0.childGearID == gearID && $0.endedAt == nil })
        _childInstallations = Query(filter: #Predicate { $0.parentGearID == gearID && $0.endedAt == nil })
    }

    var body: some View {
        Group {
            if let gear = rows.first { content(gear) } else {
                ContentUnavailableView("Nicht gefunden", systemImage: "questionmark.folder")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ gear: GearEntity) -> some View {
        let status = GearStatus(rawValue: gear.statusRaw) ?? .active
        let category = SportCategory(rawValue: gear.categoryRaw) ?? .other
        let usage = summaries.first?.value ?? UsageSummary(uses: 0, distanceMeters: .noData, durationSeconds: .noData)
        let used = Set(ledger.map(\.activityID))
        let history = activities.filter { used.contains($0.id) }
        return List {
            Section {
                HStack(spacing: 12) {
                    SymbolBadge(systemName: DisplayNames.symbol(for: category))
                    VStack(alignment: .leading) {
                        Text(gear.name).font(.title2.bold()).accessibilityIdentifier("detailName")
                        Text(gear.subtypeRaw.flatMap(SportSubtype.init(rawValue:)).map(DisplayNames.name(for:)) ?? DisplayNames.name(for: category))
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Status", value: DisplayNames.name(for: status)).accessibilityIdentifier("detailStatus")
                if let parent = mounted.first.flatMap({ m in allGear.first { $0.id == m.parentGearID } }) {
                    // Nur Text, kein Link zurück: Teil und Elternteil würden sich beim Aufbau endlos gegenseitig auswerten.
                    LabeledContent("Verbaut in", value: parent.name).accessibilityIdentifier("installedIn")
                    // Eine Komponente tauscht, baut um oder aus an ihrer eigenen Seite (SPEC 4.3, 4.4).
                    Button("Ersetzen", systemImage: "arrow.triangle.2.circlepath") { componentSheet = .replace(gearID) }
                        .accessibilityIdentifier("componentReplace.\(gear.name)")
                    Button("Umbauen", systemImage: "arrow.left.arrow.right") { componentSheet = .move(gearID) }
                        .accessibilityIdentifier("componentMove.\(gear.name)")
                    Button("Ausbauen", systemImage: "minus.circle") { componentSheet = .unmount(gearID) }
                        .accessibilityIdentifier("componentUnmount.\(gear.name)")
                }
            }
            Section("Nutzung") {
                LabeledContent("Nutzungen", value: "\(usage.uses)").accessibilityIdentifier("usageUses")
                LabeledContent("Distanz", value: DisplayNames.distance(usage.distanceMeters)).accessibilityIdentifier("usageDistance")
                LabeledContent("Dauer", value: DisplayNames.duration(usage.durationSeconds))
                if case let .value(since) = UsageQuery(entries: ledger.map(\.value), installations: allInstallations.map(\.value)).sinceInstallation(of: gearID) {
                    LabeledContent("Seit Einbau", value: since.uses == 1 ? "1 Nutzung" : "\(since.uses) Nutzungen")
                        .accessibilityIdentifier("sinceInstallation")
                }
            }
            ComponentsSection(gearID: gearID, isArchived: status == .archived, sheet: $componentSheet)
            MaintenanceSection(gearID: gearID, isArchived: status == .archived,
                               components: childInstallations.compactMap { c in allGear.first { $0.id == c.childGearID }.map { (id: $0.id, name: $0.name) } },
                               componentSheet: $componentSheet)
            Section("Aktionen") {
                Button("Aktivität eintragen", systemImage: "plus.circle") { showAddActivity = true }
                    .disabled(status == .archived)
                    .accessibilityIdentifier("detailAddActivity")
                Button("Umbenennen", systemImage: "pencil") { newName = gear.name; showRename = true }
                    .accessibilityIdentifier("detailRename")
                statusActions(gear, status)
            }
            if !history.isEmpty {
                Section("Verlauf") {
                    ForEach(history, id: \.id) { ActivityRow(activity: $0) }
                }
            }
        }
        .navigationTitle(gear.name)
        .alert("Umbenennen", isPresented: $showRename) {
            TextField("Name", text: $newName)
            Button("Speichern") { Task { await model.run(.renameGear(id: gearID, name: newName)) } }
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog("„\(gear.name)“ archivieren?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archivieren", role: .destructive) {
                Task { if await model.run(.setGearStatus(id: gearID, status: .archived, effectiveAt: Date())) != nil { dismiss() } }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Ausrüstung wird ausgeblendet, nicht gelöscht. Ihr Verlauf bleibt erhalten.")
        }
        .sheet(isPresented: $showAddActivity) { ManualActivityView(preselectedGearID: gearID) }
        .sheet(item: $componentSheet) { sheet in
            switch sheet {
            case .add: AddComponentSheet(parentID: gearID)
            case .replace(let id): ComponentActionSheet(mode: .replace, componentID: id)
            case .move(let id): ComponentActionSheet(mode: .move, componentID: id)
            case .unmount(let id): ComponentActionSheet(mode: .unmount, componentID: id)
            }
        }
    }

    @ViewBuilder
    private func statusActions(_ gear: GearEntity, _ status: GearStatus) -> some View {
        switch status {
        case .archived:
            Button("Wiederherstellen", systemImage: "arrow.uturn.backward") { set(.active) }.accessibilityIdentifier("detailRestore")
        case .stored:
            Button("Wieder aktivieren", systemImage: "arrow.uturn.backward") { set(.active) }.accessibilityIdentifier("detailActivate")
            Button("Archivieren", systemImage: "archivebox", role: .destructive) { confirmArchive = true }.accessibilityIdentifier("detailArchive")
        default:
            Button("Einlagern", systemImage: "shippingbox") { set(.stored) }.accessibilityIdentifier("detailStore")
            Button("Archivieren", systemImage: "archivebox", role: .destructive) { confirmArchive = true }.accessibilityIdentifier("detailArchive")
        }
    }

    private func set(_ status: GearStatus) {
        Task { await model.run(.setGearStatus(id: gearID, status: status, effectiveAt: Date())) }
    }
}
