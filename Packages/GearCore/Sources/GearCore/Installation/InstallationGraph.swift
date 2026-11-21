import Foundation

public enum InstallationIssue: Hashable, Sendable {
    case selfInstallation(installationID: UUID)
    case endNotAfterStart(installationID: UUID)
    case overlappingChildInstallations(childGearID: UUID, first: UUID, second: UUID)
    case cycle(at: Date, gearIDs: [UUID])
    case startsBeforePurchase(installationID: UUID, gearID: UUID)

    /// Warnung statt Sperre (ARCHITEKTUR I-03: Kaufdatum kann unbekannt/geschätzt sein).
    public var isWarning: Bool {
        if case .startsBeforePurchase = self { return true }
        return false
    }
}

/// Montagegraph mit Zeitauflösung. Rein, ohne Systemuhr.
/// Prüft I-01 (keine Überlappung je Komponente), I-02 (azyklisch zu jedem Zeitpunkt) und I-03 (Ende nach Beginn).
public struct InstallationGraph: Sendable {
    public let installations: [Installation]
    private let byChild: [UUID: [Installation]]
    private let byParent: [UUID: [Installation]]

    public init(_ installations: [Installation]) {
        self.installations = installations
        self.byChild = Dictionary(grouping: installations, by: \.childGearID)
        self.byParent = Dictionary(grouping: installations, by: \.parentGearID)
    }

    // MARK: Validierung

    /// Alle Verstöße gegen I-01…I-03 (ohne Warnungen), deterministisch sortiert.
    public func validate() -> [InstallationIssue] {
        var issues: [InstallationIssue] = []
        let ordered = installations.sorted(by: Self.chronological)

        for inst in ordered where inst.parentGearID == inst.childGearID {
            issues.append(.selfInstallation(installationID: inst.id))
        }
        for inst in ordered {
            if let end = inst.endedAt, end <= inst.startedAt {
                issues.append(.endNotAfterStart(installationID: inst.id))
            }
        }
        issues += overlapIssues()
        issues += cycleIssues()
        return issues
    }

    /// I-03: Montage vor bekanntem Kaufdatum ist eine Warnung, keine Sperre.
    public func purchaseWarnings(gear: [GearItem]) -> [InstallationIssue] {
        let purchase = Dictionary(gear.compactMap { g in g.purchaseDate.map { (g.id, $0) } },
                                  uniquingKeysWith: { first, _ in first })
        return installations.sorted(by: Self.chronological).compactMap { inst in
            guard let bought = purchase[inst.childGearID], inst.startedAt < bought else { return nil }
            return .startsBeforePurchase(installationID: inst.id, gearID: inst.childGearID)
        }
    }

    /// Neue Verstöße, die entstehen würden, wenn `installation` hinzukäme (Bestehendes wird nicht erneut gemeldet).
    public func validating(adding installation: Installation) -> [InstallationIssue] {
        let existing = Set(validate())
        let combined = InstallationGraph(installations + [installation])
        return combined.validate().filter { !existing.contains($0) }
    }

    // MARK: Zeitauflösung

    /// Elternteil zum Zeitpunkt `t`. Bei (ungültigen) mehrfachen Montagen gewinnt die jüngste.
    public func parent(of child: UUID, at t: Date) -> UUID? {
        (byChild[child] ?? []).filter { $0.isActive(at: t) }
            .max(by: Self.chronological)?.parentGearID
    }

    public func children(of parent: UUID, at t: Date) -> [UUID] {
        let ids = Set((byParent[parent] ?? []).filter { $0.isActive(at: t) }.map(\.childGearID))
        return ids.sorted { $0.uuidString < $1.uuidString }
    }

    /// Alle zum Zeitpunkt `t` (transitiv) montierten Gegenstände, ohne `root`. Terminiert auch bei Kreisen.
    public func descendants(of root: UUID, at t: Date) -> [UUID] {
        var visited: Set<UUID> = [root]
        var result: [UUID] = []
        var queue = [root]
        while let current = queue.popLast() {
            for child in children(of: current, at: t) where visited.insert(child).inserted {
                result.append(child)
                queue.append(child)
            }
        }
        return result.sorted { $0.uuidString < $1.uuidString }
    }

