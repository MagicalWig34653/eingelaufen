import Foundation
import GearCore

/// Navigationsziele (wertbasiert, wie `GearRoute`: Ziele am Stack-Wurzel, nie Closure-Ziele).
struct InboxRoute: Hashable {}
struct ActivityRoute: Hashable { let id: UUID }

/// Brücke zwischen `@Query`-Zeilen und den Kernfunktionen: die Regeln für „offen“ und die Reihenfolge stehen nur im Kern.
enum InboxEntries {
    static func open(pendings: [PendingEntity], activities: [ActivityEntity]) -> [InboxEntry] {
        var d = GearDataset()
        d.pendings = pendings.map(\.value)
        d.activities = activities.map(\.value)
        return InboxQuery.open(in: d)
    }
}

/// Texte zur Begründung eines Vorschlags (SPEC 6.2 Schritt 5): sagt, woher er kommt, und nie „sicher“ bei bloßer Heuristik.
enum InboxTexts {
    static func reason(_ reason: AssignmentReason?) -> String {
        switch reason {
        case .history: "Du hast ähnliche Aktivitäten zuletzt so zugeordnet."
        case .rule: "Nach einer deiner Regeln."
        case .defaultPreset, .preset: "Nach deinem Set."
        case .soleCandidate: "Das einzige passende Teil."
        case .unavailableMembersDropped: "Einige Teile des Sets waren damals nicht verfügbar."
        case .replacementAmbiguous: "Die Aktivität wurde ersetzt, die Zuordnung ist nicht eindeutig."
        case .conflictingRules: "Mehrere Regeln passen gleich gut."
        case .multipleCandidates, .noCandidates, nil: "Mehrere Teile passen gleich gut."
        }
    }
}
