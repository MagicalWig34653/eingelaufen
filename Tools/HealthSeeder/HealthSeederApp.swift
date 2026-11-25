import HealthKit
import SwiftUI

/// **Nur Test-Hilfsziel** für den echten Lauf im Simulator (`scripts/echter-lauf.sh`): legt genau ein
/// Lauftraining mit 5,4 km in Health an. Gehört nie zur App und wird nie archiviert; die App selbst schreibt
/// nichts nach Health.
@main
struct HealthSeederApp: App {
    var body: some Scene { WindowGroup { SeederView() } }
}

struct SeederView: View {
    private let store = HKHealthStore()
    @State private var status = "bereit"

    var body: some View {
        VStack(spacing: 20) {
            Text(status).accessibilityIdentifier("seedStatus")
            Button("Training anlegen") { Task { await seed() } }.accessibilityIdentifier("seed")
        }
        .padding()
    }

    private func seed() async {
        do {
            let distance = HKQuantityType(.distanceWalkingRunning)
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType(), distance], read: [])
            // Training aus früheren Läufen entfernen (nur eigene Einträge dieses Hilfsziels), damit genau eins da ist.
            let own = HKQuery.predicateForObjects(from: .default())
            let removed = try await delete(HKObjectType.workoutType(), own)
            _ = try await delete(distance, own)
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .running
            configuration.locationType = .outdoor
            let end = Date().addingTimeInterval(-3_600)
            let start = end.addingTimeInterval(-1_800)
            let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
            try await builder.beginCollection(at: start)
            let sample = HKQuantitySample(type: distance, quantity: HKQuantity(unit: .meter(), doubleValue: 5_400),
                                          start: start, end: end)
            try await builder.addSamples([sample])
            try await builder.endCollection(at: end)
            guard let workout = try await builder.finishWorkout() else {
                status = "Fehler: kein Training"
                return
            }
            status = "gespeichert \(workout.uuid.uuidString), alte entfernt: \(removed)"
        } catch {
            let e = error as NSError
            status = "Fehler: \(e.domain) \(e.code) \(e.localizedDescription)"
        }
    }

    private func delete(_ type: HKObjectType, _ predicate: NSPredicate) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            store.deleteObjects(of: type, predicate: predicate) { _, count, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: count) }
            }
        }
    }
}
