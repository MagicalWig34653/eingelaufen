import Foundation
import GearCore
import SwiftData

/// SchemaV1: alle Entitäten der Spec 5.1 plus die in ARCHITEKTUR 3.1 ergänzten (P-04).
/// Regeln (ARCHITEKTUR 3.2): stabile UUIDs, Beziehungen nur über IDs, keine Kaskaden, keine `@Attribute(.unique)`
/// (Upsert würde still überschreiben; Eindeutigkeit prüft der `PersistenceActor`). Enums liegen als Rohwert-String,
/// fehlende Werte sind `nil`, nie `0` (A-08). Vor dem ersten TestFlight-Build darf V1 frei geändert werden.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            GearEntity.self, GearStatusChangeEntity.self, InstallationEntity.self, GearPresetEntity.self,
            SportProfileEntity.self, ActivityEntity.self, ActivitySegmentEntity.self, AssignmentEntity.self,
            MaintenanceEventEntity.self, MaintenanceRuleEntity.self, AssignmentRuleEntity.self, PendingEntity.self,
            AppSettingsEntity.self, ImportCursorEntity.self, NotificationRecordEntity.self,
            LedgerEntryEntity.self, GearUsageSummaryEntity.self, OutboxEntity.self,
        ]
    }

    // MARK: Wahrheit (vom Nutzer oder Import)

    @Model final class GearEntity {
        var id = UUID()
        var name = ""
        var purchaseDate: Date?
        var statusRaw = GearStatus.active.rawValue
        var createdAt = Date(timeIntervalSince1970: 0)
        var categoryRaw = SportCategory.other.rawValue
        var subtypeRaw: String?
        /// Relativer Pfad unter Application Support/Media (ARCHITEKTUR 3.2); Fotos folgen in einer späteren Stufe.
        var imagePath: String?
        var isFavorite = false

        init() {}
        init(_ g: GearItem) { update(from: g) }

        func update(from g: GearItem) {
            id = g.id
            name = g.name
            purchaseDate = g.purchaseDate
            statusRaw = g.status.rawValue
            createdAt = g.createdAt
            categoryRaw = g.category.rawValue
            subtypeRaw = g.subtype?.rawValue
        }

        var value: GearItem {
            GearItem(id: id, name: name, purchaseDate: purchaseDate, status: GearStatus(rawValue: statusRaw) ?? .active,
                     createdAt: createdAt, category: SportCategory(rawValue: categoryRaw) ?? .other,
                     subtype: subtypeRaw.flatMap(SportSubtype.init(rawValue:)))
        }
    }

    @Model final class GearStatusChangeEntity {
        var id = UUID()
        var gearID = UUID()
        var statusRaw = GearStatus.active.rawValue
        var effectiveAt = Date(timeIntervalSince1970: 0)

        init() {}
        init(_ c: GearStatusChange) {
            id = c.id
            gearID = c.gearID
            statusRaw = c.status.rawValue
            effectiveAt = c.effectiveAt
        }

        var value: GearStatusChange {
            GearStatusChange(id: id, gearID: gearID, status: GearStatus(rawValue: statusRaw) ?? .active, effectiveAt: effectiveAt)
        }
    }

    @Model final class InstallationEntity {
        var id = UUID()
        var parentGearID = UUID()
        var childGearID = UUID()
        var startedAt = Date(timeIntervalSince1970: 0)
        var endedAt: Date?
        var notes: String?

        init() {}
        init(_ i: Installation) {
            id = i.id
            parentGearID = i.parentGearID
            childGearID = i.childGearID
            startedAt = i.startedAt
            endedAt = i.endedAt
            notes = i.notes
        }

        var value: Installation {
            Installation(id: id, parentGearID: parentGearID, childGearID: childGearID, startedAt: startedAt, endedAt: endedAt, notes: notes)
        }
    }

    @Model final class GearPresetEntity {
        var id = UUID()
        var name = ""
        var sportTypeRaws: [Int] = []
        var memberGearIDs: [UUID] = []
        var isEnabled = true

        init() {}
        init(_ p: GearPreset) {
            id = p.id
            name = p.name
            sportTypeRaws = p.sportTypes.map(\.rawValue)
            memberGearIDs = p.memberGearIDs
            isEnabled = p.isEnabled
        }

        var value: GearPreset {
            GearPreset(id: id, name: name, sportTypes: sportTypeRaws.map(SportType.init(rawValue:)),
                       memberGearIDs: memberGearIDs, isEnabled: isEnabled)
        }
    }

    @Model final class SportProfileEntity {
        var id = UUID()
        var sportTypeRaw = 0
        var enabled = true
        var defaultPresetID: UUID?
        var notificationLevelRaw = NotificationLevel.assignmentOnly.rawValue

        init() {}
        init(_ s: SportProfile) {
            id = s.id
            sportTypeRaw = s.sportType.rawValue
            enabled = s.enabled
            defaultPresetID = s.defaultPresetID
            notificationLevelRaw = s.notificationLevel.rawValue
        }

        var value: SportProfile {
            SportProfile(id: id, sportType: SportType(rawValue: sportTypeRaw), enabled: enabled, defaultPresetID: defaultPresetID,
                         notificationLevel: NotificationLevel(rawValue: notificationLevelRaw) ?? .assignmentOnly)
        }
    }

    @Model final class ActivityEntity {
        var id = UUID()
        var sourceRaw = ActivitySource.manual.rawValue
        var sourceID: String?
        var sportTypeRaw = 0
        var startAt = Date(timeIntervalSince1970: 0)
        var endAt = Date(timeIntervalSince1970: 0)
        /// `nil` = nicht gemessen (SPEC 5.2).
        var distanceMeters: Double?
        var durationSeconds = 0.0
        var deletedAt: Date?
        var isIndoor: Bool?
        var revision = 1
        // Für den HealthKit-Import (M3); manuelle Aktivitäten lassen sie leer.
        var sourceBundleID: String?
        var sourceName: String?
        var missingInSourceSince: Date?

        init() {}
        init(_ a: ActivityRecord) {
            id = a.id
            sourceRaw = a.source.rawValue
            sourceID = a.sourceID
            sportTypeRaw = a.sportType.rawValue
            startAt = a.startAt
            endAt = a.endAt
            distanceMeters = a.distanceMeters
            durationSeconds = a.durationSeconds
            deletedAt = a.deletedAt
            isIndoor = a.isIndoor
            revision = a.revision
        }

        var value: ActivityRecord {
            ActivityRecord(id: id, source: ActivitySource(rawValue: sourceRaw) ?? .manual, sourceID: sourceID,
                           sportType: SportType(rawValue: sportTypeRaw), startAt: startAt, endAt: endAt,
                           distanceMeters: distanceMeters, durationSeconds: durationSeconds, deletedAt: deletedAt,
                           isIndoor: isIndoor, revision: revision)
        }
    }

    @Model final class ActivitySegmentEntity {
        var id = UUID()
        var activityID = UUID()
        var sportTypeRaw = 0
        var startAt = Date(timeIntervalSince1970: 0)
        var endAt = Date(timeIntervalSince1970: 0)
        var distanceMeters: Double?

        init() {}
        init(_ s: ActivitySegment) {
            id = s.id
            activityID = s.activityID
            sportTypeRaw = s.sportType.rawValue
            startAt = s.startAt
            endAt = s.endAt
            distanceMeters = s.distanceMeters
        }

        var value: ActivitySegment {
            ActivitySegment(id: id, activityID: activityID, sportType: SportType(rawValue: sportTypeRaw),
                            startAt: startAt, endAt: endAt, distanceMeters: distanceMeters)
        }
    }

    @Model final class AssignmentEntity {
        var id = UUID()
        var activityID = UUID()
        var segmentID: UUID?
        var gearID = UUID()
        var originRaw = AssignmentOrigin.manual.rawValue
        var createdAt = Date(timeIntervalSince1970: 0)

        init() {}
        init(_ a: ActivityGearAssignment) {
            id = a.id
            activityID = a.activityID
            segmentID = a.segmentID
            gearID = a.gearID
            originRaw = a.origin.rawValue
            createdAt = a.createdAt
        }

        var value: ActivityGearAssignment {
            ActivityGearAssignment(id: id, activityID: activityID, segmentID: segmentID, gearID: gearID,
                                   origin: AssignmentOrigin(rawValue: originRaw) ?? .manual, createdAt: createdAt)
        }
    }

    @Model final class MaintenanceEventEntity {
        var id = UUID()
        var gearID = UUID()
        var kindRaw = MaintenanceKind.custom.rawValue
        var performedAt = Date(timeIntervalSince1970: 0)
        var measurement: Double?
        var costMinor: Int?
        var notes: String?

        init() {}
        init(_ e: MaintenanceEvent) {
            id = e.id
            gearID = e.gearID
            kindRaw = e.kind.rawValue
            performedAt = e.performedAt
            measurement = e.measurement
            costMinor = e.costMinor
            notes = e.notes
        }

        var value: MaintenanceEvent {
            MaintenanceEvent(id: id, gearID: gearID, kind: MaintenanceKind(rawValue: kindRaw) ?? .custom,
                             performedAt: performedAt, measurement: measurement, costMinor: costMinor, notes: notes)
        }
    }

    @Model final class MaintenanceRuleEntity {
        var id = UUID()
        var gearID = UUID()
        var kindRaw = MaintenanceKind.inspected.rawValue
        var metricRaw = UsageMetricKind.distance.rawValue
        var intervalValue = 0.0
        var warningLeadValue: Double?
        var enabled = true

        init() {}
        init(_ r: MaintenanceRule) {
            id = r.id
            gearID = r.gearID
            kindRaw = r.kind.rawValue
            metricRaw = r.metric.rawValue
            intervalValue = r.intervalValue
            warningLeadValue = r.warningLeadValue
            enabled = r.enabled
        }

        var value: MaintenanceRule {
            MaintenanceRule(id: id, gearID: gearID, kind: MaintenanceKind(rawValue: kindRaw) ?? .inspected,
                            metric: UsageMetricKind(rawValue: metricRaw) ?? .distance, intervalValue: intervalValue,
                            warningLeadValue: warningLeadValue, enabled: enabled)
        }
    }

    @Model final class AssignmentRuleEntity {
        var id = UUID()
        var sportTypeRaw = 0
        var kindRaw = AssignmentRuleKind.explicitDefault.rawValue
        /// `RuleConditions` als JSON (sortierte Wochentage): bleibt unabhängig von künftigen Bedingungsfeldern.
        var conditionsData = Data()
        var gearIDs: [UUID] = []
        var priority = 0
        var enabled = true
        var createdAt = Date(timeIntervalSince1970: 0)

        init() {}
        init(_ r: AssignmentRule) {
            id = r.id
            sportTypeRaw = r.sportType.rawValue
            kindRaw = r.kind.rawValue
            conditionsData = (try? JSONEncoder().encode(r.conditions)) ?? Data()
            gearIDs = r.gearIDs
            priority = r.priority
            enabled = r.enabled
            createdAt = r.createdAt
        }

        var value: AssignmentRule {
            AssignmentRule(id: id, sportType: SportType(rawValue: sportTypeRaw),
                           kind: AssignmentRuleKind(rawValue: kindRaw) ?? .explicitDefault,
                           conditions: (try? JSONDecoder().decode(RuleConditions.self, from: conditionsData)) ?? RuleConditions(),
                           gearIDs: gearIDs, priority: priority, enabled: enabled, createdAt: createdAt)
        }
    }

    // MARK: Zustand von Abläufen

    @Model final class PendingEntity {
        var id = UUID()
        var activityID = UUID()
        var stateRaw = PendingState.unresolved.rawValue
        var proposedGearIDs: [UUID] = []
        var alternativesData = Data()
        var candidateGearIDs: [UUID] = []
        var reasonData: Data?
        var confidenceRaw = Confidence.none.rawValue
        var proposalRevision = 1
        var createdAt = Date(timeIntervalSince1970: 0)
        var lastPromptAt: Date?
        var resolutionRaw = PendingResolution.none.rawValue

        init() {}
        init(_ p: PendingAssignment) {
            id = p.id
            activityID = p.activityID
            stateRaw = p.state.rawValue
            proposedGearIDs = p.proposedGearIDs
            alternativesData = (try? JSONEncoder().encode(p.alternatives)) ?? Data()
            candidateGearIDs = p.candidateGearIDs
            reasonData = p.reason.flatMap { try? JSONEncoder().encode($0) }
            confidenceRaw = p.confidence.rawValue
            proposalRevision = p.proposalRevision
            createdAt = p.createdAt
            lastPromptAt = p.lastPromptAt
            resolutionRaw = p.resolution.rawValue
        }

        var value: PendingAssignment {
            PendingAssignment(
                id: id, activityID: activityID, state: PendingState(rawValue: stateRaw) ?? .unresolved,
                proposedGearIDs: proposedGearIDs,
                alternatives: (try? JSONDecoder().decode([[UUID]].self, from: alternativesData)) ?? [],
                candidateGearIDs: candidateGearIDs,
                reason: reasonData.flatMap { try? JSONDecoder().decode(AssignmentReason.self, from: $0) },
                confidence: Confidence(rawValue: confidenceRaw) ?? .none, proposalRevision: proposalRevision,
                createdAt: createdAt, lastPromptAt: lastPromptAt,
                resolution: PendingResolution(rawValue: resolutionRaw) ?? .none)
        }
    }

    /// Genau eine Zeile (feste ID). Nutzereinstellungen, die nicht im Kern liegen (Kern kennt `AppSettings` nicht, siehe BackupDocument).
    @Model final class AppSettingsEntity {
        static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A5")!
        var id = AppSettingsEntity.singletonID
        var onboardingCompleted = false
        var healthChoiceRaw = HealthChoice.undecided.rawValue
        /// Zeitraum des Erstimports in Tagen (M3); `nil` = noch nicht gewählt.
        var importWindowDays: Int?
        var createdAt = Date(timeIntervalSince1970: 0)

        init() {}
    }

    /// HealthKit-Anker und Importzustand (M3). Der Anker wird im selben Commit wie die Datensätze gespeichert.
    @Model final class ImportCursorEntity {
        var id = UUID()
        var sourceRaw = "healthKit"
        var anchorData: Data?
        var lastSuccessAt: Date?
        var lastError: String?
        var retryPending = false

        init() {}
    }

    @Model final class NotificationRecordEntity {
        var id = UUID()
        var pendingID = UUID()
        var proposalRevision = 1
        var identifier = ""
        var scheduledAt = Date(timeIntervalSince1970: 0)
        var deliveredAt: Date?

        init() {}
    }

    // MARK: Abgeleitet (jederzeit neu erzeugbar)

    @Model final class LedgerEntryEntity {
        var id = UUID()
        var activityID = UUID()
        var segmentID: UUID?
        var gearID = UUID()
        var occurredAt = Date(timeIntervalSince1970: 0)
        var distanceMeters: Double?
        var durationSeconds: Double?
        var uses = 1
        var derivationVersion = 1

        init() {}
        init(_ e: UsageLedgerEntry) {
            activityID = e.activityID
            segmentID = e.segmentID
            gearID = e.gearID
            occurredAt = e.occurredAt
            distanceMeters = e.distanceMeters
            durationSeconds = e.durationSeconds
            uses = e.uses
            derivationVersion = e.derivationVersion
        }

        var value: UsageLedgerEntry {
            UsageLedgerEntry(key: LedgerKey(activityID: activityID, segmentID: segmentID, gearID: gearID),
                             occurredAt: occurredAt, distanceMeters: distanceMeters, durationSeconds: durationSeconds,
                             uses: uses, derivationVersion: derivationVersion)
        }
    }

    /// Cache der Lebensdauer-Summen je Gegenstand für schnelle Listen (Spec 13), nie alleinige Wahrheit.
    @Model final class GearUsageSummaryEntity {
        var gearID = UUID()
        var uses = 0
        var distanceMeters: Double?
        var distanceIsComplete = true
        var durationSeconds: Double?
        var durationIsComplete = true
        var updatedAt = Date(timeIntervalSince1970: 0)

        init() {}

        func store(_ s: UsageSummary, at now: Date) {
            uses = s.uses
            (distanceMeters, distanceIsComplete) = Self.flatten(s.distanceMeters)
            (durationSeconds, durationIsComplete) = Self.flatten(s.durationSeconds)
            updatedAt = now
        }

        var value: UsageSummary {
            UsageSummary(uses: uses, distanceMeters: Self.metric(distanceMeters, distanceIsComplete),
                         durationSeconds: Self.metric(durationSeconds, durationIsComplete))
        }

        private static func flatten(_ m: Metric<Double>) -> (Double?, Bool) {
            switch m {
            case .noData: (nil, true)
            case .measured(let v, let complete): (v, complete)
            case .estimate(let v, _): (v, false)   // Lebensdauer wird nie geschätzt; falls doch: als unvollständig sichern.
            }
        }

        private static func metric(_ v: Double?, _ complete: Bool) -> Metric<Double> {
            v.map { .measured($0, isComplete: complete) } ?? .noData
        }
    }

    /// Outbox (ARCHITEKTUR A-04): wird im selben Commit wie die Änderung geschrieben, danach zugestellt.
    @Model final class OutboxEntity {
        var id = UUID()
        /// Zustellreihenfolge: aufsteigend, unabhängig von gleichen Zeitstempeln.
        var sequence = 0
        var kindRaw = OutboxKind.gearChanged.rawValue
        var subjectIDs: [UUID] = []
        var createdAt = Date(timeIntervalSince1970: 0)
        var processedAt: Date?
        var attempts = 0
        var lastError: String?

        init() {}

        var value: OutboxItem {
            OutboxItem(id: id, kind: OutboxKind(rawValue: kindRaw) ?? .gearChanged, subjectIDs: subjectIDs,
                       createdAt: createdAt, attempts: attempts, lastError: lastError)
        }
    }
}

