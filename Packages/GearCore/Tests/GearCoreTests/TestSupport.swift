import Foundation
@testable import GearCore

/// Feste, lesbare Zeitpunkte: Tag n ab 2026-01-01 00:00 UTC, plus Stunden. Keine Systemuhr in Tests.
func day(_ n: Int, hour: Int = 0) -> Date {
    Date(timeIntervalSince1970: 1_767_225_600 + Double(n) * 86_400 + Double(hour) * 3_600)
}

let run = SportType(rawValue: 37)
let cycling = SportType(rawValue: 13)

/// Stabile UUIDs je Buchstabe, damit Fehlermeldungen lesbar bleiben.
func id(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
}

func activity(_ n: Int, start: Date, hours: Double = 1, distance: Double? = 10_000,
              deleted: Date? = nil, sport: SportType = cycling) -> ActivityRecord {
    ActivityRecord(id: id(1_000 + n), sportType: sport, startAt: start,
                   endAt: start.addingTimeInterval(hours * 3_600),
                   distanceMeters: distance, durationSeconds: hours * 3_600, deletedAt: deleted)
}

func assign(_ a: ActivityRecord, _ gear: UUID, segment: ActivitySegment? = nil) -> ActivityGearAssignment {
    ActivityGearAssignment(activityID: a.id, segmentID: segment?.id, gearID: gear)
}

func mount(_ child: UUID, in parent: UUID, from: Date, to: Date? = nil) -> Installation {
    Installation(parentGearID: parent, childGearID: child, startedAt: from, endedAt: to)
}
