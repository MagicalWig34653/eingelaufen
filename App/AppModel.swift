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

    static func message(for error: Error) -> String {
        switch error as? PersistenceError {
        case .emptyName: "Bitte gib einen Namen ein."
        case .gearNotFound: "Diese Ausrüstung gibt es nicht mehr."
        case .gearAlreadyExists, .activityAlreadyExists: "Dieser Eintrag existiert bereits."
        case .invalidDuration: "Die Dauer muss größer als 0 sein."
        case .invalidDistance: "Die Distanz darf nicht negativ sein."
        case .startsInFuture: "Der Beginn darf nicht in der Zukunft liegen."
        case .component, .maintenance, .invalidRule, .ruleNotFound, .notImplemented, nil: "Das hat nicht geklappt. Bitte versuche es noch einmal."
        }
    }
}

/// Platzhalter, bis Benachrichtigungen, Live Activity und HealthKit-Anker Outbox-Einträge verarbeiten.
struct NoSideEffects: OutboxHandler {
    func handle(_ item: OutboxItem) async throws {}
}
