import Foundation
import GearCore
import SwiftData

// Befehlsschicht und einziger Schreiber (ARCHITEKTUR A-03): jeder Befehl ist eine Transaktion inklusive
// Ledger-Neuberechnung der betroffenen Aktivitäten und Outbox-Eintrag. Schreibt nie die UI direkt.

enum PersistenceError: Error, Equatable {
    case emptyName
    case gearNotFound(UUID)
    case gearAlreadyExists(UUID)
    case activityAlreadyExists(UUID)
    case invalidDuration
    case invalidDistance
    case startsInFuture
    case component(ComponentPlanError)
    case maintenance(MaintenanceEntryError)
    case invalidRule
    case ruleNotFound(UUID)
    case notImplemented
}

/// Entscheidung des Nutzers zu Apple Health im Onboarding (SPEC S01 Schritt 2). Die Verbindung selbst kommt mit M3.
enum HealthChoice: String, Codable, Sendable {
    case undecided, later
}

struct OnboardingChoice: Sendable, Equatable {
    var categories: [SportCategory]
    var health: HealthChoice
}

/// Manuelle Aktivität (SPEC 6.4): Sportart, Beginn, Dauer, optional Distanz und Ausrüstung.
struct ManualActivityInput: Sendable, Equatable {
    var id = UUID()
    var sportType: SportType
    var startAt: Date
    var durationSeconds: Double
    /// `nil` = nicht gemessen; wird nie zu 0 (SPEC 5.2).
    var distanceMeters: Double?
    var gearIDs: [UUID]
}

enum GearCommand: Sendable {
    case createGear(GearItem)
    case renameGear(id: UUID, name: String)
    case setGearStatus(id: UUID, status: GearStatus, effectiveAt: Date)
    case addManualActivity(ManualActivityInput)
    case completeOnboarding(OnboardingChoice)
    // M5: Komponenten und Wartung
    /// Neues Teil anlegen und sofort montieren (Starter-Vorlage, SPEC S04).
    case addComponent(parent: UUID, item: GearItem, at: Date)
    case mountComponent(child: UUID, parent: UUID, at: Date)
    case unmountComponent(child: UUID, at: Date)
    case moveComponent(child: UUID, to: UUID, at: Date)
    /// „Ersetzen“ (SPEC 4.4): neues Teil, alte Montage endet, altes Teil optional einlagern/ausmustern.
    case replaceComponent(old: UUID, with: GearItem, oldBecomes: GearStatus?, at: Date)
    case recordMaintenance(MaintenanceInput)
    case setMaintenanceRule(MaintenanceRule)
    case removeMaintenanceRule(UUID)
}

/// Wartungseingabe (SPEC S07): Datum = jetzt, wenn `performedAt == nil`; alles Weitere optional.
struct MaintenanceInput: Sendable, Equatable {
    var id = UUID()
    var gearID: UUID
    var kind: MaintenanceKind
    var performedAt: Date?
    var measurement: Double?
    var costMinor: Int?
    var notes: String?
}

struct CommandOutcome: Sendable, Equatable {
    var gearID: UUID?
    var activityID: UUID?
}

struct AppSettingsValue: Sendable, Equatable {
    var onboardingCompleted: Bool
    var healthChoice: HealthChoice
    var importWindowDays: Int?
}

enum OutboxKind: String, Sendable, CaseIterable {
    case gearChanged, activityChanged, onboardingCompleted, dataReplaced, maintenanceChanged
}

struct OutboxItem: Sendable, Equatable, Identifiable {
    var id: UUID
    var kind: OutboxKind
    var subjectIDs: [UUID]
    var createdAt: Date
    var attempts: Int
    var lastError: String?
}

