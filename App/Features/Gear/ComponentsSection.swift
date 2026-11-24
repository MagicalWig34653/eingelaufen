import GearCore
import SwiftData
import SwiftUI

/// Welches Blatt für Komponenten gerade offen ist (gehört dem Ausrüstungsdetail, damit Wartung und Komponenten es teilen).
enum ComponentSheet: Identifiable, Hashable {
    case add
    case replace(UUID), move(UUID), unmount(UUID)
    var id: String {
        switch self {
        case .add: "add"
        case .replace(let id): "replace.\(id)"
        case .move(let id): "move.\(id)"
        case .unmount(let id): "unmount.\(id)"
        }
    }
}

/// Komponenten eines Gegenstands (SPEC S04, 4.3, 4.4): aktuelle mit Menü (Ersetzen, Umbauen, Ausbauen), frühere bleiben aufrufbar.
struct ComponentsSection: View {
    let gearID: UUID
    let isArchived: Bool
    @Binding var sheet: ComponentSheet?
    @Query private var installations: [InstallationEntity]
    @Query private var allGear: [GearEntity]

    init(gearID: UUID, isArchived: Bool, sheet: Binding<ComponentSheet?>) {
        self.gearID = gearID
        self.isArchived = isArchived
        _sheet = sheet
        _installations = Query(filter: #Predicate { $0.parentGearID == gearID })
    }

    private var entries: [ComponentHistoryEntry] { ComponentHistory.entries(parent: gearID, installations: installations.map(\.value)) }
    private func name(_ id: UUID) -> String { allGear.first { $0.id == id }?.name ?? String(localized: "Unbekannt") }

    var body: some View {
        let current = entries.filter(\.isCurrent), previous = entries.filter { !$0.isCurrent }
        Section("Komponenten") {
            if current.isEmpty {
                Text("Noch keine Komponenten. Das ist in Ordnung: alles ist optional.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(current, id: \.installationID) { entry in
                let childName = name(entry.childID)
                NavigationLink { GearDetailView(gearID: entry.childID) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(childName)
                        Text("seit \(DisplayNames.day(entry.startedAt))").font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("component.\(childName)")
            }
            Button("Komponente hinzufügen", systemImage: "plus.circle") { sheet = .add }
                .disabled(isArchived)
                .accessibilityIdentifier("componentAdd")
        }
        if !previous.isEmpty {
            Section("Frühere Komponenten") {
                ForEach(previous, id: \.installationID) { entry in
                    let childName = name(entry.childID)
                    NavigationLink { GearDetailView(gearID: entry.childID) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(childName)
                            Text("\(DisplayNames.day(entry.startedAt)) bis \(DisplayNames.day(entry.endedAt ?? entry.startedAt))")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("previousComponent.\(childName)")
                }
            }
        }
    }
}

/// Neue Komponente aus Starter-Vorlage oder frei (SPEC S04): nur der Name ist Pflicht.
struct AddComponentSheet: View {
    let parentID: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query private var parents: [GearEntity]
    @State private var name = ""
    @State private var selected: String?
    @State private var date = Date()
    @State private var saving = false

    init(parentID: UUID) {
        self.parentID = parentID
        _parents = Query(filter: #Predicate { $0.id == parentID })
    }

    private var parent: GearEntity? { parents.first }
    private var templates: [ComponentTemplate] {
        guard let parent else { return [] }
        let category = SportCategory(rawValue: parent.categoryRaw) ?? .other
        let subtype = parent.subtypeRaw.flatMap(SportSubtype.init(rawValue:))
        let exact = GearTemplateCatalog.all.filter { $0.category == category && $0.subtype == subtype && !$0.components.isEmpty }
        let pool = exact.isEmpty ? GearTemplateCatalog.templates(for: category).filter { !$0.components.isEmpty } : exact
        var seen = Set<String>()
        return pool.flatMap(\.components).filter { seen.insert($0.id).inserted }
    }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                if !templates.isEmpty {
                    Section("Starter-Vorlagen") {
                        ForEach(templates) { t in
                            Button {
                                selected = t.id
                                name = DisplayNames.name(for: t)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(DisplayNames.name(for: t))
                                        if t.isSafetyCritical {
                                            Text("Sicherheitsrelevant: nur Prüfhinweise, nie ein Freigabesignal.").font(.footnote).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if selected == t.id { Image(systemName: "checkmark").accessibilityLabel("Gewählt") }
                                }
                                .frame(minHeight: 44)
                            }
                            .foregroundStyle(.primary)
                            .accessibilityIdentifier("componentTemplate.\(t.id)")
                        }
                    }
                }
                Section("Teil") {
                    TextField("Name", text: $name).accessibilityIdentifier("componentName")
                    DatePicker("Eingebaut am", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("Komponente hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.accessibilityIdentifier("componentCancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }.disabled(trimmed.isEmpty || saving).accessibilityIdentifier("componentSave")
                }
            }
        }
    }

    private func save() {
        guard let parent else { return }
        saving = true
        let item = GearItem(name: trimmed, createdAt: Date(), category: SportCategory(rawValue: parent.categoryRaw) ?? .other)
        Task { if await model.run(.addComponent(parent: parentID, item: item, at: date)) != nil { dismiss() } else { saving = false } }
    }
}

/// Ersetzen, Umbauen oder Ausbauen einer Komponente zu einem (auch rückdatierten) Zeitpunkt (SPEC 4.3–4.5).
struct ComponentActionSheet: View {
    enum Mode { case replace, move, unmount }
    let mode: Mode
    let componentID: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query private var rows: [GearEntity]
    @Query(sort: \GearEntity.name) private var allGear: [GearEntity]
    @Query private var installations: [InstallationEntity]
    @State private var name = ""
    @State private var date = Date()
    @State private var oldBecomes: GearStatus? = .stored
    @State private var newParent: UUID?
    @State private var loaded = false
    @State private var saving = false
    @FocusState private var nameFocused: Bool

    init(mode: Mode, componentID: UUID) {
        self.mode = mode
        self.componentID = componentID
        _rows = Query(filter: #Predicate { $0.id == componentID })
        _installations = Query(filter: #Predicate { $0.childGearID == componentID && $0.endedAt == nil })
    }

    private var component: GearEntity? { rows.first }
    private var currentParent: UUID? { installations.first?.parentGearID }
    private var candidates: [GearEntity] {
        allGear.filter { $0.id != componentID && $0.id != currentParent && $0.statusRaw != GearStatus.archived.rawValue }
    }
    private var title: String {
        switch mode { case .replace: "Ersetzen"; case .move: "Umbauen"; case .unmount: "Ausbauen" }
    }
    private var canConfirm: Bool {
        guard !saving else { return false }
        switch mode {
        case .replace: return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .move: return newParent != nil
        case .unmount: return true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch mode {
                case .replace:
                    Section {
                        TextField("Name des neuen Teils", text: $name).focused($nameFocused).accessibilityIdentifier("replaceName")
                    } footer: {
                        Text("Das neue Teil beginnt bei null. Der Verschleiß des alten Teils bleibt erhalten und bleibt unter „Frühere Komponenten“ aufrufbar.")
                    }
                    Section("Altes Teil") {
                        Picker("Danach", selection: $oldBecomes) {
                            Text("Einlagern").tag(GearStatus?.some(.stored))
                            Text("Ausmustern").tag(GearStatus?.some(.retired))
                            Text("Unverändert").tag(GearStatus?.none)
                        }
                        .accessibilityIdentifier("replaceOldStatus")
                    }
                case .move:
                    Section("Neu verbauen in") {
                        ForEach(candidates, id: \.id) { g in
                            Button {
                                newParent = g.id
                            } label: {
                                HStack {
                                    Text(g.name)
                                    Spacer()
                                    if newParent == g.id { Image(systemName: "checkmark").accessibilityLabel("Gewählt") }
                                }
                                .frame(minHeight: 44)
                            }
                            .foregroundStyle(.primary)
                            .accessibilityIdentifier("movePick.\(g.name)")
                        }
                    }
                case .unmount:
                    Section { Text("Das Teil bleibt mit seiner Historie bestehen und kann später wieder verbaut werden.") }
                }
                Section {
                    DatePicker("Zeitpunkt", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                } footer: {
                    Text("Ein früherer Zeitpunkt ist möglich. Die Nutzung dazwischen wird neu zugeordnet.")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.accessibilityIdentifier("componentActionCancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button(title) { confirm() }.disabled(!canConfirm).accessibilityIdentifier("\(mode)Confirm")
                }
            }
            .keyboardDoneButton($nameFocused)
            .onAppear {
                guard !loaded, let component else { return }
                loaded = true
                name = component.name
            }
        }
    }

    private func confirm() {
        guard let component else { return }
        saving = true
        let command: GearCommand
        switch mode {
        case .replace:
            let item = GearItem(name: name, createdAt: Date(), category: SportCategory(rawValue: component.categoryRaw) ?? .other,
                                subtype: component.subtypeRaw.flatMap(SportSubtype.init(rawValue:)))
            command = .replaceComponent(old: componentID, with: item, oldBecomes: oldBecomes, at: date)
        case .move:
            guard let newParent else { return }
            command = .moveComponent(child: componentID, to: newParent, at: date)
        case .unmount:
            command = .unmountComponent(child: componentID, at: date)
        }
        Task { if await model.run(command) != nil { dismiss() } else { saving = false } }
    }
}
