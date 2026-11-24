import GearCore
import SwiftData
import SwiftUI

/// Wartung im Ausrüstungsdetail (SPEC S04/S07): Schnellaktionsleiste (alle 7 Typen, Speichern ohne Formular),
/// drei getrennte Statusarten (Intervall, Messwert, Prognose als Schätzung), Regeln, Verlauf.
struct MaintenanceSection: View {
    let gearID: UUID
    let isArchived: Bool
    let components: [(id: UUID, name: String)]
    @Binding var componentSheet: ComponentSheet?
    @Environment(AppModel.self) private var model
    @Query private var events: [MaintenanceEventEntity]
    @Query private var rules: [MaintenanceRuleEntity]
    @Query private var ledger: [LedgerEntryEntity]
    @Query private var installations: [InstallationEntity]
    @Query private var gearRows: [GearEntity]
    @State private var form: MaintenanceFormKind?
    @State private var ruleSheet: RuleSheet?
    @State private var partDialog = false

    init(gearID: UUID, isArchived: Bool, components: [(id: UUID, name: String)], componentSheet: Binding<ComponentSheet?>) {
        self.gearID = gearID
        self.isArchived = isArchived
        self.components = components
        _componentSheet = componentSheet
        _events = Query(filter: #Predicate { $0.gearID == gearID }, sort: \.performedAt, order: .reverse)
        _rules = Query(filter: #Predicate { $0.gearID == gearID })
        _ledger = Query(filter: #Predicate { $0.gearID == gearID })
        _gearRows = Query(filter: #Predicate { $0.id == gearID })
    }

    private var report: GearMaintenanceReport {
        MaintenanceEvaluator.report(gearID: gearID, rules: rules.map(\.value), events: events.map(\.value), entries: ledger.map(\.value),
                                    installations: installations.map(\.value), gear: gearRows.map(\.value), now: Date())
    }

    var body: some View {
        let report = report
        Section("Wartung") {
            quickBar
            ForEach(rules.sorted { $0.id.uuidString < $1.id.uuidString }, id: \.id) { rule in ruleRow(rule.value, report: report) }
            if let m = report.measurement { measurementRow(m) }
            if let f = report.forecast {
                Label("Schätzung: bei bisherigem Nutzungsverlauf in etwa \(f.estimatedDaysUntilDue) Tagen prüfen (Basis: \(f.basisDays) Tage).",
                      systemImage: "chart.line.uptrend.xyaxis")
                    .font(.footnote)
                    .accessibilityIdentifier("forecastStatus")
            }
            Button("Regel hinzufügen", systemImage: "plus.circle") { ruleSheet = .new }
                .disabled(isArchived)
                .accessibilityIdentifier("ruleAdd")
        }
        if !events.isEmpty {
            Section("Wartungsverlauf") {
                ForEach(events.prefix(8), id: \.id) { eventRow($0.value) }
            }
        }
    }

    private var quickBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(QuickAction.allCases, id: \.self) { action in
                    Button { perform(action) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: DisplayNames.symbol(for: action)).font(.title3)
                            Text(DisplayNames.name(for: action)).font(.footnote).lineLimit(2).multilineTextAlignment(.center)
                        }
                        .frame(minWidth: 76, minHeight: 56)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isArchived)
                    .accessibilityIdentifier("quick.\(action.rawValue)")
                }
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        .sheet(item: $form) { MaintenanceFormView(gearID: gearID, kind: $0.kind) }
        .sheet(item: $ruleSheet) { RuleFormView(gearID: gearID, editing: $0.rule) }
        .confirmationDialog("Teil wechseln", isPresented: $partDialog, titleVisibility: .visible) {
            Button("Teil einbauen") { componentSheet = .add }
            ForEach(components, id: \.id) { c in
                Button("„\(c.name)“ ersetzen") { componentSheet = .replace(c.id) }
            }
        }
    }

    private func perform(_ action: QuickAction) {
        switch action {
        case .cleaned, .lubricated, .inspected, .repaired:
            // Ein Tipp speichert sofort, ohne Formular (SPEC S07).
            Task { await model.run(.recordMaintenance(MaintenanceInput(gearID: gearID, kind: action.kinds[0]))) }
        case .wearMeasured: form = MaintenanceFormKind(kind: .wearMeasured)
        case .custom: form = MaintenanceFormKind(kind: .custom)
        case .partChange: partDialog = true
        }
    }

    @ViewBuilder
    private func ruleRow(_ rule: MaintenanceRule, report: GearMaintenanceReport) -> some View {
        Button { ruleSheet = RuleSheet(rule: rule) } label: {
            VStack(alignment: .leading, spacing: 2) {
                if rule.kind == .wearMeasured {
                    Text("Messgrenze \(DisplayNames.number(rule.intervalValue))").font(.body)
                    Text(rule.enabled ? String(localized: "Regel aktiv") : String(localized: "Regel aus")).font(.footnote).foregroundStyle(.secondary)
                } else if !rule.enabled {
                    Text("\(DisplayNames.name(for: rule.kind)): alle \(DisplayNames.plain(rule.intervalValue, rule.metric))")
                    Text("Regel aus").font(.footnote).foregroundStyle(.secondary)
                } else if let status = report.intervals.first(where: { $0.rule.id == rule.id }) {
                    Text(DisplayNames.summary(status))
                } else {
                    Text(DisplayNames.name(for: rule.kind))
                }
            }
            .frame(minHeight: 44, alignment: .leading)
            .foregroundStyle(.primary)
        }
        .accessibilityIdentifier(rule.kind == .wearMeasured ? "ruleLimit" : "ruleStatus.\(rule.kind.rawValue)")
    }

    private func measurementRow(_ m: MeasurementStatus) -> some View {
        var text = String(localized: "Zuletzt gemessen: \(DisplayNames.number(m.value)) am \(DisplayNames.day(m.measuredAt))")
        switch m.state {
        case .noLimit: break
        case .withinLimit: text += " · " + String(localized: "Grenze \(DisplayNames.number(m.limit ?? 0)): im Rahmen")
        case .limitReached: text += " · " + String(localized: "Grenze \(DisplayNames.number(m.limit ?? 0)) erreicht: Prüfen")
        }
        return Label(text, systemImage: "ruler").accessibilityIdentifier("measurementStatus")
    }

    private func eventRow(_ e: MaintenanceEvent) -> some View {
        var parts = [DisplayNames.name(for: e.kind), DisplayNames.day(e.performedAt)]
        if let m = e.measurement { parts.append(DisplayNames.number(m)) }
        if let c = e.costMinor { parts.append(DisplayNames.cost(minor: c)) }
        if let n = e.notes { parts.append(n) }
        return Text(parts.joined(separator: " · "))
            .accessibilityIdentifier("maintenanceEvent.\(e.kind.rawValue)")
    }
}

struct MaintenanceFormKind: Identifiable {
    let kind: MaintenanceKind
    var id: String { kind.rawValue }
}

struct RuleSheet: Identifiable {
    var rule: MaintenanceRule?
    var id: String { rule?.id.uuidString ?? "new" }
    static let new = RuleSheet(rule: nil)
}
