import Foundation

// Ausrüstungsvorlagen (SPEC 3.2 „Standard-Ausrüstung“, S03/S04, 8.2).
// Eine Vorlage anwenden heißt: Name bestätigen, speichern. Komponenten sind optional und nie Pflicht (SPEC 13).

/// Wofür ein Intervall gedacht ist. Immer „Prüfen“, nie „Ersetzen“ (SPEC 7.4, 8.2).
public enum IntervalPurpose: String, Codable, Sendable {
    case check
}

/// Vorgeschlagenes Wartungsintervall aus einer Vorlage. **Startwert**, editierbar, konservativ, keine Tatsache
/// und kein Verschleiß in Prozent (SPEC 1.1, 8.2, Annahme P-07). Einheiten: Meter, Sekunden, Anzahl, Tage (A-08).
public struct StartInterval: Hashable, Codable, Sendable {
    public var metric: UsageMetricKind
    public var lower: Double
    public var upper: Double
    public var purpose: IntervalPurpose
    /// Immer `true`: die UI kennzeichnet Vorlagenwerte als „Startwert“.
    public var isStartValue: Bool { true }

    public init(metric: UsageMetricKind, lower: Double, upper: Double, purpose: IntervalPurpose = .check) {
        self.metric = metric
        self.lower = lower
        self.upper = upper
        self.purpose = purpose
    }

    public static func kilometers(_ lower: Double, _ upper: Double) -> StartInterval {
        StartInterval(metric: .distance, lower: lower * 1_000, upper: upper * 1_000)
    }
}

/// Teilvorlage, z. B. Kette am Fahrrad.
public struct ComponentTemplate: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var nameKey: String
    /// Sicherheitskritisch (Bremsen, Reifen, Helm …): nur „Prüfen“, nie ein Freigabesignal und kein Zahlenwert (SPEC 8.2).
    public var isSafetyCritical: Bool
    /// `nil` = kein Vorschlag, der Nutzer legt selbst fest.
    public var startInterval: StartInterval?

    public init(id: String, nameKey: String, isSafetyCritical: Bool = false, startInterval: StartInterval? = nil) {
        precondition(!(isSafetyCritical && startInterval != nil), "Sicherheitskritische Teile erhalten keinen Zahlenwert")
        self.id = id
        self.nameKey = nameKey
        self.isSafetyCritical = isSafetyCritical
        self.startInterval = startInterval
    }
}

public struct GearTemplate: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var category: SportCategory
    public var subtype: SportSubtype?
    public var nameKey: String
    /// SF-Symbol-Name für die Karte.
    public var symbol: String
    public var components: [ComponentTemplate]

    public init(id: String, category: SportCategory, subtype: SportSubtype? = nil, nameKey: String,
                symbol: String, components: [ComponentTemplate] = []) {
        self.id = id
        self.category = category
        self.subtype = subtype
        self.nameKey = nameKey
        self.symbol = symbol
        self.components = components
    }

    /// Legt den Gegenstand aus der Vorlage an: nur der Name ist nötig (SPEC S03). Komponenten folgen bei Bedarf.
    public func makeGearItem(name: String, id: UUID = UUID(), now: Date) -> GearItem {
        GearItem(id: id, name: name, status: .active, createdAt: now, category: category, subtype: subtype)
    }
}

public enum GearTemplateCatalog {
    private static let bikeComponents: [ComponentTemplate] = [
        // Zahlenwerte nur, wo die Spec selbst ein Beispiel nennt (Kette 2.500–3.500 km, 1.1); sonst legt der Nutzer fest.
        ComponentTemplate(id: "chain", nameKey: "component.chain", startInterval: .kilometers(2_500, 3_500)),
        ComponentTemplate(id: "cassette", nameKey: "component.cassette"),
        ComponentTemplate(id: "wheelset", nameKey: "component.wheelset"),
        ComponentTemplate(id: "tires", nameKey: "component.tires", isSafetyCritical: true),
        ComponentTemplate(id: "brake-pads", nameKey: "component.brake-pads", isSafetyCritical: true),
    ]

    private static func simple(_ category: SportCategory, _ slug: String, symbol: String,
                               subtype: SportSubtype? = nil) -> GearTemplate {
        GearTemplate(id: "\(category.rawValue).\(slug)", category: category, subtype: subtype,
                     nameKey: "template.\(category.rawValue).\(slug)", symbol: symbol)
    }

