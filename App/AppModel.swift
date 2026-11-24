import Foundation
import GearCore
import Observation
import SwiftData

/// Verbindet die Oberfläche mit dem einzigen Schreiber (`PersistenceActor`). Die UI liest über `@Query`
/// und schreibt nur über Befehle (ARCHITEKTUR 3.2).
@MainActor @Observable
final class AppModel {
    let persistence: PersistenceActor
    /// Verständliche Meldung zum letzten fehlgeschlagenen Befehl (wird im Alert gezeigt).
    var errorMessage: String?

    init(container: ModelContainer) {
        persistence = PersistenceActor(modelContainer: container)
    }

    @discardableResult
    func run(_ command: GearCommand) async -> CommandOutcome? {
        do {
            let outcome = try await persistence.apply(command, now: Date())
            // Seiteneffekte erst nach dem Commit (A-04). Noch keiner registriert (kommen mit M3/M6/M7).
            _ = await OutboxDispatcher(persistence: persistence).deliver(to: NoSideEffects(), now: Date())
            return outcome
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    static func message(for reason: ComponentPlanError) -> String {
        switch reason {
        case .sameGear: "Ein Teil kann nicht in sich selbst verbaut werden."
        case .sameParent: "Das Teil sitzt schon dort."
        case .gearNotFound: "Diese Ausrüstung gibt es nicht mehr."
        case .gearAlreadyExists: "Dieses Teil existiert bereits."
        case .emptyName: "Bitte gib einen Namen ein."
        case .alreadyMounted: "Das Teil ist schon verbaut. Nutze „Umbauen“."
        case .notMounted: "Das Teil ist gerade nirgends verbaut."
        case .wouldCreateCycle: "So würde sich das Teil selbst enthalten."
        case .overlapsExistingInstallation: "Zu diesem Zeitpunkt war das Teil schon woanders verbaut."
        case .beforeInstallationStart: "Das Datum muss nach dem Einbau liegen."
        }
    }

    static func message(for reason: MaintenanceEntryError) -> String {
        switch reason {
        case .performedInFuture: "Das Datum darf nicht in der Zukunft liegen."
        case .negativeCost: "Die Kosten dürfen nicht negativ sein."
        case .invalidMeasurement: "Bitte gib einen gültigen Messwert ein."
        case .measurementRequired: "Bitte gib den gemessenen Wert ein."
        case .noteRequired: "Bitte beschreibe die Wartung kurz."
        }
    }

    static func message(for error: Error) -> String {
        switch error as? PersistenceError {
        case .emptyName: "Bitte gib einen Namen ein."
        case .gearNotFound: "Diese Ausrüstung gibt es nicht mehr."
        case .gearAlreadyExists, .activityAlreadyExists: "Dieser Eintrag existiert bereits."
        case .invalidDuration: "Die Dauer muss größer als 0 sein."
        case .invalidDistance: "Die Distanz darf nicht negativ sein."
        case .startsInFuture: "Der Beginn darf nicht in der Zukunft liegen."
        case .component(let reason): Self.message(for: reason)
        case .maintenance(let reason): Self.message(for: reason)
        case .invalidRule: "Das Intervall muss größer als 0 sein, die Vorwarnung darf es nicht überschreiten."
        case .ruleNotFound: "Diese Regel gibt es nicht mehr."
        case nil: "Das hat nicht geklappt. Bitte versuche es noch einmal."
        }
    }
}

/// Platzhalter, bis Benachrichtigungen, Live Activity und HealthKit-Anker Outbox-Einträge verarbeiten.
struct NoSideEffects: OutboxHandler {
    func handle(_ item: OutboxItem) async throws {}
}
