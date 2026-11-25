import GearCore
import SwiftData
import SwiftUI

/// Onboarding (SPEC S01): höchstens drei Schritte, kein Konto. Schritt 2 verbindet Apple Health mit Zeitraumwahl
/// oder vertagt es; importiert wird erst nach Schritt 3, damit die erste Ausrüstung schon zugeordnet werden kann.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Query private var gear: [GearEntity]
    @State private var step = 0
    @State private var categories: Set<SportCategory> = []
    @State private var showAddGear = false
    @State private var window = ImportWindow.standard
    @State private var connectHealth = false
    @State private var asking = false

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
                choiceRow(selected: selected, identifier: "sport.\(category.rawValue)") {
                    if selected { categories.remove(category) } else { categories.insert(category) }
                } label: {
                    SymbolBadge(systemName: DisplayNames.symbol(for: category))
                    Text(DisplayNames.name(for: category)).foregroundStyle(.primary)
                }
            }
        }
    }

    private func choiceRow(selected: Bool, identifier: String, action: @escaping () -> Void,
                           @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                label()
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
        .accessibilityIdentifier(identifier)
    }

    private var healthStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Health").font(.title2.bold())
            Text("Eingelaufen kann deine Workouts aus Apple Health lesen, damit Ausrüstung ohne Handarbeit mitzählt. Es wird nichts geschrieben und nichts hochgeladen.")
            Text("Welche Trainings sollen übernommen werden?").font(.headline).padding(.top, 4)
            ForEach(ImportWindow.allCases, id: \.self) { option in
                choiceRow(selected: window == option, identifier: "window.\(option.days ?? 0)") {
                    window = option
                } label: {
                    Text(HealthTexts.window(option)).foregroundStyle(.primary).padding(.leading, 8)
                }
            }
            Text("Wann neue Trainings im Hintergrund ankommen, entscheidet iOS; beim Öffnen gleicht die App ab. Du kannst das auch später in den Einstellungen verbinden und Aktivitäten von Hand eintragen.")
                .font(.footnote).foregroundStyle(.secondary)
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
                Button("Mit Apple Health verbinden") {
                    asking = true
                    Task {
                        if await model.requestHealthAccess() {
                            connectHealth = true
                            step = 2
                        }
                        asking = false
                    }
                }
                .buttonStyle(.borderedProminent).disabled(asking).accessibilityIdentifier("onboardingHealthConnect")
                Button("Später") {
                    connectHealth = false
                    step = 2
                }
                .disabled(asking).accessibilityIdentifier("onboardingHealthLater")
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
        let choice = OnboardingChoice(categories: categories.sorted { $0.rawValue < $1.rawValue },
                                      health: connectHealth ? .connected : .later, importWindow: window)
        Task {
            await model.run(.completeOnboarding(choice))
            await model.startHealth()
        }
    }
}
