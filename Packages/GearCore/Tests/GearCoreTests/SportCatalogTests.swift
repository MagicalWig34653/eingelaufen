import Testing
import Foundation
@testable import GearCore

/// Alle `HKWorkoutActivityType`-Rohwerte laut iOS-SDK 27.2 (HealthKit/HKWorkoutActivityType.h, geprüft 23.11.2026),
/// ohne `Rest`/`Group` (auf iOS nicht verfügbar). Das Mapping muss genau diese Menge kennen.
private let sdkRawValues: Set<Int> = Set(1...84).subtracting([81]).union([3000])

@Suite("SportCatalog (SPEC 3.2, 3.3)")
struct SportCatalogTests {

    @Test("Alle 12 Kategorien der Spec 3.2 sind vorhanden")
    func twelveCategories() {
        #expect(SportCategory.allCases.count == 12)
        #expect(Set(SportCategory.allCases.map(\.rawValue)).count == 12)
    }

    @Test("Jede Kategorie hat mindestens eine Kurzvorlage, passende Metriken und einen Standard-Sporttyp")
    func everyCategoryHasTemplateAndMetrics() {
        for category in SportCategory.allCases {
            #expect(!GearTemplateCatalog.templates(for: category).isEmpty, "Vorlage fehlt: \(category)")
            #expect(!category.typicalMetrics.isEmpty, "Metriken fehlen: \(category)")
            #expect(SportCatalog.category(for: category.defaultSportType) == category,
                    "Standard-Sporttyp von \(category) muss zurück auf die Kategorie zeigen")
        }
    }

    @Test("Metriken folgen der Tabelle in Spec 3.2")
    func metricsFollowSpecTable() {
        #expect(SportCategory.cycling.typicalMetrics == [.distance, .duration, .uses])
        #expect(SportCategory.fitness.typicalMetrics == [.duration, .uses])
        #expect(SportCategory.ballSports.typicalMetrics == [.duration, .uses])
        #expect(SportCategory.racketSports.typicalMetrics == [.duration, .uses])
        #expect(SportCategory.winterSports.typicalMetrics.contains(.calendarAge))
        #expect(SportCategory.climbing.typicalMetrics.contains(.calendarAge))
        #expect(!SportCategory.climbing.typicalMetrics.contains(.distance))
    }

    @Test("Unterkategorien gehören jeweils zu genau einer Kategorie")
    func subtypesBelongToOneCategory() {
        for subtype in SportSubtype.allCases {
            #expect(subtype.category.subtypes.contains(subtype))
        }
        #expect(SportCategory.cycling.subtypes.contains(.roadBike))
        #expect(SportCategory.cycling.subtypes.contains(.indoorCycling))
        #expect(SportCategory.running.subtypes == [.roadRunning, .trailRunning, .treadmill])
        #expect(SportCategory.swimming.subtypes == [.pool, .openWater])
        #expect(SportCategory.other.subtypes.isEmpty)
    }

    // MARK: HealthKit-Mapping

    @Test("Das Mapping kennt genau die SDK-Rohwerte, keinen mehr und keinen weniger")
    func mappingCoversExactlySDKList() {
        #expect(Set(HealthWorkoutMapping.table.keys) == sdkRawValues)
    }

    @Test("Bekannte Rohwerte landen in der erwarteten Kategorie")
    func knownValuesMapped() {
        let expected: [(Int, SportCategory)] = [
            (13, .cycling), (74, .cycling), (37, .running), (49, .running),
            (52, .walkingHiking), (24, .walkingHiking), (46, .swimming),
            (20, .fitness), (50, .fitness), (57, .fitness), (63, .fitness),
            (40, .winterSports), (60, .winterSports), (61, .winterSports), (67, .winterSports),
            (41, .ballSports), (6, .ballSports), (51, .ballSports),
            (48, .racketSports), (4, .racketSports), (43, .racketSports), (79, .racketSports),
            (35, .waterPaddle), (31, .waterPaddle), (45, .waterPaddle),
            (82, .triathlonMultisport), (83, .triathlonMultisport),
            (9, .climbing), (3000, .other),
        ]
        for (raw, category) in expected {
            #expect(SportCatalog.category(for: SportType(rawValue: raw)) == category, "rawValue \(raw)")
        }
    }

    @Test("Unbekannte oder künftige Rohwerte landen in Sonstige statt verworfen zu werden (SPEC 3.1)")
    func unknownGoesToOther() {
        for raw in [85, 999, 2998, 2999, 99_999, -1, 0] {
            let c = SportCatalog.classify(SportType(rawValue: raw))
            #expect(c.category == .other, "rawValue \(raw)")
            #expect(c.subtype == nil)
        }
    }

    @Test("Jede Kategorie außer Sonstige wird von mindestens einem Rohwert erreicht")
    func everyCategoryReachable() {
        let reached = Set(HealthWorkoutMapping.table.values.map(\.category))
        for category in SportCategory.allCases where category != .other {
            #expect(reached.contains(category), "\(category) ohne Rohwert")
        }
    }

    @Test("Indoor/Outdoor wird nie aus dem Sporttyp allein behauptet (SPEC 3.3)")
    func noIndoorOutdoorFromTypeAlone() {
        // Radfahren, Laufen und Schwimmen sind ohne Metadaten mehrdeutig: keine Unterkategorie.
        for raw in [13, 37, 46] {
            #expect(SportCatalog.classify(SportType(rawValue: raw)).subtype == nil, "rawValue \(raw)")
        }
        // Eindeutige Typen dürfen eine Unterkategorie tragen.
        #expect(SportCatalog.classify(SportType(rawValue: 60)).subtype == .crossCountrySkiing)
        #expect(SportCatalog.classify(SportType(rawValue: 67)).subtype == .snowboard)
    }

    @Test("Jede Unterkategorie im Mapping gehört zur gemappten Kategorie")
    func mappedSubtypeMatchesCategory() {
        for (_, c) in HealthWorkoutMapping.table {
            if let subtype = c.subtype { #expect(subtype.category == c.category) }
        }
    }

    // MARK: Vorlagen

    @Test("Vorlagen-IDs sind eindeutig, jede Vorlage gehört zu ihrer Kategorie")
    func templateIDsUniqueAndConsistent() {
        let all = GearTemplateCatalog.all
        #expect(Set(all.map(\.id)).count == all.count)
        for template in all {
            #expect(GearTemplateCatalog.templates(for: template.category).contains(where: { $0.id == template.id }))
            if let subtype = template.subtype { #expect(subtype.category == template.category) }
            #expect(!template.nameKey.isEmpty)
        }
    }

    @Test("Fahrradvorlagen enthalten Kette, Kassette, Laufradsatz, Reifen und Bremsbeläge (SPEC S04)")
    func bikeComponentTemplates() throws {
        let road = try #require(GearTemplateCatalog.template(id: "cycling.road-bike"))
        let ids = Set(road.components.map(\.id))
        #expect(ids.isSuperset(of: ["chain", "cassette", "wheelset", "tires", "brake-pads"]))
    }

    @Test("Intervalle sind Startwerte oder leer, nie Tatsache oder Prozent-Verschleiß (SPEC 8.2, P-07)")
    func intervalsAreStartValues() {
        for template in GearTemplateCatalog.all {
            for component in template.components {
                guard let interval = component.startInterval else { continue }
                #expect(interval.isStartValue, "\(template.id)/\(component.id)")
                #expect(interval.lower > 0 && interval.lower <= interval.upper)
                #expect(interval.purpose == .check, "Hinweis lautet „Prüfen“, nie „Ersetzen“")
            }
        }
    }

    @Test("Sicherheitskritische Teile haben keinen numerischen Startwert, sondern verlangen Prüfung (SPEC 8.2)")
    func safetyCriticalPartsHaveNoNumericInterval() throws {
        let road = try #require(GearTemplateCatalog.template(id: "cycling.road-bike"))
        for id in ["brake-pads", "tires"] {
            let part = try #require(road.components.first { $0.id == id })
            #expect(part.isSafetyCritical)
            #expect(part.startInterval == nil)
        }
        for template in GearTemplateCatalog.all {
            for part in template.components where part.isSafetyCritical {
                #expect(part.startInterval == nil, "\(template.id)/\(part.id)")
            }
        }
    }

    @Test("Eine Vorlage anwenden braucht nur einen Namen und keine Komponenten (SPEC 13)")
    func templateNeedsNoComponents() throws {
        let shoes = try #require(GearTemplateCatalog.templates(for: .running).first)
        let gear = shoes.makeGearItem(name: "Mein Paar", id: id(1), now: day(0))
        #expect(gear.name == "Mein Paar")
        #expect(gear.status == .active)
        #expect(gear.createdAt == day(0))
    }

    @Test("Manuelle Aktivitäten: Standard-Sporttyp je Kategorie bleibt stabil")
    func defaultSportTypesStable() {
        #expect(SportCategory.cycling.defaultSportType.rawValue == 13)
        #expect(SportCategory.running.defaultSportType.rawValue == 37)
        #expect(SportCategory.other.defaultSportType.rawValue == 3000)
    }
}
