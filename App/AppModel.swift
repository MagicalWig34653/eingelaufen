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

    private let health: HealthImporter

    init(container: ModelContainer, healthSource: any HealthWorkoutSource = HealthKitWorkoutSource()) {
        let persistence = PersistenceActor(modelContainer: container)
        self.persistence = persistence
        health = HealthImporter(source: healthSource, store: persistence, now: { Date() })
    }

    // MARK: Apple Health (SPEC 6.1)

    /// Systemdialog für die Leserechte. Ein Erfolg sagt nichts darüber, was der Nutzer erlaubt hat (F-04).
    func requestHealthAccess() async -> Bool {
        do {
            try await health.requestAuthorization()
            return true
        } catch {
            errorMessage = error as? HealthSourceError == .unavailable
                ? "Apple Health ist auf diesem Gerät nicht verfügbar."
                : "Apple Health konnte nicht geöffnet werden. Bitte versuche es noch einmal."
            return false
        }
    }

    /// Verbinden bzw. Zeitraum ändern und sofort abgleichen.
    @discardableResult
    func connectHealth(_ window: ImportWindow) async -> Bool {
        guard await requestHealthAccess(), await run(.connectHealth(window)) != nil else { return false }
        await startHealth()
        return true
    }

    /// App-Start und Vordergrund: Beobachter registrieren und abgleichen (ohne Verbindung passiert nichts).
    func startHealth() async { await health.start() }
    func syncHealth() async { await health.sync() }
    /// Nach dem Entsperren: ausstehenden Import nachholen (F-03).
    func retryHealthIfPending() async { await health.retryIfPending() }

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
