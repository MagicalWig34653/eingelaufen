import Foundation

// Regelbasierte Zuordnungs-Engine (SPEC 6.2, ARCHITEKTUR 6.1). Rein: keine Systemuhr, kein Standort, kein ML.
// Reihenfolge exakt nach Spec: explizit (Regel, Standard-Preset, eindeutiges Preset) → konservative Heuristik.
// Reine Heuristik wird nie als Gewissheit ausgegeben (SPEC 6.2, 17): ohne Regel/Preset wird nur vorgeschlagen oder gefragt.
// Ein einziger Kandidat wird standardmäßig nur vorgeschlagen; automatisch bucht ihn nur die ausdrückliche Option (P-09).

public enum AssignmentDecision: Hashable, Sendable {
    /// Nur bei expliziter Information oder genau einem Kandidaten.
    case autoAssign(gear: [UUID], reason: AssignmentReason, confidence: Confidence)
    case propose(primary: [UUID], alternatives: [[UUID]], reason: AssignmentReason, confidence: Confidence)
    /// Mehrere gleich plausible Kandidaten: keine Empfehlung erzwingen.
    case choose(candidates: [UUID], reason: AssignmentReason)
    /// „Ohne Ausrüstung“: importieren, keine Benachrichtigung.
    case noGear
}

/// Bestätigte frühere Zuordnung (Eingabe für die Gewohnheit; nie Quelle einer Automatik).
public struct ConfirmedAssignment: Hashable, Codable, Sendable {
    public var sportType: SportType
    public var gearIDs: [UUID]
    public var confirmedAt: Date
    public init(sportType: SportType, gearIDs: [UUID], confirmedAt: Date) {
        self.sportType = sportType
        self.gearIDs = gearIDs
        self.confirmedAt = confirmedAt
    }
}

/// Umkehrbare Planungsannahmen der Engine.
public struct EnginePolicy: Hashable, Sendable {
    /// P-09 (Option, Standard aus): Genau ein verfügbarer Gegenstand der Kategorie wird ohne Nachfrage zugeordnet.
    /// Die Spec deckt das nicht: automatisch nur explizite Regeln/Presets (6.2, 17), bei Heuristik nur Vorschlag.
    /// Standard daher `false`; die App darf es nur auf Linos ausdrückliche Entscheidung einschalten.
    public var autoAssignSoleCandidate: Bool
    /// Wie viele jüngste bestätigte Zuordnungen die Gewohnheit betrachtet.
    public var historyWindow: Int
    /// Mindestanzahl übereinstimmender Bestätigungen für einen Vorschlag.
    public var minHistory: Int

    public init(autoAssignSoleCandidate: Bool = false, historyWindow: Int = 3, minHistory: Int = 2) {
        self.autoAssignSoleCandidate = autoAssignSoleCandidate
        self.historyWindow = historyWindow
        self.minHistory = minHistory
    }
}

public struct AssignmentContext: Sendable {
    public var gear: [GearItem]
    public var statusChanges: [GearStatusChange]
    public var installations: [Installation]
    public var presets: [GearPreset]
    public var sportProfiles: [SportProfile]
    public var rules: [AssignmentRule]
    public var history: [ConfirmedAssignment]
    /// Nur für tageszeitliche Regeln (Wochentag); Persistenz bleibt UTC (SPEC 10.4).
    public var calendar: Calendar
    public var policy: EnginePolicy

    public init(gear: [GearItem] = [], statusChanges: [GearStatusChange] = [], installations: [Installation] = [],
                presets: [GearPreset] = [], sportProfiles: [SportProfile] = [], rules: [AssignmentRule] = [],
                history: [ConfirmedAssignment] = [], calendar: Calendar = Calendar(identifier: .gregorian),
                policy: EnginePolicy = EnginePolicy()) {
        self.gear = gear
        self.statusChanges = statusChanges
        self.installations = installations
        self.presets = presets
        self.sportProfiles = sportProfiles
        self.rules = rules
        self.history = history
        self.calendar = calendar
        self.policy = policy
    }

    public init(dataset: GearDataset, history: [ConfirmedAssignment] = [], calendar: Calendar = Calendar(identifier: .gregorian),
                policy: EnginePolicy = EnginePolicy()) {
        self.init(gear: dataset.gear, statusChanges: dataset.statusChanges, installations: dataset.installations,
                  presets: dataset.presets, sportProfiles: dataset.sportProfiles, rules: dataset.assignmentRules,
                  history: history, calendar: calendar, policy: policy)
    }
}

public enum AssignmentEngine {

