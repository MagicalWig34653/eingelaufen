import Foundation
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

    @Test func productionPlanStartsAtV1AndOpensAnOnDiskStoreTwice() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prod-\(UUID().uuidString).store")
        defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        #expect(GearMigrationPlan.schemas.count == 1)
        _ = try Stores.makeContainer(inMemory: false, url: url)
        _ = try Stores.makeContainer(inMemory: false, url: url)
    }
}
