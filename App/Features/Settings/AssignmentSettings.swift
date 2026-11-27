import GearCore
import SwiftData
import SwiftUI

/// Einstellungen › Zuordnung (SPEC S08 „Regeln und Presets“): Regeln ansehen und abschalten, Sets verwalten.
struct AssignmentSettingsSection: View {
    @Query private var rules: [AssignmentRuleEntity]
    @Query private var presets: [GearPresetEntity]

    var body: some View {
        Section {
            NavigationLink { RulesView() } label: {
                LabeledContent("Regeln", value: rules.isEmpty ? "Keine" : "\(rules.count)")
            }
            .accessibilityIdentifier("rulesLink")
            NavigationLink { PresetsView() } label: {
                LabeledContent("Sets", value: presets.isEmpty ? "Keine" : "\(presets.count)")
            }
            .accessibilityIdentifier("presetsLink")
        } header: {
            Text("Zuordnung")
        } footer: {
            Text("Regeln und Sets ordnen neue Aktivitäten zu. Frühere Zuordnungen ändern sie nie.")
        }
    }
}

enum AssignmentTexts {
    static func conditions(_ c: RuleConditions) -> String {
        var parts: [String] = []
        if let indoor = c.isIndoor { parts.append(indoor ? "drinnen" : "draußen") }
        if let days = c.weekdays, !days.isEmpty {
            let symbols = Calendar.current.shortWeekdaySymbols
            parts.append(days.sorted().map { symbols[($0 - 1) % 7] }.joined(separator: ", "))
        }
        return parts.isEmpty ? "Immer" : parts.joined(separator: " · ")
    }
}

struct RulesView: View {
    @Query(sort: \AssignmentRuleEntity.createdAt) private var rules: [AssignmentRuleEntity]
    @Query private var gear: [GearEntity]
    @Environment(AppModel.self) private var model

    private func names(_ ids: [UUID]) -> String {
        let byID = Dictionary(gear.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byID[$0] }.joined(separator: ", ")
    }

    var body: some View {
        Group {
            if rules.isEmpty {
                ContentUnavailableView {
                    Label("Keine Regeln", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Wähle beim Bestätigen „Für ähnliche Aktivitäten merken“, dann erscheint hier eine Regel.")
                }
            } else {
                List {
                    Section {
                        ForEach(rules, id: \.id) { rule in
                            Toggle(isOn: Binding(get: { rule.enabled },
                                                 set: { on in Task { await model.run(.setAssignmentRuleEnabled(id: rule.id, enabled: on)) } })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    let category = SportCatalog.category(for: SportType(rawValue: rule.sportTypeRaw))
                                    Text(DisplayNames.name(for: category)).font(.body.weight(.semibold))
                                    Text(names(rule.gearIDs)).font(.footnote)
                                    let kind = AssignmentRuleKind(rawValue: rule.kindRaw) == .remembered ? "Gemerkt" : "Festgelegt"
                                    Text("\(kind) · \(AssignmentTexts.conditions(RuleConditions.decoded(rule.conditionsData)))")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                .frame(minHeight: 48, alignment: .leading)
                            }
                            .accessibilityIdentifier("ruleToggle")
                            .swipeActions {
                                Button("Löschen", role: .destructive) { Task { await model.run(.removeAssignmentRule(rule.id)) } }
                            }
                        }
                    } footer: {
                        Text("Regeln gelten nur für neue Aktivitäten. Frühere Zuordnungen bleiben, wie sie sind.")
                    }
                }
            }
        }
        .navigationTitle("Regeln")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension RuleConditions {
    static func decoded(_ data: Data) -> RuleConditions { (try? JSONDecoder().decode(RuleConditions.self, from: data)) ?? RuleConditions() }
}

struct PresetsView: View {
    @Query(sort: \GearPresetEntity.name) private var presets: [GearPresetEntity]
    @Query private var profiles: [SportProfileEntity]
    @Query private var gear: [GearEntity]
    @Environment(AppModel.self) private var model
    @State private var showAdd = false

    private func names(_ ids: [UUID]) -> String {
        let byID = Dictionary(gear.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byID[$0] }.joined(separator: ", ")
    }

    var body: some View {
        List {
            if presets.isEmpty {
                Section {
                    Text("Ein Set bündelt Teile, die du oft zusammen nutzt, etwa Rad, Helm und Schuhe.").foregroundStyle(.secondary)
                }
            } else {
                Section("Sets") {
                    ForEach(presets, id: \.id) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.body.weight(.semibold))
                            Text(names(p.memberGearIDs)).font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 48, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("preset.\(p.name)")
                        .swipeActions {
                            Button("Löschen", role: .destructive) { Task { await model.run(.removePreset(p.id)) } }
                        }
                    }
                }
                Section {
                    ForEach(profiles.filter { $0.enabled }.sorted { $0.sportTypeRaw < $1.sportTypeRaw }, id: \.id) { profile in
                        let sport = SportType(rawValue: profile.sportTypeRaw)
                        let category = SportCatalog.category(for: sport)
                        let fitting = presets.filter { $0.isEnabled && $0.sportTypeRaws.contains(sport.rawValue) }
                        Picker(DisplayNames.name(for: category), selection: Binding(
                            get: { profile.defaultPresetID },
                            set: { id in Task { await model.run(.setDefaultPreset(sport: sport, preset: id)) } })) {
                            Text("Keins").tag(UUID?.none)
                            ForEach(fitting, id: \.id) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                        .accessibilityIdentifier("defaultPreset.\(category.rawValue)")
                    }
                } header: {
                    Text("Standard-Set je Sportart")
                } footer: {
                    Text("Ein Standard-Set ordnet neue Aktivitäten dieser Sportart ohne Nachfrage zu.")
                }
            }
        }
        .navigationTitle("Sets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Set anlegen").accessibilityIdentifier("presetAdd")
            }
        }
        .sheet(isPresented: $showAdd) { AddPresetView() }
    }
}

struct AddPresetView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GearEntity.name) private var allGear: [GearEntity]
    @State private var name = ""
    @State private var category: SportCategory = .cycling
    @State private var selected: Set<UUID> = []
    @State private var saving = false

    private var candidates: [GearEntity] {
        allGear.filter { $0.statusRaw == GearStatus.active.rawValue }.sorted { a, b in
            let ma = a.categoryRaw == category.rawValue, mb = b.categoryRaw == category.rawValue
            return ma != mb ? ma : a.name < b.name
        }
    }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !selected.isEmpty && !saving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).accessibilityIdentifier("presetName")
                    Picker("Sportart", selection: $category) {
                        ForEach(SportCategory.allCases, id: \.self) { Text(DisplayNames.name(for: $0)).tag($0) }
                    }
                }
                Section("Ausrüstung im Set") {
                    ForEach(candidates, id: \.id) { g in
                        Toggle(g.name, isOn: Binding(get: { selected.contains(g.id) },
                                                     set: { on in if on { selected.insert(g.id) } else { selected.remove(g.id) } }))
                            .accessibilityIdentifier("presetMember.\(g.name)")
                    }
                }
            }
            .navigationTitle("Neues Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }.disabled(!canSave).accessibilityIdentifier("presetSave")
                }
            }
        }
    }

    private func save() {
        saving = true
        let members = candidates.map(\.id).filter(selected.contains)
        Task {
            if await model.run(.createPreset(name: name, sportTypes: [category.defaultSportType], members: members)) != nil {
                dismiss()
            } else { saving = false }
        }
    }
}