    public static func decide(for activity: ActivityRecord, context c: AssignmentContext) -> AssignmentDecision {
        let t = activity.startAt
        let sport = activity.sportType
        let profile = c.sportProfiles.first { $0.sportType == sport }
        if profile?.enabled == false { return .noGear }

        let byID = Dictionary(c.gear.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func available(_ g: UUID) -> Bool { byID[g].map { isAvailable($0, at: t, in: c) } ?? false }

        // 1. Feste Zuordnungsregeln (explizit).
        let matching = c.rules.filter { $0.enabled && $0.sportType == sport && matches($0.conditions, activity, c.calendar) }
        if let top = matching.map(\.priority).max() {
            let leaders = matching.filter { $0.priority == top }
            let distinctSets = Set(leaders.map { Set($0.gearIDs) })
            if distinctSets.count > 1 {
                let union = Set(leaders.flatMap(\.gearIDs)).filter(available)
                if !union.isEmpty {
                    return .choose(candidates: ordered(union, byID), reason: .conflictingRules)
                }
            } else if let rule = leaders.min(by: { $0.id.uuidString < $1.id.uuidString }) {
                if let d = apply(members: rule.gearIDs, reason: .rule(rule.id), confidence: .explicit,
                                 available: available) { return d }
            }
        }

        // 2. Standard-Preset des Sportprofils (explizit), dann ein eindeutig passendes Preset.
        if let presetID = profile?.defaultPresetID,
           let preset = c.presets.first(where: { $0.id == presetID && $0.isEnabled }),
           let d = apply(members: preset.memberGearIDs, reason: .defaultPreset(preset.id), confidence: .explicit,
                         available: available) {
            return d
        }
        let fitting = c.presets.filter { $0.isEnabled && $0.sportTypes.contains(sport) }
        if fitting.count == 1, let d = apply(members: fitting[0].memberGearIDs, reason: .preset(fitting[0].id),
                                             confidence: .high, available: available) {
            return d
        }

        // 3. Konservative Heuristik über unabhängig getragene, verfügbare Gegenstände der Kategorie.
        let category = SportCatalog.category(for: sport)
        let candidates = ordered(c.gear.filter {
            $0.category == category && isAvailable($0, at: t, in: c) && !isMounted($0.id, at: t, in: c)
        }.map(\.id), byID)

        switch candidates.count {
        case 0:
            return .noGear
        case 1:
            let only = candidates[0]
            return c.policy.autoAssignSoleCandidate
                ? .autoAssign(gear: [only], reason: .soleCandidate, confidence: .high)
                : .propose(primary: [only], alternatives: [], reason: .soleCandidate, confidence: .medium)
        default:
            if let habit = habitualSet(sport: sport, candidates: candidates, c) {
                let alternatives = candidates.filter { !habit.contains($0) }.map { [$0] }
                return .propose(primary: ordered(habit, byID), alternatives: alternatives, reason: .history, confidence: .medium)
            }
            return .choose(candidates: candidates, reason: .multipleCandidates)
        }
    }

    // MARK: Verfügbarkeit (T-12)

    /// Zuweisbar zum Zeitpunkt `t`: Status zu `t` ist aktiv und der Gegenstand war schon gekauft.
    /// Ohne Historie gilt der heutige Status (konservativ).
    public static func isAvailable(_ item: GearItem, at t: Date, in c: AssignmentContext) -> Bool {
        if let purchase = item.purchaseDate, purchase > t { return false }
        return status(of: item, at: t, changes: c.statusChanges) == .active
    }

    static func status(of item: GearItem, at t: Date, changes: [GearStatusChange]) -> GearStatus {
        let history = changes.filter { $0.gearID == item.id }
        guard !history.isEmpty else { return item.status }
        // Vor dem ersten Eintrag war der Gegenstand im Zweifel noch nicht in diesem Status → aktiv; danach der jüngste Wechsel.
        let latest = history.filter { $0.effectiveAt <= t }.max { $0.effectiveAt < $1.effectiveAt }
        return latest?.status ?? .active
    }

    // MARK: Bausteine

    private static func isMounted(_ gearID: UUID, at t: Date, in c: AssignmentContext) -> Bool {
        c.installations.contains { $0.childGearID == gearID && $0.isActive(at: t) }
    }

    private static func matches(_ cond: RuleConditions, _ a: ActivityRecord, _ calendar: Calendar) -> Bool {
        if let wantIndoor = cond.isIndoor, a.isIndoor != wantIndoor { return false }   // nil ≠ belegt
        if let days = cond.weekdays, !days.contains(calendar.component(.weekday, from: a.startAt)) { return false }
        return true
    }

    /// Wendet eine Mitgliederliste an: vollständig verfügbar → automatisch; teilweise → nur Vorschlag; keines → weiter.
    private static func apply(members: [UUID], reason: AssignmentReason, confidence: Confidence,
                              available: (UUID) -> Bool) -> AssignmentDecision? {
        let usable = members.filter(available)
        if usable.isEmpty { return nil }
        if usable.count == members.count { return .autoAssign(gear: usable, reason: reason, confidence: confidence) }
        return .propose(primary: usable, alternatives: [], reason: .unavailableMembersDropped, confidence: .medium)
    }

    private static func habitualSet(sport: SportType, candidates: [UUID], _ c: AssignmentContext) -> Set<UUID>? {
        let pool = Set(candidates)
        let recent = c.history.filter { $0.sportType == sport && Set($0.gearIDs).isSubset(of: pool) && !$0.gearIDs.isEmpty }
            .sorted { $0.confirmedAt > $1.confirmedAt }
            .prefix(c.policy.historyWindow)
        guard recent.count >= c.policy.minHistory else { return nil }
        let sets = Set(recent.map { Set($0.gearIDs) })
        return sets.count == 1 ? sets.first : nil
    }

    private static func ordered<S: Sequence>(_ ids: S, _ byID: [UUID: GearItem]) -> [UUID] where S.Element == UUID {
        ids.sorted {
            let a = byID[$0]?.createdAt ?? .distantPast, b = byID[$1]?.createdAt ?? .distantPast
            return a != b ? a < b : $0.uuidString < $1.uuidString
        }
    }
}
