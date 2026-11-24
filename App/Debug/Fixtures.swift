#if DEBUG
import Foundation
import GearCore

/// Feste Daten für UI-Tests (`-UITestFixture <name>`), nur in Debug-Builds. Alle Zeitpunkte liegen absolut in der Vergangenheit.
enum Fixtures {
    /// 1. November 2026, 00:00 UTC.
    static let base = Date(timeIntervalSince1970: 1_793_491_200)
    static func at(day: Double, hour: Double = 9) -> Date { base.addingTimeInterval(day * 86_400 + hour * 3_600) }

    static func apply(_ name: String, to persistence: PersistenceActor) async {
        switch name {
        case "empty":
            _ = try? await persistence.apply(.completeOnboarding(OnboardingChoice(categories: [], health: .later)), now: at(day: 0))
        case "basic":
            try? await persistence.load(basic)
            _ = try? await persistence.apply(.completeOnboarding(OnboardingChoice(categories: [.cycling, .running], health: .later)), now: at(day: 0))
        case "maintenance":
            try? await persistence.load(maintenance)
            _ = try? await persistence.apply(.completeOnboarding(OnboardingChoice(categories: [.cycling], health: .later)), now: at(day: 0))
        default:
            break   // „fresh“: frischer Start mit Onboarding
        }
    }

    /// Rennrad mit montierter Kette (seit Tag 0), vier Fahrten, Schmierung an Tag 3, Messung an Tag 9, zwei Regeln an der Kette:
    /// Schmieren alle 100 km (Vorwarnung 20 km) und Messgrenze 0,5. Seit der Schmierung: 35 + 40 + 30 = 105 km → fällig.
    static var maintenance: GearDataset {
        let bike = GearItem(name: "Canyon Endurace", createdAt: at(day: 0), category: .cycling, subtype: .roadBike)
        let chain = GearItem(name: "Kette", createdAt: at(day: 0), category: .cycling)
        var d = GearDataset()
        d.gear = [bike, chain]
        d.statusChanges = d.gear.map { GearStatusChange(gearID: $0.id, status: .active, effectiveAt: at(day: 0)) }
        d.installations = [Installation(parentGearID: bike.id, childGearID: chain.id, startedAt: at(day: 0))]
        for (day, km) in [(2.0, 42.3), (4, 35), (6, 40), (9, 30)] {
            let a = ActivityRecord(source: .manual, sportType: SportCategory.cycling.defaultSportType, startAt: at(day: day),
                                   endAt: at(day: day).addingTimeInterval(5_400), distanceMeters: km * 1_000, durationSeconds: 5_400)
            d.activities.append(a)
            d.assignments.append(ActivityGearAssignment(activityID: a.id, gearID: bike.id, origin: .manual, createdAt: at(day: day)))
        }
        d.maintenanceEvents = [
            MaintenanceEvent(gearID: chain.id, kind: .lubricated, performedAt: at(day: 3)),
            MaintenanceEvent(gearID: chain.id, kind: .wearMeasured, performedAt: at(day: 9), measurement: 0.3),
        ]
        d.maintenanceRules = [
            MaintenanceRule(gearID: chain.id, kind: .lubricated, metric: .distance, intervalValue: 100_000, warningLeadValue: 20_000),
            MaintenanceRule(gearID: chain.id, kind: .wearMeasured, metric: .distance, intervalValue: 0.5),
        ]
        return d
    }

    static var basic: GearDataset {
        let bike = GearItem(name: "Canyon Endurace", status: .active, createdAt: at(day: 0), category: .cycling, subtype: .roadBike)
        let shoes = GearItem(name: "Radschuhe", createdAt: at(day: 0), category: .cycling)
        let run = GearItem(name: "Laufschuhe Pegasus", createdAt: at(day: 0), category: .running, subtype: .roadRunning)
        let racket = GearItem(name: "Tennisschläger", createdAt: at(day: 0), category: .racketSports, subtype: .tennis)
        let old = GearItem(name: "Alte Laufschuhe", status: .archived, createdAt: at(day: 0), category: .running)
        var d = GearDataset()
        d.gear = [bike, shoes, run, racket, old]
        d.statusChanges = d.gear.map { GearStatusChange(gearID: $0.id, status: .active, effectiveAt: at(day: 0)) }
            + [GearStatusChange(gearID: old.id, status: .archived, effectiveAt: at(day: 5))]
        func activity(_ category: SportCategory, day: Double, minutes: Double, km: Double?, gear: [GearItem]) {
            let a = ActivityRecord(source: .manual, sportType: category.defaultSportType, startAt: at(day: day),
                                   endAt: at(day: day).addingTimeInterval(minutes * 60),
                                   distanceMeters: km.map { $0 * 1_000 }, durationSeconds: minutes * 60)
            d.activities.append(a)
            d.assignments += gear.map { ActivityGearAssignment(activityID: a.id, gearID: $0.id, origin: .manual, createdAt: at(day: day)) }
        }
        activity(.cycling, day: 2, minutes: 95, km: 42.3, gear: [bike, shoes])
        activity(.running, day: 4, minutes: 40, km: 7.5, gear: [run])
        activity(.cycling, day: 8, minutes: 60, km: nil, gear: [bike])
        activity(.racketSports, day: 10, minutes: 75, km: nil, gear: [racket])
        return d
    }
}
#endif