typealias GearEntity = SchemaV1.GearEntity
typealias GearStatusChangeEntity = SchemaV1.GearStatusChangeEntity
typealias InstallationEntity = SchemaV1.InstallationEntity
typealias GearPresetEntity = SchemaV1.GearPresetEntity
typealias SportProfileEntity = SchemaV1.SportProfileEntity
typealias ActivityEntity = SchemaV1.ActivityEntity
typealias ActivitySegmentEntity = SchemaV1.ActivitySegmentEntity
typealias AssignmentEntity = SchemaV1.AssignmentEntity
typealias MaintenanceEventEntity = SchemaV1.MaintenanceEventEntity
typealias MaintenanceRuleEntity = SchemaV1.MaintenanceRuleEntity
typealias AssignmentRuleEntity = SchemaV1.AssignmentRuleEntity
typealias PendingEntity = SchemaV1.PendingEntity
typealias AppSettingsEntity = SchemaV1.AppSettingsEntity
typealias ImportCursorEntity = SchemaV1.ImportCursorEntity
typealias NotificationRecordEntity = SchemaV1.NotificationRecordEntity
typealias LedgerEntryEntity = SchemaV1.LedgerEntryEntity
typealias GearUsageSummaryEntity = SchemaV1.GearUsageSummaryEntity
typealias OutboxEntity = SchemaV1.OutboxEntity

enum GearMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    /// Noch keine Stufen: V1 ist das erste Schema. Die Testmigration V1 → V1_1 liegt im Testziel (SPEC 14.2).
    static var stages: [MigrationStage] { [] }
}

enum Stores {
    /// `url == nil` und `inMemory == false`: Standardablage der App (Application Support).
    static func makeContainer(inMemory: Bool, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration("Eingelaufen", schema: schema, isStoredInMemoryOnly: true)
        } else if let url {
            configuration = ModelConfiguration(schema: schema, url: url)
        } else {
            configuration = ModelConfiguration("Eingelaufen", schema: schema)
        }
        return try ModelContainer(for: schema, migrationPlan: GearMigrationPlan.self, configurations: configuration)
    }
}
