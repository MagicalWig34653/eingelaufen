import Foundation
import GearCore
import HealthKit

/// Echte Trainingsquelle (SPEC 6.1, PLATTFORM F-01…F-06): nur lesen, verankerte Abfrage, Beobachter mit
/// Background Delivery. Auf dem Gerät noch nicht erprobt (Spike S-1).
actor HealthKitWorkoutSource: HealthWorkoutSource {
    private let store = HKHealthStore()
    private var observer: HKObserverQuery?

    /// Trainings und die Distanzarten, aus denen die Trainingsdistanz stammt. Sonst nichts.
    static var readTypes: Set<HKObjectType> {
        Set([HKObjectType.workoutType()]
            + WorkoutDistanceKind.allCases.map { HKQuantityType(HKWorkoutMapper.identifier(for: $0)) })
    }

    func requestAuthorization() async throws {
        try ensureAvailable()
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
        } catch {
            throw Self.map(error)
        }
    }

    func fetchChanges(since: Date?, anchor: Data?) async throws -> WorkoutChanges {
        try ensureAvailable()
        let window = since.map { HKQuery.predicateForSamples(withStart: $0, end: nil, options: .strictStartDate) }
        // Unlesbarer Anker: von vorn abfragen, der Import ist idempotent.
        let previous = anchor.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
        do {
            let result = try await HKAnchoredObjectQueryDescriptor(predicates: [.workout(window)], anchor: previous)
                .result(for: store)
            let next = try NSKeyedArchiver.archivedData(withRootObject: result.newAnchor, requiringSecureCoding: true)
            let batch = ImportBatch(upserts: result.addedSamples.map(HKWorkoutMapper.incoming),
                                    deletedSourceIDs: result.deletedObjects.map(\.uuid.uuidString))
            return WorkoutChanges(batch: batch, anchor: next)
        } catch {
            throw Self.map(error)
        }
    }

    func startObserving(_ handler: @escaping ObserverHandler) async throws {
        try ensureAvailable()
        if observer == nil {
            let query = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { _, completion, error in
                // HealthKits Handler ist nicht als Sendable deklariert, darf aber von jedem Thread gerufen werden.
                nonisolated(unsafe) let done = completion
                handler(error.map(HealthKitWorkoutSource.map)) { done() }
            }
            store.execute(query)
            observer = query
        }
        do {
            // Bei jedem Start erneut (F-02). Wie oft wirklich geweckt wird, misst S-1 (F-01).
            try await store.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate)
        } catch {
            throw Self.map(error)
        }
    }

    private func ensureAvailable() throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthSourceError.unavailable }
    }

    /// Nur Fehlercode, keine Gesundheitswerte.
    private static func map(_ error: any Error) -> HealthSourceError {
        switch (error as? HKError)?.code {
        case .errorDatabaseInaccessible: .databaseInaccessible
        case .errorHealthDataUnavailable: .unavailable
        default: .failed("HealthKit \((error as NSError).code)")
        }
    }
}

/// `HKWorkout` → Kernwerte (ARCHITEKTUR 5.1).
enum HKWorkoutMapper {
    static func identifier(for kind: WorkoutDistanceKind) -> HKQuantityTypeIdentifier {
        switch kind {
        case .cycling: .distanceCycling
        case .walkingRunning: .distanceWalkingRunning
        case .wheelchair: .distanceWheelchair
        case .swimming: .distanceSwimming
        case .downhillSnowSports: .distanceDownhillSnowSports
        case .crossCountrySkiing: .distanceCrossCountrySkiing
        case .paddleSports: .distancePaddleSports
        case .rowing: .distanceRowing
        case .skatingSports: .distanceSkatingSports
        }
    }

    static func incoming(_ workout: HKWorkout) -> IncomingWorkout {
        let type = sportType(workout.workoutActivityType)
        let parts = workout.workoutActivities.map { part in
            let sport = sportType(part.workoutConfiguration.activityType)
            return IncomingSegment(sportType: sport, startAt: part.startDate, endAt: part.endDate ?? workout.endDate,
                                   distanceMeters: distance(sport) { part.statistics(for: $0) })
        }
        let source = workout.sourceRevision.source
        return IncomingWorkout(
            sourceID: workout.uuid.uuidString, sportType: type, startAt: workout.startDate, endAt: workout.endDate,
            distanceMeters: distance(type) { workout.statistics(for: $0) }, durationSeconds: workout.duration,
            isIndoor: workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool,
            sourceBundleID: source.bundleIdentifier, sourceName: source.name,
            segments: IncomingWorkout.multisportSegments(parts))
    }

    private static func sportType(_ type: HKWorkoutActivityType) -> SportType {
        SportType(rawValue: Int(type.rawValue))
    }

    /// Ohne passende Distanzart oder ohne Messwerte `nil`, nie `0` (F-06, SPEC 5.2).
    private static func distance(_ type: SportType, _ statistics: (HKQuantityType) -> HKStatistics?) -> Double? {
        guard let kind = WorkoutDistanceKind.of(type) else { return nil }
        return statistics(HKQuantityType(identifier(for: kind)))?.sumQuantity()?.doubleValue(for: .meter())
    }
}