    private static func bike(_ slug: String, _ subtype: SportSubtype) -> GearTemplate {
        GearTemplate(id: "cycling.\(slug)", category: .cycling, subtype: subtype,
                     nameKey: "template.cycling.\(slug)", symbol: "bicycle", components: bikeComponents)
    }

    /// Kurzvorlagen je Kategorie aus der Spalte „Standard-Ausrüstung“ der Spec-Tabelle 3.2.
    public static let all: [GearTemplate] = [
        // Radsport: Fahrrad, Schuhe, Helm, Kleidung, Teile
        bike("road-bike", .roadBike), bike("gravel-bike", .gravel), bike("mountain-bike", .mountainBike),
        bike("city-bike", .cityBike), bike("indoor-bike", .indoorCycling),
        simple(.cycling, "shoes", symbol: "shoe"), simple(.cycling, "helmet", symbol: "figure.outdoor.cycle"),
        simple(.cycling, "clothing", symbol: "tshirt"), simple(.cycling, "part", symbol: "gearshape"),
        // Laufen: Laufschuhe, Bekleidung, Zubehör
        simple(.running, "shoes", symbol: "shoe", subtype: .roadRunning),
        simple(.running, "trail-shoes", symbol: "shoe", subtype: .trailRunning),
        simple(.running, "clothing", symbol: "tshirt"), simple(.running, "accessory", symbol: "watch.analog"),
        // Gehen & Wandern: Wanderschuhe, Stöcke, Rucksack
        simple(.walkingHiking, "boots", symbol: "shoe", subtype: .hiking),
        simple(.walkingHiking, "poles", symbol: "figure.hiking"), simple(.walkingHiking, "backpack", symbol: "backpack"),
        // Schwimmen: Brille, Badebekleidung, Flossen
        simple(.swimming, "goggles", symbol: "eyeglasses"), simple(.swimming, "swimwear", symbol: "figure.pool.swim"),
        simple(.swimming, "fins", symbol: "water.waves"),
        // Fitness & Kraft: Schuhe, Matte, Gürtel, Zubehör
        simple(.fitness, "shoes", symbol: "shoe"), simple(.fitness, "mat", symbol: "figure.yoga", subtype: .yoga),
        simple(.fitness, "belt", symbol: "dumbbell"), simple(.fitness, "accessory", symbol: "dumbbell.fill"),
        // Wintersport: Ski, Board, Boots, Helm
        simple(.winterSports, "ski", symbol: "figure.skiing.downhill", subtype: .ski),
        simple(.winterSports, "board", symbol: "figure.snowboarding", subtype: .snowboard),
        simple(.winterSports, "boots", symbol: "shoe"), simple(.winterSports, "helmet", symbol: "figure.skiing.downhill"),
        // Ballsport: Schuhe, Ball, Schützer
        simple(.ballSports, "shoes", symbol: "shoe"), simple(.ballSports, "ball", symbol: "soccerball"),
        simple(.ballSports, "protection", symbol: "shield"),
        // Schlägersport: Schläger, Schuhe, Bespannung
        simple(.racketSports, "racket", symbol: "tennis.racket"), simple(.racketSports, "shoes", symbol: "shoe"),
        simple(.racketSports, "strings", symbol: "tennis.racket"),
        // Wasser- & Paddelsport: Board, Paddel, Kleidung
        simple(.waterPaddle, "board", symbol: "figure.surfing", subtype: .standUpPaddling),
        simple(.waterPaddle, "paddle", symbol: "oar.2.crossed"), simple(.waterPaddle, "clothing", symbol: "tshirt"),
        // Triathlon/Multisport: Kombination passender Ausrüstung (kein eigener Gegenstand nötig, Presets decken es ab)
        simple(.triathlonMultisport, "wetsuit", symbol: "figure.open.water.swim"),
        simple(.triathlonMultisport, "gear", symbol: "figure.mixed.cardio"),
        // Klettern & Bergsport: Kletterschuhe, Chalkbag, Equipment
        simple(.climbing, "shoes", symbol: "shoe"), simple(.climbing, "chalk-bag", symbol: "bag"),
        simple(.climbing, "equipment", symbol: "figure.climbing"),
        // Sonstige: frei definierbar
        simple(.other, "custom", symbol: "square.grid.2x2"),
    ]

    public static func templates(for category: SportCategory) -> [GearTemplate] {
        all.filter { $0.category == category }
    }

    public static func template(id: String) -> GearTemplate? { all.first { $0.id == id } }
}
