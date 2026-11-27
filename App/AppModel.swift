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
    /// Meldung zum Verbinden mit Apple Health. Eigenes Feld, weil die auslösende Ansicht (auch im Blatt) sie zeigt:
    /// ein Hinweis an der Wurzel würde das Einstellungen-Blatt schließen.
    var healthError: String?

    /// Ziel nach einer Benachrichtigung („Andere auswählen“, „Prüfen“, Tippen auf die Meldung); `MainTabs` navigiert.
    var notificationRoute: NotificationRoute?
    let notifications: NotificationCoordinator

    private let health: HealthImporter

    init(container: ModelContainer, healthSource: any HealthWorkoutSource = HealthKitWorkoutSource(),
         notificationCenter: any NotificationCenterClient = SystemNotificationCenter()) {
        let persistence = PersistenceActor(modelContainer: container)
        let notifications = NotificationCoordinator(persistence: persistence, center: notificationCenter)
        self.persistence = persistence
        self.notifications = notifications
        // Auch Importe aus dem Hintergrundweckruf planen Benachrichtigungen, aber fragen nie nach der Erlaubnis.
        health = HealthImporter(source: healthSource, store: NotifyingImportStore(base: persistence, notifications: notifications),
                                now: { Date() })
    }

    // MARK: Benachrichtigungen (SPEC 7.2, 7.4)

    /// Abgleich mit der Mitteilungszentrale. `requestPermission` nur aus der Oberfläche (kontextbezogen, Kern entscheidet).
    func refreshNotifications(requestPermission: Bool) async {
        await notifications.refresh(now: Date(), requestPermission: requestPermission)
    }

    func notificationAuthorization() async -> NotificationAuthorization { await notifications.center.authorization() }

    /// Antwort aus der Mitteilungszentrale (auch im Hintergrund): derselbe Befehl wie im Posteingang.
    func handleNotification(actionIdentifier: String, categoryIdentifier: String, userInfo: [String: String]) async {
        switch await notifications.handle(actionIdentifier: actionIdentifier, categoryIdentifier: categoryIdentifier,
                                          userInfo: userInfo, now: Date()) {
        case .openInbox: notificationRoute = .inbox
        case .openMaintenance(let gearID): notificationRoute = .gear(gearID)
        case .resolve, .none: break
        }
    }

    // MARK: Apple Health (SPEC 6.1)

    /// Systemdialog für die Leserechte. Ein Erfolg sagt nichts darüber, was der Nutzer erlaubt hat (F-04).
    func requestHealthAccess() async -> Bool {
        do {
            try await health.requestAuthorization()
            return true
        } catch {
            healthError = error as? HealthSourceError == .unavailable
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
            // Seiteneffekte erst nach dem Commit (A-04). Benachrichtigungen gleichen danach den ganzen Stand ab (M6),
            // Live Activity folgt mit M7.
            _ = await OutboxDispatcher(persistence: persistence).deliver(to: NoSideEffects(), now: Date())
            // Nicht abwarten: Der Systemdialog zur Erlaubnis darf das Speichern nicht aufhalten.
            Task { await refreshNotifications(requestPermission: true) }
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

    static func message(for reason: PresetError) -> String {
        switch reason {
        case .emptyName: "Bitte gib dem Set einen Namen."
        case .noMembers: "Wähle mindestens ein Ausrüstungsteil."
        case .noSportTypes: "Wähle mindestens eine Sportart."
        case .unknownGear: "Diese Ausrüstung gibt es nicht mehr."
        case .presetNotFound: "Dieses Set gibt es nicht mehr."
        case .presetDoesNotCover: "Das Set gehört nicht zu dieser Sportart."
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
        case .pendingNotFound: "Diese Zuordnung gibt es nicht mehr."
        case .activityNotFound: "Diese Aktivität gibt es nicht mehr."
        case .preset(let reason): Self.message(for: reason)
        case nil: "Das hat nicht geklappt. Bitte versuche es noch einmal."
        }
    }
}

enum NotificationRoute: Hashable { case inbox, gear(UUID) }

/// Import-Speicher, der nach jedem Import-Commit die Benachrichtigungen abgleicht (Seiteneffekt nach Commit, A-04).
struct NotifyingImportStore: ImportStore {
    let base: PersistenceActor
    let notifications: NotificationCoordinator

    func importState() async throws -> ImportState { try await base.importState() }
    func commitImport(_ changes: WorkoutChanges, since: Date?, now: Date) async throws -> ImportSummary {
        let summary = try await base.commitImport(changes, since: since, now: now)
        await notifications.refresh(now: now, requestPermission: false)
        return summary
    }
    func recordImportFailure(_ failure: ImportFailure, now: Date) async throws { try await base.recordImportFailure(failure, now: now) }
}

/// Outbox-Handler: Benachrichtigungen gleichen nach der Zustellung den ganzen Stand ab (`NotificationCoordinator.refresh`),
/// Live Activity kommt mit M7.
struct NoSideEffects: OutboxHandler {
    func handle(_ item: OutboxItem) async throws {}
}
