import Foundation

// Sportkatalog (SPEC 3.2, 3.3): Kategorien, Unterkategorien, typische Metriken, Standard-Sporttyp.
// Rein und ohne HealthKit-Import: Rohwerte sind Zahlen (`HKWorkoutActivityType.rawValue`), damit der Kern
// ohne Framework testbar bleibt. Anzeigenamen kommen als Schlüssel (`nameKey`) und werden in der App lokalisiert.

/// Nutzungsmetriken (SPEC 5.3). Welche für einen Gegenstand aktiv sind, wählt die App je Kategorie vor.
public enum UsageMetricKind: String, Codable, Sendable, CaseIterable {
    case distance, duration, uses, calendarAge
}

/// Die 12 Kategorien ab V1 (SPEC 3.2).
public enum SportCategory: String, Codable, Sendable, CaseIterable {
    case cycling, running, walkingHiking, swimming, fitness, winterSports
    case ballSports, racketSports, waterPaddle, triathlonMultisport, climbing, other

    /// „Typische Metriken“ aus der Tabelle in SPEC 3.2. Bei „Sonstige“ ist alles konfigurierbar,
    /// bei Triathlon hängt es vom Segment ab (alle drei Messgrößen möglich).
    public var typicalMetrics: [UsageMetricKind] {
        switch self {
        case .cycling, .running, .walkingHiking, .swimming, .waterPaddle, .triathlonMultisport:
            [.distance, .duration, .uses]
        case .fitness, .ballSports, .racketSports:
            [.duration, .uses]
        case .winterSports:
            [.distance, .duration, .uses, .calendarAge]
        case .climbing:
            [.duration, .uses, .calendarAge]
        case .other:
            [.distance, .duration, .uses, .calendarAge]
        }
    }

    /// Unterkategorien laut SPEC 3.2 (Beispiele/Untertypen).
    public var subtypes: [SportSubtype] { SportSubtype.allCases.filter { $0.category == self } }

    /// Repräsentativer Sporttyp für manuell angelegte Aktivitäten (SPEC 6.4). Rohwert wie bei HealthKit, damit
    /// manuelle und importierte Aktivitäten dieselbe Zuordnungs- und Wartungslogik durchlaufen.
    public var defaultSportType: SportType {
        let raw: Int = switch self {
        case .cycling: 13
        case .running: 37
        case .walkingHiking: 52
        case .swimming: 46
        case .fitness: 20
        case .winterSports: 40
        case .ballSports: 41
        case .racketSports: 48
        case .waterPaddle: 31
        case .triathlonMultisport: 82
        case .climbing: 9
        case .other: 3000
        }
        return SportType(rawValue: raw)
    }
}

public enum SportSubtype: String, Codable, Sendable, CaseIterable {
    // Radsport
    case roadBike, gravel, mountainBike, cityBike, indoorCycling
    // Laufen
    case roadRunning, trailRunning, treadmill
    // Gehen & Wandern
    case walk, hiking, trekking
    // Schwimmen
    case pool, openWater
    // Fitness & Kraft
    case gym, strength, functional, yoga
    // Wintersport
    case ski, crossCountrySkiing, snowboard
    // Ballsport
    case football, basketball, handball, volleyball
    // Schlägersport
    case tennis, badminton, squash, padel
    // Wasser & Paddeln
    case rowing, kayak, standUpPaddling, surfing
    // Klettern & Bergsport
    case indoorClimbing, outdoorClimbing

    public var category: SportCategory {
        switch self {
        case .roadBike, .gravel, .mountainBike, .cityBike, .indoorCycling: .cycling
        case .roadRunning, .trailRunning, .treadmill: .running
        case .walk, .hiking, .trekking: .walkingHiking
        case .pool, .openWater: .swimming
        case .gym, .strength, .functional, .yoga: .fitness
        case .ski, .crossCountrySkiing, .snowboard: .winterSports
        case .football, .basketball, .handball, .volleyball: .ballSports
        case .tennis, .badminton, .squash, .padel: .racketSports
        case .rowing, .kayak, .standUpPaddling, .surfing: .waterPaddle
        case .indoorClimbing, .outdoorClimbing: .climbing
        }
    }
}

/// Ergebnis der Einordnung eines Sporttyps. `subtype` nur, wenn der Typ selbst eindeutig ist (SPEC 3.3).
public struct SportClassification: Hashable, Sendable {
    public var category: SportCategory
    public var subtype: SportSubtype?
    public init(_ category: SportCategory, _ subtype: SportSubtype? = nil) {
        self.category = category
        self.subtype = subtype
    }
}

public enum SportCatalog {
    public static func classify(_ sport: SportType) -> SportClassification {
        HealthWorkoutMapping.table[sport.rawValue] ?? SportClassification(.other)
    }

    public static func category(for sport: SportType) -> SportCategory { classify(sport).category }
}
