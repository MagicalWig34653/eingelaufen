import GearCore
import SwiftData
import SwiftUI

/// Onboarding (SPEC S01): höchstens drei Schritte, kein Konto. Schritt 2 (Apple Health) bietet bis M3 nur „Später“.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Query private var gear: [GearEntity]
    @State private var step = 0
    @State private var categories: Set<SportCategory> = []
    @State private var showAddGear = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Schritt \(step + 1) von 3")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("onboardingStep")
                    switch step {
                    case 0: sportsStep
                    case 1: healthStep
                    default: firstGearStep
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Willkommen")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) { actions }
        }
        .sheet(isPresented: $showAddGear) { AddGearView() }
    }

    // MARK: Schritte

    private var sportsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welche Sportarten machst du?").font(.title2.bold())
            Text("Mehrfachauswahl möglich. Du kannst das später ändern.").foregroundStyle(.secondary)
            ForEach(SportCategory.allCases, id: \.self) { category in
                let selected = categories.contains(category)
                Button {
                    if selected { categories.remove(category) } else { categories.insert(category) }
                } label: {
                    HStack(spacing: 12) {
                        SymbolBadge(systemName: DisplayNames.symbol(for: category))
                        Text(DisplayNames.name(for: category)).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? Color.accentColor : .secondary)
                    }
                    .padding(8)
                    .frame(minHeight: 48)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("sport.\(category.rawValue)")
            }
        }
    }

    private var healthStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Health").font(.title2.bold())
            Text("Eingelaufen kann deine Workouts aus Apple Health lesen, damit Ausrüstung ohne Handarbeit mitzählt. Es wird nichts geschrieben und nichts hochgeladen.")
            Text("Die Verbindung richtest du später ein. Bis dahin trägst du Aktivitäten von Hand ein, die App ist auch so voll nutzbar.")
                .foregroundStyle(.secondary)
        }
    }

    private var firstGearStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dein erstes Ausrüstungsteil").font(.title2.bold())
            Text("Mit einer Vorlage genügt ein Name, zum Beispiel für Laufschuhe oder dein Rad. Das geht auch später.")
            if !gear.isEmpty {
                Label("\(gear.count) angelegt", systemImage: "checkmark.circle")
                    .accessibilityIdentifier("onboardingGearCount")
            }
        }
    }

    // MARK: Aktionen

    private var actions: some View {
        VStack(spacing: 8) {
            switch step {
            case 0:
                Button("Weiter") { step = 1 }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("onboardingNext")
            case 1:
                Button("Später") { step = 2 }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("onboardingHealthLater")
            default:
                if gear.isEmpty {
                    Button("Vorlage wählen") { showAddGear = true }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("onboardingChooseTemplate")
                    Button("Später") { finish() }.accessibilityIdentifier("onboardingFirstGearLater")
                } else {
                    Button("Fertig") { finish() }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("onboardingDone")
                }
            }
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.bar)
    }

    private func finish() {
        Task { await model.run(.completeOnboarding(OnboardingChoice(categories: categories.sorted { $0.rawValue < $1.rawValue }, health: .later))) }
    }
}
