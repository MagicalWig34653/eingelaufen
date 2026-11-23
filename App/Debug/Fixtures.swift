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
        default:
            break   // „fresh“: frischer Start mit Onboarding
        }
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
