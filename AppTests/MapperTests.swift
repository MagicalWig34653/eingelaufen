import Foundation
import GearCore
import SwiftData
import Testing
@testable import Eingelaufen

/// Mapper Kern ↔ SwiftData: jede Wahrheits-Entität verlustfrei (SchemaV1 vollständig, T-14-Grundlage).
@Suite struct MapperTests {
    static func fullDataset() -> GearDataset {
        let bike = GearItem(name: "Rad", purchaseDate: day(-100), status: .stored, createdAt: day(-90), category: .cycling, subtype: .gravel)
        let chain = GearItem(name: "Kette", createdAt: day(-90), category: .cycling)
        let act = ActivityRecord(source: .healthKit, sourceID: "hk-1", sportType: SportType(rawValue: 13), startAt: day(1),
                                 endAt: day(1).addingTimeInterval(3_600), distanceMeters: 31_500.5, durationSeconds: 3_600,
                                 deletedAt: nil, isIndoor: false, revision: 3)
        let seg = ActivitySegment(activityID: act.id, sportType: SportType(rawValue: 46), startAt: day(1),
                                  endAt: day(1).addingTimeInterval(600), distanceMeters: nil)
        var d = GearDataset()
        d.gear = [bike, chain]
        d.statusChanges = [GearStatusChange(gearID: bike.id, status: .stored, effectiveAt: day(-10))]
        d.installations = [Installation(parentGearID: bike.id, childGearID: chain.id, startedAt: day(-50), endedAt: day(-5), notes: "Neu")]
        d.presets = [GearPreset(name: "Rennrad-Set", sportTypes: [SportType(rawValue: 13), SportType(rawValue: 74)], memberGearIDs: [bike.id, chain.id], isEnabled: false)]
        d.sportProfiles = [SportProfile(sportType: SportType(rawValue: 13), enabled: true, defaultPresetID: d.presets[0].id, notificationLevel: .assignmentAndMaintenance)]
        d.activities = [act]
        d.segments = [seg]
        d.assignments = [ActivityGearAssignment(activityID: act.id, segmentID: seg.id, gearID: bike.id, origin: .confirmedProposal, createdAt: day(2))]
        d.maintenanceEvents = [MaintenanceEvent(gearID: chain.id, kind: .wearMeasured, performedAt: day(3), measurement: 0.5, costMinor: 1_299, notes: "Lehre")]
        d.maintenanceRules = [MaintenanceRule(gearID: chain.id, kind: .inspected, metric: .distance, intervalValue: 2_500_000, warningLeadValue: 250_000, enabled: false)]
        d.assignmentRules = [AssignmentRule(sportType: SportType(rawValue: 13), kind: .remembered,
                                            conditions: RuleConditions(isIndoor: true, weekdays: [2, 4]),
                                            gearIDs: [bike.id], priority: 7, enabled: true, createdAt: day(4))]
        d.pendings = [PendingAssignment(activityID: act.id, state: .suggested, proposedGearIDs: [bike.id],
                                        alternatives: [[chain.id], [bike.id, chain.id]], candidateGearIDs: [bike.id, chain.id],
                                        reason: .rule(d.assignmentRules[0].id), confidence: .high, proposalRevision: 4,
                                        createdAt: day(5), lastPromptAt: day(6), resolution: .none)]
        return d
    }

    @Test func everyTruthEntityRoundTripsThroughSwiftData() async throws {
        let p = try makePersistence()
        let input = Self.fullDataset()
        try await p.load(input)
        #expect(normalized(try await p.dataset()) == normalized(input))
    }

    @Test func loadReplacesEverythingAndRebuildsLedger() async throws {
        let p = try makePersistence()
        try await p.load(Self.fullDataset())
        var other = GearDataset()
        other.gear = [GearItem(name: "Nur das", createdAt: t0)]
        try await p.load(other)
        let ds = try await p.dataset()
        #expect(ds.gear.map(\.name) == ["Nur das"])
        #expect(ds.activities.isEmpty && ds.pendings.isEmpty && ds.installations.isEmpty)
        #expect(try await p.ledger().isEmpty)
    }

    @Test func storedDatasetPassesBackupValidatorAndRoundTripsAsJSON() async throws {
        let p = try makePersistence()
        try await p.load(Self.fullDataset())
        let doc = BackupDocument(exportedAt: t0, data: try await p.dataset())
        #expect(BackupValidator.validate(doc).filter { !$0.isWarning }.isEmpty)
        let decoded = try BackupCodec.decode(try BackupCodec.encode(doc))
        #expect(normalized(decoded.data) == normalized(doc.data))
    }

    @Test func schemaContainsAllEntitiesOfSpec51() {
        let names = Set(SchemaV1.models.map { String(describing: $0).split(separator: ".").last.map(String.init) ?? "" })
        let required: Set<String> = [
            "GearEntity", "GearStatusChangeEntity", "InstallationEntity", "GearPresetEntity", "SportProfileEntity",
            "ActivityEntity", "ActivitySegmentEntity", "AssignmentEntity", "MaintenanceEventEntity", "MaintenanceRuleEntity",
            "AssignmentRuleEntity", "PendingEntity", "AppSettingsEntity", "ImportCursorEntity", "NotificationRecordEntity",
            "LedgerEntryEntity", "GearUsageSummaryEntity", "OutboxEntity",
        ]
        #expect(names == required)
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    }
}
