import GearCore
import SwiftData
import SwiftUI

/// Zuordnungs-Posteingang (SPEC S05): offene Aktivitäten, ein klar markierter Vorschlag, „Vorschlag bestätigen“,
/// „Ändern“ (mehrere Teile in einem Dialog), „Nicht zuordnen“ als gültige Entscheidung.
struct InboxView: View {
    @Query private var pendings: [PendingEntity]
    @Query private var activities: [ActivityEntity]
    @Query(sort: \GearEntity.name) private var gear: [GearEntity]
    @Environment(AppModel.self) private var model
    @State private var editing: InboxEntry?

    private var entries: [InboxEntry] { InboxEntries.open(pendings: pendings, activities: activities) }
    private func name(_ id: UUID) -> String? { gear.first { $0.id == id }?.name }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Alles zugeordnet", systemImage: "checkmark.circle")
                } description: {
                    Text("Neue Aktivitäten, bei denen die Ausrüstung nicht eindeutig ist, erscheinen hier.")
                }
                .accessibilityIdentifier("inboxEmpty")
            } else {
                List {
                    ForEach(entries) { entry in
                        InboxCard(entry: entry, gearName: name, onChange: { editing = entry })
                    }
                }
                .accessibilityIdentifier("inboxList")
            }
        }
        .navigationTitle("Zuordnung")
        .sheet(item: $editing) { entry in
            let activity = activities.first { $0.id == entry.activity.id }
            if let activity {
                AssignSheet(activity: activity, initial: Set(entry.pending.proposedGearIDs), showsRemember: true,
                            allowsEmpty: false) { gear, remember in
                    await model.run(.resolvePending(id: entry.pending.id, action: .choose(gear: gear), remember: remember)) != nil
                }
            }
        }
    }
}

private struct InboxCard: View {
    let entry: InboxEntry
    let gearName: (UUID) -> String?
    let onChange: () -> Void
    @Environment(AppModel.self) private var model
    @State private var remember = false

    private var pending: PendingAssignment { entry.pending }
    private var activity: ActivityRecord { entry.activity }
    private var category: SportCategory { SportCatalog.category(for: activity.sportType) }
    private var hasProposal: Bool { !pending.proposedGearIDs.isEmpty && (pending.state == .suggested || pending.state == .ignored) }
    private var proposal: String { pending.proposedGearIDs.compactMap(gearName).joined(separator: ", ") }

    var body: some View {
        Section {
            HStack(spacing: 12) {
                SymbolBadge(systemName: DisplayNames.symbol(for: category))
                VStack(alignment: .leading, spacing: 2) {
                    Text(DisplayNames.name(for: category)).font(.body.weight(.semibold))
                    Text(activity.startAt.formatted(date: .abbreviated, time: .shortened)).font(.footnote).foregroundStyle(.secondary)
                    Text("\(DisplayNames.durationText(activity.durationSeconds)) · \(DisplayNames.distance(activity.distanceMeters.map { .measured($0, isComplete: true) } ?? .noData))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 48)
            .accessibilityElement(children: .combine)

            if hasProposal {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Vorschlag", systemImage: "lightbulb").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    Text(proposal).font(.body.weight(.semibold)).accessibilityIdentifier("inboxProposal")
                    Text(InboxTexts.reason(pending.reason)).font(.footnote).foregroundStyle(.secondary)
                }
                Button { confirm() } label: {
                    Text("Vorschlag bestätigen").frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("inboxConfirm")
                Toggle("Für ähnliche Aktivitäten merken", isOn: $remember).accessibilityIdentifier("inboxRemember")
            } else {
                Text(InboxTexts.reason(pending.reason)).font(.footnote).foregroundStyle(.secondary)
            }

            // Ohne Vorschlag steht die Hauptaktion untereinander: der längere Text bricht sonst in der Zeile um.
            if hasProposal {
                HStack(spacing: 12) { changeButton.buttonStyle(.bordered); dismissButton }
            } else {
                VStack(spacing: 12) { changeButton.buttonStyle(.borderedProminent); dismissButton }
            }
        }
    }

    private var dismissButton: some View {
        Button { dismissEntry() } label: {
            Text("Nicht zuordnen").frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("inboxDismiss")
    }

    private var changeButton: some View {
        Button(action: onChange) {
            Text(hasProposal ? "Ändern" : "Ausrüstung wählen").frame(maxWidth: .infinity, minHeight: 36)
        }
        .accessibilityIdentifier("inboxChange")
    }

    private func confirm() {
        let revision = pending.proposalRevision, id = pending.id, remember = remember
        Task { await model.run(.resolvePending(id: id, action: .confirm(proposalRevision: revision), remember: remember)) }
    }

    private func dismissEntry() {
        let id = pending.id
        Task { await model.run(.resolvePending(id: id, action: .dismiss, remember: false)) }
    }
}
