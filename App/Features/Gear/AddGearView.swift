import GearCore
import SwiftUI

/// Vorlagen-Assistent (SPEC S03): Kategorie → Vorlage → Name → Speichern. Nur der Name ist Pflicht, keine Modal-Kaskade
/// (alles in einem Sheet mit Navigation).
struct AddGearView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(SportCategory.allCases, id: \.self) { category in
                NavigationLink(value: category) {
                    HStack(spacing: 12) {
                        SymbolBadge(systemName: DisplayNames.symbol(for: category))
                        Text(DisplayNames.name(for: category))
                    }
                    .frame(minHeight: 48)
                }
                .accessibilityIdentifier("category.\(category.rawValue)")
            }
            .navigationTitle("Neue Ausrüstung")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SportCategory.self) { TemplateListView(category: $0) }
            .navigationDestination(for: GearDraft.self) { NameStepView(draft: $0) { dismiss() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.accessibilityIdentifier("addGearCancel") }
            }
        }
    }
}

/// Zwischenstand vor dem Speichern.
struct GearDraft: Hashable {
    var category: SportCategory
    var subtype: SportSubtype?
    var suggestedName: String
}

private struct TemplateListView: View {
    let category: SportCategory

    var body: some View {
        List {
            Section("Vorlagen") {
                ForEach(GearTemplateCatalog.templates(for: category)) { template in
                    NavigationLink(value: GearDraft(category: category, subtype: template.subtype, suggestedName: DisplayNames.name(for: template))) {
                        HStack(spacing: 12) {
                            SymbolBadge(systemName: template.symbol)
                            Text(DisplayNames.name(for: template))
                        }
                        .frame(minHeight: 48)
                    }
                    .accessibilityIdentifier("template.\(template.id)")
                }
            }
            Section {
                NavigationLink(value: GearDraft(category: category, subtype: nil, suggestedName: "")) {
                    Label("Frei hinzufügen", systemImage: "square.and.pencil").frame(minHeight: 48)
                }
                .accessibilityIdentifier("template.free")
            }
        }
        .navigationTitle(DisplayNames.name(for: category))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NameStepView: View {
    let draft: GearDraft
    let onSaved: () -> Void
    @Environment(AppModel.self) private var model
    @State private var name: String
    @State private var saving = false
    @FocusState private var focused: Bool

    init(draft: GearDraft, onSaved: @escaping () -> Void) {
        self.draft = draft
        self.onSaved = onSaved
        _name = State(initialValue: draft.suggestedName)
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saving }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .focused($focused)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .onSubmit { save() }
                    .accessibilityIdentifier("gearNameField")
            } header: {
                Text(DisplayNames.name(for: draft.category))
            } footer: {
                Text("Mehr ist nicht nötig. Teile und Wartung kannst du später ergänzen.")
            }
        }
        .navigationTitle("Name")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") { save() }.disabled(!canSave).accessibilityIdentifier("gearSave")
            }
        }
        .onAppear { focused = draft.suggestedName.isEmpty }
    }

    private func save() {
        guard canSave else { return }
        saving = true
        let item = GearItem(name: name, createdAt: Date(), category: draft.category, subtype: draft.subtype)
        Task {
            if await model.run(.createGear(item)) != nil { onSaved() } else { saving = false }
        }
    }
}