    /// Die offene (nicht beendete) Montage einer Komponente.
    public func currentInstallation(of child: UUID) -> Installation? {
        (byChild[child] ?? []).filter { $0.endedAt == nil }.max(by: Self.chronological)
    }

    // MARK: Intern

    private static func chronological(_ a: Installation, _ b: Installation) -> Bool {
        (a.startedAt, a.id.uuidString) < (b.startedAt, b.id.uuidString)
    }

    private func overlapIssues() -> [InstallationIssue] {
        var issues: [InstallationIssue] = []
        for child in byChild.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            // Ungültige Intervalle (Ende ≤ Beginn) werden schon als solche gemeldet.
            let valid = (byChild[child] ?? [])
                .filter { inst in inst.endedAt.map { $0 > inst.startedAt } ?? true }
                .sorted(by: Self.chronological)
            for i in valid.indices {
                for j in valid.indices where j > i {
                    let a = valid[i], b = valid[j]
                    // a beginnt nicht nach b; überlappt, wenn b vor dem Ende von a beginnt.
                    if b.startedAt < (a.endedAt ?? .distantFuture) {
                        issues.append(.overlappingChildInstallations(childGearID: child, first: a.id, second: b.id))
                    }
                }
            }
        }
        return issues
    }

    /// Prüft an jeder Beginn-Grenze, weil sich die aktive Kantenmenge nur dort durch Hinzukommen ändert
    /// (Enden entfernen nur Kanten und können keinen Kreis erzeugen).
    private func cycleIssues() -> [InstallationIssue] {
        let usable = installations.filter { inst in
            inst.parentGearID != inst.childGearID && (inst.endedAt.map { $0 > inst.startedAt } ?? true)
        }
        let boundaries = Set(usable.map(\.startedAt)).sorted()
        var issues: [InstallationIssue] = []
        var previous: [UUID] = []
        for t in boundaries {
            let edges = usable.filter { $0.isActive(at: t) }.map { ($0.parentGearID, $0.childGearID) }
            let onCycle = Self.nodesOnCycles(edges: edges)
            if !onCycle.isEmpty, onCycle != previous {
                issues.append(.cycle(at: t, gearIDs: onCycle))
            }
            previous = onCycle
        }
        return issues
    }

    /// Knoten in nichttrivialen starken Zusammenhangskomponenten (Tarjan), sortiert.
    private static func nodesOnCycles(edges: [(UUID, UUID)]) -> [UUID] {
        var adjacency: [UUID: [UUID]] = [:]
        for (p, c) in edges { adjacency[p, default: []].append(c); adjacency[c, default: []] += [] }
        var index = 0
        var indices: [UUID: Int] = [:], low: [UUID: Int] = [:]
        var stack: [UUID] = [], onStack: Set<UUID> = []
        var result: Set<UUID> = []

        func connect(_ v: UUID) {
            indices[v] = index; low[v] = index; index += 1
            stack.append(v); onStack.insert(v)
            for w in adjacency[v] ?? [] {
                if indices[w] == nil {
                    connect(w)
                    low[v] = min(low[v]!, low[w]!)
                } else if onStack.contains(w) {
                    low[v] = min(low[v]!, indices[w]!)
                }
            }
            if low[v] == indices[v] {
                var component: [UUID] = []
                while let w = stack.popLast() {
                    onStack.remove(w)
                    component.append(w)
                    if w == v { break }
                }
                if component.count > 1 { result.formUnion(component) }
            }
        }
        for v in adjacency.keys.sorted(by: { $0.uuidString < $1.uuidString }) where indices[v] == nil {
            connect(v)
        }
        return result.sorted { $0.uuidString < $1.uuidString }
    }
}
