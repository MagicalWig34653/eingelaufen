import Foundation
import GearCore
import HealthKit

actor HealthKitWorkoutSource: HealthWorkoutSource {
    static var readTypes: Set<HKObjectType> { [] }
    func requestAuthorization() async throws {}
    func fetchChanges(since: Date?, anchor: Data?) async throws -> WorkoutChanges { WorkoutChanges(batch: ImportBatch(), anchor: anchor) }
    func startObserving(_ handler: @escaping ObserverHandler) async throws {}
}

enum HKWorkoutMapper {
    static func incoming(_ workout: HKWorkout) -> IncomingWorkout {
        IncomingWorkout(sourceID: "", sportType: SportType(rawValue: 0), startAt: .distantPast, endAt: .distantPast, durationSeconds: 0)
    }
}