@ModelActor
actor PersistenceActor {
    // MARK: Schreiben

    /// Führt genau einen Befehl als Transaktion aus. Bei einem Fehler bleibt nichts zurück (Rollback), auch keine Outbox.
    func apply(_ command: GearCommand, now: Date) throws -> CommandOutcome {
        modelContext.autosaveEnabled = false
        do {
            let outcome = try perform(command, now: now)
            try modelContext.save()
            return outcome
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Ersetzt den gesamten Bestand (Testdaten, UI-Fixtures, später Backup-Wiederherstellung) in einem Commit.
    func load(_ dataset: GearDataset, now: Date = Date(timeIntervalSince1970: 0)) throws {
        modelContext.autosaveEnabled = false
        do {
            try deleteAll(GearEntity.self); try deleteAll(GearStatusChangeEntity.self); try deleteAll(InstallationEntity.self)
            try deleteAll(GearPresetEntity.self); try deleteAll(SportProfileEntity.self); try deleteAll(ActivityEntity.self)
            try deleteAll(ActivitySegmentEntity.self); try deleteAll(AssignmentEntity.self)
            try deleteAll(MaintenanceEventEntity.self); try deleteAll(MaintenanceRuleEntity.self)
            try deleteAll(AssignmentRuleEntity.self); try deleteAll(PendingEntity.self)
            dataset.gear.forEach { modelContext.insert(GearEntity($0)) }
            dataset.statusChanges.forEach { modelContext.insert(GearStatusChangeEntity($0)) }
            dataset.installations.forEach { modelContext.insert(InstallationEntity($0)) }
            dataset.presets.forEach { modelContext.insert(GearPresetEntity($0)) }
            dataset.sportProfiles.forEach { modelContext.insert(SportProfileEntity($0)) }
            dataset.activities.forEach { modelContext.insert(ActivityEntity($0)) }
            dataset.segments.forEach { modelContext.insert(ActivitySegmentEntity($0)) }
            dataset.assignments.forEach { modelContext.insert(AssignmentEntity($0)) }
            dataset.maintenanceEvents.forEach { modelContext.insert(MaintenanceEventEntity($0)) }
            dataset.maintenanceRules.forEach { modelContext.insert(MaintenanceRuleEntity($0)) }
            dataset.assignmentRules.forEach { modelContext.insert(AssignmentRuleEntity($0)) }
            dataset.pendings.forEach { modelContext.insert(PendingEntity($0)) }
            try rebuildLedgerAndSummaries(input: dataset.ledgerInput, gear: dataset.gear.map(\.id), now: now, replacingEverything: true)
            try enqueue(.dataReplaced, [], now: now)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Sicherheitsnetz (ARCHITEKTUR 4): Ledger und Summen vollständig aus den Wahrheitsdaten neu aufbauen.
    func rebuildAll(now: Date = Date(timeIntervalSince1970: 0)) throws {
        modelContext.autosaveEnabled = false
        do {
            let ds = try dataset()
            try rebuildLedgerAndSummaries(input: ds.ledgerInput, gear: ds.gear.map(\.id), now: now, replacingEverything: true)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Nach der Zustellung eines Outbox-Eintrags (siehe `OutboxDispatcher`).
    func markOutbox(_ id: UUID, delivered: Bool, error: String?, now: Date) throws {
        let rows = try modelContext.fetch(FetchDescriptor<OutboxEntity>(predicate: #Predicate { $0.id == id }))
        guard let row = rows.first else { return }
        row.attempts += 1
        row.lastError = delivered ? nil : error
        if delivered { row.processedAt = now }
        try modelContext.save()
    }

    // MARK: Lesen

    func dataset() throws -> GearDataset {
        var d = GearDataset()
        d.gear = try fetchAll(GearEntity.self).map(\.value).sortedByID()
        d.statusChanges = try fetchAll(GearStatusChangeEntity.self).map(\.value).sortedByID()
        d.installations = try fetchAll(InstallationEntity.self).map(\.value).sortedByID()
        d.presets = try fetchAll(GearPresetEntity.self).map(\.value).sortedByID()
        d.sportProfiles = try fetchAll(SportProfileEntity.self).map(\.value).sortedByID()
        d.activities = try fetchAll(ActivityEntity.self).map(\.value).sortedByID()
        d.segments = try fetchAll(ActivitySegmentEntity.self).map(\.value).sortedByID()
        d.assignments = try fetchAll(AssignmentEntity.self).map(\.value).sortedByID()
        d.maintenanceEvents = try fetchAll(MaintenanceEventEntity.self).map(\.value).sortedByID()
        d.maintenanceRules = try fetchAll(MaintenanceRuleEntity.self).map(\.value).sortedByID()
        d.assignmentRules = try fetchAll(AssignmentRuleEntity.self).map(\.value).sortedByID()
        d.pendings = try fetchAll(PendingEntity.self).map(\.value).sortedByID()
        return d
    }

    func ledger() throws -> [UsageLedgerEntry] {
        try fetchAll(LedgerEntryEntity.self).map(\.value).sorted { $0.key < $1.key }
    }

    /// Lebensdauer-Summe aus dem Cache; ohne Zeile „nichts gemessen“ (nie 0 erfinden).
    func usage(of gearID: UUID) throws -> UsageSummary {
        let rows = try modelContext.fetch(FetchDescriptor<GearUsageSummaryEntity>(predicate: #Predicate { $0.gearID == gearID }))
        return rows.first?.value ?? UsageSummary(uses: 0, distanceMeters: .noData, durationSeconds: .noData)
    }

    func settings() throws -> AppSettingsValue {
        let row = try fetchAll(AppSettingsEntity.self).first
        return AppSettingsValue(onboardingCompleted: row?.onboardingCompleted ?? false,
                                healthChoice: row.flatMap { HealthChoice(rawValue: $0.healthChoiceRaw) } ?? .undecided,
                                importWindowDays: row?.importWindowDays)
    }

    func outbox(pendingOnly: Bool) throws -> [OutboxItem] {
        let rows = try fetchAll(OutboxEntity.self).sorted { $0.sequence < $1.sequence }
        return rows.filter { !pendingOnly || $0.processedAt == nil }.map(\.value)
    }

    // MARK: Befehle

    private func perform(_ command: GearCommand, now: Date) throws -> CommandOutcome {
        switch command {
        case .createGear(let item): try createGear(item, now: now)
        case .renameGear(let id, let name): try renameGear(id, name, now: now)
        case .setGearStatus(let id, let status, let effectiveAt): try setStatus(id, status, effectiveAt: effectiveAt, now: now)
        case .addManualActivity(let input): try addManualActivity(input, now: now)
        case .completeOnboarding(let choice): try completeOnboarding(choice, now: now)
        default: throw PersistenceError.notImplemented
        }
    }

    private func createGear(_ item: GearItem, now: Date) throws -> CommandOutcome {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PersistenceError.emptyName }
        guard try gear(item.id) == nil else { throw PersistenceError.gearAlreadyExists(item.id) }
        var item = item
        item.name = name
        // Kein Zeitstempel übergeben (Standardwert Epoche): Zeitpunkt des Befehls.
        if item.createdAt == Date(timeIntervalSince1970: 0) { item.createdAt = now }
        modelContext.insert(GearEntity(item))
        modelContext.insert(GearStatusChangeEntity(GearStatusChange(gearID: item.id, status: item.status, effectiveAt: item.createdAt)))
        let summary = GearUsageSummaryEntity()
        summary.gearID = item.id
        summary.store(UsageSummary(uses: 0, distanceMeters: .noData, durationSeconds: .noData), at: now)
        modelContext.insert(summary)
        try enqueue(.gearChanged, [item.id], now: now)
        return CommandOutcome(gearID: item.id)
    }

    private func renameGear(_ id: UUID, _ name: String, now: Date) throws -> CommandOutcome {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PersistenceError.emptyName }
        guard let row = try gear(id) else { throw PersistenceError.gearNotFound(id) }
        row.name = name
        try enqueue(.gearChanged, [id], now: now)
        return CommandOutcome(gearID: id)
    }

    private func setStatus(_ id: UUID, _ status: GearStatus, effectiveAt: Date, now: Date) throws -> CommandOutcome {
        guard let row = try gear(id) else { throw PersistenceError.gearNotFound(id) }
        guard row.statusRaw != status.rawValue else { return CommandOutcome(gearID: id) }
        row.statusRaw = status.rawValue
        modelContext.insert(GearStatusChangeEntity(GearStatusChange(gearID: id, status: status, effectiveAt: effectiveAt)))
        try enqueue(.gearChanged, [id], now: now)
        return CommandOutcome(gearID: id)
    }

    private func addManualActivity(_ input: ManualActivityInput, now: Date) throws -> CommandOutcome {
        guard input.durationSeconds.isFinite, input.durationSeconds > 0 else { throw PersistenceError.invalidDuration }
        if let km = input.distanceMeters, !(km.isFinite && km >= 0) { throw PersistenceError.invalidDistance }
        // Kleine Toleranz für Uhrenabweichung; „später heute“ ist keine Aktivität, die schon stattgefunden hat.
        guard input.startAt <= now.addingTimeInterval(300) else { throw PersistenceError.startsInFuture }
        let id = input.id
        let existing = try modelContext.fetch(FetchDescriptor<ActivityEntity>(predicate: #Predicate { $0.id == id }))
        guard existing.isEmpty else { throw PersistenceError.activityAlreadyExists(input.id) }
        var gearIDs: [UUID] = []
        for g in input.gearIDs where !gearIDs.contains(g) { gearIDs.append(g) }
        for g in gearIDs {
            if try gear(g) == nil { throw PersistenceError.gearNotFound(g) }
        }

        let activity = ActivityRecord(id: input.id, source: .manual, sportType: input.sportType, startAt: input.startAt,
                                      endAt: input.startAt.addingTimeInterval(input.durationSeconds),
                                      distanceMeters: input.distanceMeters, durationSeconds: input.durationSeconds)
        modelContext.insert(ActivityEntity(activity))
        for g in gearIDs {
            modelContext.insert(AssignmentEntity(ActivityGearAssignment(activityID: input.id, gearID: g, origin: .manual, createdAt: now)))
        }
        let affected = try rebuildLedger(for: [input.id], now: now)
        try enqueue(.activityChanged, [input.id] + affected.sorted { $0.uuidString < $1.uuidString }, now: now)
        return CommandOutcome(activityID: input.id)
    }

    private func completeOnboarding(_ choice: OnboardingChoice, now: Date) throws -> CommandOutcome {
        let settings: AppSettingsEntity
        if let existing = try fetchAll(AppSettingsEntity.self).first {
            settings = existing
        } else {
            settings = AppSettingsEntity()
            settings.createdAt = now
            modelContext.insert(settings)
        }
        settings.onboardingCompleted = true
        settings.healthChoiceRaw = choice.health.rawValue
        var profiles: [UUID] = []
        for category in choice.categories {
            let raw = category.defaultSportType.rawValue
            if let existing = try modelContext.fetch(FetchDescriptor<SportProfileEntity>(predicate: #Predicate { $0.sportTypeRaw == raw })).first {
                existing.enabled = true
                profiles.append(existing.id)
            } else {
                let profile = SportProfile(sportType: category.defaultSportType)
                modelContext.insert(SportProfileEntity(profile))
                profiles.append(profile.id)
            }
        }
        try enqueue(.onboardingCompleted, profiles, now: now)
        return CommandOutcome()
    }

    // MARK: Ledger

    /// Baut das Ledger der genannten Aktivitäten neu und aktualisiert die Summen der betroffenen Gegenstände.
    /// Liefert die betroffenen Gegenstände (vorher und nachher).
    @discardableResult
    private func rebuildLedger(for activityIDs: Set<UUID>, now: Date) throws -> Set<UUID> {
        let ids = Array(activityIDs)
        let activities = try modelContext.fetch(FetchDescriptor<ActivityEntity>(predicate: #Predicate { ids.contains($0.id) })).map(\.value)
        let segments = try modelContext.fetch(FetchDescriptor<ActivitySegmentEntity>(predicate: #Predicate { ids.contains($0.activityID) })).map(\.value)
        let assignments = try modelContext.fetch(FetchDescriptor<AssignmentEntity>(predicate: #Predicate { ids.contains($0.activityID) })).map(\.value)
        let installations = try fetchAll(InstallationEntity.self).map(\.value)
        let result = LedgerBuilder.build(LedgerInput(activities: activities, segments: segments, assignments: assignments,
                                                      installations: installations), only: activityIDs)

        let old = try modelContext.fetch(FetchDescriptor<LedgerEntryEntity>(predicate: #Predicate { ids.contains($0.activityID) }))
        var affected = Set(old.map(\.gearID))
        old.forEach(modelContext.delete)
        for entry in result.entries {
            modelContext.insert(LedgerEntryEntity(entry))
            affected.insert(entry.gearID)
        }
        // Summen aus den unveränderten Einträgen (ohne die ersetzten Aktivitäten) plus den neuen Einträgen.
        for gearID in affected {
            let others = try modelContext.fetch(FetchDescriptor<LedgerEntryEntity>(
                predicate: #Predicate { $0.gearID == gearID && !ids.contains($0.activityID) })).map(\.value)
            let entries = (others + result.entries.filter { $0.gearID == gearID }).sorted { $0.key < $1.key }
            try storeSummary(for: gearID, entries: entries, now: now)
        }
        return affected
    }

    private func rebuildLedgerAndSummaries(input: LedgerInput, gear: [UUID], now: Date, replacingEverything: Bool) throws {
        try deleteAll(LedgerEntryEntity.self)
        try deleteAll(GearUsageSummaryEntity.self)
        let result = LedgerBuilder.build(input)
        result.entries.forEach { modelContext.insert(LedgerEntryEntity($0)) }
        let byGear = Dictionary(grouping: result.entries, by: \.gearID)
        for g in Set(gear).union(byGear.keys) {
            try storeSummary(for: g, entries: (byGear[g] ?? []).sorted { $0.key < $1.key }, now: now)
        }
    }

    private func storeSummary(for gearID: UUID, entries: [UsageLedgerEntry], now: Date) throws {
        let summary = UsageQuery(entries: entries, installations: []).lifetime(of: gearID)
        let rows = try modelContext.fetch(FetchDescriptor<GearUsageSummaryEntity>(predicate: #Predicate { $0.gearID == gearID }))
        let row: GearUsageSummaryEntity
        if let existing = rows.first {
            row = existing
        } else {
            row = GearUsageSummaryEntity()
            row.gearID = gearID
            modelContext.insert(row)
        }
        row.store(summary, at: now)
    }

    // MARK: Hilfen

    private func enqueue(_ kind: OutboxKind, _ subjects: [UUID], now: Date) throws {
        var top = FetchDescriptor<OutboxEntity>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        top.fetchLimit = 1
        let row = OutboxEntity()
        row.sequence = (try modelContext.fetch(top).first?.sequence ?? 0) + 1
        row.kindRaw = kind.rawValue
        row.subjectIDs = subjects
        row.createdAt = now
        modelContext.insert(row)
    }

    private func gear(_ id: UUID) throws -> GearEntity? {
        try modelContext.fetch(FetchDescriptor<GearEntity>(predicate: #Predicate { $0.id == id })).first
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try modelContext.fetch(FetchDescriptor<T>())
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        try fetchAll(type).forEach(modelContext.delete)
    }
}

private extension Array where Element: Identifiable, Element.ID == UUID {
    func sortedByID() -> [Element] { sorted { $0.id.uuidString < $1.id.uuidString } }
}

/// Stellt Outbox-Einträge nach dem Commit zu (ARCHITEKTUR A-04). Mindestens einmal: Handler müssen
/// idempotent sein (Schlüssel = `OutboxItem.id`). Ein fehlgeschlagener Eintrag bleibt offen und blockiert die anderen nicht.
protocol OutboxHandler: Sendable {
    func handle(_ item: OutboxItem) async throws
}

struct OutboxDispatcher: Sendable {
    let persistence: PersistenceActor

    /// Anzahl der erfolgreich zugestellten Einträge.
    func deliver(to handler: some OutboxHandler, now: Date) async -> Int {
        guard let items = try? await persistence.outbox(pendingOnly: true) else { return 0 }
        var delivered = 0
        for item in items {
            do {
                try await handler.handle(item)
                try await persistence.markOutbox(item.id, delivered: true, error: nil, now: now)
                delivered += 1
            } catch {
                // Kein Gesundheitswert in der Meldung: nur der Fehlertyp (CLAUDE.md).
                try? await persistence.markOutbox(item.id, delivered: false, error: String(describing: type(of: error)), now: now)
            }
        }
        return delivered
    }
}
