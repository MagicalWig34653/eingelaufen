import GearCore
import SwiftData
import SwiftUI

/// Zeile für Listen: Symbol, Name, Kategorie/Status und wichtigste Nutzung („Keine Daten“ statt 0, T-09).
struct GearRow: View {
    let gear: GearEntity
    @Query private var summaries: [GearUsageSummaryEntity]

    init(gear: GearEntity) {
        self.gear = gear
        let id = gear.id
        _summaries = Query(filter: #Predicate { $0.gearID == id })
    }

    private var status: GearStatus { GearStatus(rawValue: gear.statusRaw) ?? .active }
    private var category: SportCategory { SportCategory(rawValue: gear.categoryRaw) ?? .other }

    private var usageText: String {
        guard let s = summaries.first?.value, s.uses > 0 else { return "Noch nicht verwendet" }
        let uses = s.uses == 1 ? "1 Nutzung" : "\(s.uses) Nutzungen"
        if case .noData = s.distanceMeters { return uses }
        return "\(uses) · \(DisplayNames.distance(s.distanceMeters))"
    }

    var body: some View {
        HStack(spacing: 12) {
            SymbolBadge(systemName: DisplayNames.symbol(for: category))
            VStack(alignment: .leading, spacing: 2) {
                Text(gear.name).font(.body.weight(.semibold))
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                Text(usageText).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [gear.subtypeRaw.flatMap(SportSubtype.init(rawValue:)).map(DisplayNames.name(for:)) ?? DisplayNames.name(for: category)]
        if status != .active { parts.append(DisplayNames.name(for: status)) }
        return parts.joined(separator: " · ")
    }
}
