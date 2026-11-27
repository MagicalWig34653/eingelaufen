import Foundation
import GearCore
import SwiftData
import Testing
@testable import Eingelaufen

/// Testschema SchemaV1_1 nur im Testziel (ARCHITEKTUR 3.2, SPEC 14.2): GearEntity bekommt ein zusätzliches Attribut.
enum SchemaV1_1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 1, 0) }
    static var models: [any PersistentModel.Type] {
        SchemaV1.models.filter { $0 != SchemaV1.GearEntity.self } + [GearEntity.self]
    }

    @Model final class GearEntity {
        var id = UUID()
        var name = ""
        var purchaseDate: Date?
        var statusRaw = "active"
        var createdAt = Date(timeIntervalSince1970: 0)
        var categoryRaw = "other"
        var subtypeRaw: String?
        var imagePath: String?
        var isFavorite = false
        /// Neu in 1.1.
        var colorName: String?
        init() {}
    }
}

enum TestMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV1_1.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV1_1.self)] }
}

@Suite struct MigrationTests {
    @Test func storeWrittenWithSchemaV1OpensAsV1_1WithDataIntact() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString).store")
        defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let id = UUID()
        do {
            let c1 = try ModelContainer(for: Schema(versionedSchema: SchemaV1.self), configurations: ModelConfiguration(url: url))
            let ctx = ModelContext(c1)
            let g = SchemaV1.GearEntity()
            g.id = id
            g.name = "Vor der Migration"
            g.categoryRaw = "running"
            ctx.insert(g)
            try ctx.save()
        }
        let c2 = try ModelContainer(for: Schema(versionedSchema: SchemaV1_1.self), migrationPlan: TestMigrationPlan.self,
                                    configurations: ModelConfiguration(url: url))
        let items = try ModelContext(c2).fetch(FetchDescriptor<SchemaV1_1.GearEntity>())
        #expect(items.count == 1)
        #expect(items[0].id == id)
        #expect(items[0].name == "Vor der Migration")
        #expect(items[0].categoryRaw == "running")
        #expect(items[0].colorName == nil)
    }

    /// Schreibt einen vollständigen Bestand (alle Wahrheits-Entitäten, Foto am Rad) mit dem reinen SchemaV1 auf die Platte.
    private func writeV1Store(_ d: GearDataset, to url: URL) throws {
        let container = try ModelContainer(for: Schema(versionedSchema: SchemaV1.self), configurations: ModelConfiguration(url: url))
        let ctx = ModelContext(container)
        d.gear.forEach { ctx.insert(SchemaV1.GearEntity($0)) }
        d.statusChanges.forEach { ctx.insert(SchemaV1.GearStatusChangeEntity($0)) }
        d.installations.forEach { ctx.insert(SchemaV1.InstallationEntity($0)) }
        d.presets.forEach { ctx.insert(SchemaV1.GearPresetEntity($0)) }
        d.sportProfiles.forEach { ctx.insert(SchemaV1.SportProfileEntity($0)) }
        d.activities.forEach { ctx.insert(SchemaV1.ActivityEntity($0)) }
        d.segments.forEach { ctx.insert(SchemaV1.ActivitySegmentEntity($0)) }
        d.assignments.forEach { ctx.insert(SchemaV1.AssignmentEntity($0)) }
        d.maintenanceEvents.forEach { ctx.insert(SchemaV1.MaintenanceEventEntity($0)) }
        d.maintenanceRules.forEach { ctx.insert(SchemaV1.MaintenanceRuleEntity($0)) }
        d.assignmentRules.forEach { ctx.insert(SchemaV1.AssignmentRuleEntity($0)) }
        d.pendings.forEach { ctx.insert(SchemaV1.PendingEntity($0)) }
        try ctx.save()
    }

    private func photoDataset() -> GearDataset {
        var d = MapperTests.fullDataset()
        d.gear[0].photoPath = "gear/rad.jpg"
        return d
    }

    @Test("M8: voller SchemaV1-Bestand mit Foto migriert ins Testschema V1_1, nichts geht verloren")
    func fullV1StoreMigratesToTestSchema() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("full-v1-\(UUID().uuidString).store")
        defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let d = photoDataset()
        try writeV1Store(d, to: url)
        let c = try ModelContainer(for: Schema(versionedSchema: SchemaV1_1.self), migrationPlan: TestMigrationPlan.self,
                                   configurations: ModelConfiguration(url: url))
        let ctx = ModelContext(c)
        let gear = try ctx.fetch(FetchDescriptor<SchemaV1_1.GearEntity>())
        #expect(Set(gear.map(\.id)) == Set(d.gear.map(\.id)))
        #expect(gear.first { $0.id == d.gear[0].id }?.imagePath == "gear/rad.jpg")
        #expect(gear.allSatisfy { $0.colorName == nil })
        #expect(try ctx.fetchCount(FetchDescriptor<SchemaV1.GearStatusChangeEntity>()) == d.statusChanges.count)
        #expect(try ctx.fetchCount(FetchDescriptor<SchemaV1.InstallationEntity>()) == d.installations.count)
        #expect(try ctx.fetchCount(FetchDescriptor<SchemaV1.GearPresetEntity>()) == d.presets.count)
        #expect(try ctx.fetchCount(FetchDescriptor<SchemaV1.SportProfileEntity>()) == d.sportProfiles.count)
        #expect(try ctx.fetchCount(FetchDescriptor<SchemaV1.ActivityEntity>()) == d.activities.count)
        #expect(try ctx.fetchCount(FetchDescriptor<SchemaV1.ActivitySegmentEntity>()) == d.segments.count)
        #expect(try ctx.fetchCount(FetchDescriptor<SchemaV1.AssignmentEntity>()) == d.assignments.count)
        #expect(try ctx.fetchCount(FetchDescriptor<SchemaV1.MaintenanceEventEntity>()) == d.maintenanceEvents.count)
        #expect(try ctx.fetchCount(FetchDescriptor<SchemaV1.MaintenanceRuleEntity>()) == d.maintenanceRules.count)
        #expect(try ctx.fetchCount(FetchDescriptor<SchemaV1.AssignmentRuleEntity>()) == d.assignmentRules.count)
        #expect(try ctx.fetchCount(FetchDescriptor<SchemaV1.PendingEntity>()) == d.pendings.count)
    }

    @Test("M8: voller SchemaV1-Bestand mit Foto öffnet mit dem Produktionsplan (V2) unverändert, das Backup ist byte-gleich")
    func fullV1StoreMigratesToProductionWithIdenticalBackup() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("full-prod-\(UUID().uuidString).store")
        defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let d = photoDataset()
        try writeV1Store(d, to: url)
        let p = PersistenceActor(modelContainer: try Stores.makeContainer(inMemory: false, url: url))
        let migrated = try await p.dataset()
        #expect(normalized(migrated) == normalized(d))
        let before = try BackupCodec.encode(BackupDocument(exportedAt: t0, data: normalized(d)))
        let after = try BackupCodec.encode(BackupDocument(exportedAt: t0, data: normalized(migrated)))
        #expect(before == after)
    }

    @Test func productionPlanHasV1AndV2AndOpensAnOnDiskStoreTwice() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prod-\(UUID().uuidString).store")
        defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        #expect(GearMigrationPlan.schemas.count == 2)
        _ = try Stores.makeContainer(inMemory: false, url: url)
        _ = try Stores.makeContainer(inMemory: false, url: url)
    }
}
