import Foundation
import GearCore

extension PersistenceActor: ImportStore {
    func importState() async throws -> ImportState { ImportState(isEnabled: false) }
    func commitImport(_ changes: WorkoutChanges, since: Date?, now: Date) async throws -> ImportSummary { ImportSummary() }
    func recordImportFailure(_ failure: ImportFailure, now: Date) async throws {}
}
