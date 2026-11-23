import Foundation
import GearCore

/// Anzeigenamen für Schlüssel des Kerns (String Catalog `Localizable.xcstrings`, de-DE; en-US folgt in M9).
/// Fehlt ein Text, erscheint der Schlüssel selbst. Der Test `DisplayNamesTests` stellt sicher, dass das nie vorkommt.
enum DisplayNames {
    static func string(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func name(for c: SportCategory) -> String { string("category.\(c.rawValue)") }
    static func name(for s: SportSubtype) -> String { string("subtype.\(s.rawValue)") }
    static func name(for s: GearStatus) -> String { string("status.\(s.rawValue)") }
    static func name(for t: GearTemplate) -> String { string(t.nameKey) }
    static func name(for c: ComponentTemplate) -> String { string(c.nameKey) }

    /// SF-Symbol je Kategorie (nur Dekor; Farbe ist nie das einzige Signal, SPEC 1.4).
    static func symbol(for c: SportCategory) -> String {
        switch c {
        case .cycling: "bicycle"
        case .running: "figure.run"
        case .walkingHiking: "figure.hiking"
        case .swimming: "figure.pool.swim"
        case .fitness: "dumbbell"
        case .winterSports: "figure.skiing.downhill"
        case .ballSports: "soccerball"
        case .racketSports: "tennis.racket"
        case .waterPaddle: "oar.2.crossed"
        case .triathlonMultisport: "figure.mixed.cardio"
        case .climbing: "figure.climbing"
        case .other: "square.grid.2x2"
        }
    }

    // MARK: Messwerte (SPEC 5.2, 13: „Keine Daten“ statt 0, „unvollständig“ statt stillem Weniger, Schätzung gekennzeichnet)

    static func distance(_ m: Metric<Double>) -> String {
        switch m {
        case .noData: "Keine Daten"
        case .measured(let meters, let complete): complete ? lengthText(meters) : "\(lengthText(meters)) (unvollständig)"
        case .estimate(let meters, _): "\(lengthText(meters)) (Schätzung)"
        }
    }

    static func duration(_ m: Metric<Double>) -> String {
        switch m {
        case .noData: "Keine Daten"
        case .measured(let s, let complete): complete ? durationText(s) : "\(durationText(s)) (unvollständig)"
        case .estimate(let s, _): "\(durationText(s)) (Schätzung)"
        }
    }

    static func lengthText(_ meters: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        if meters < 1_000 {
            f.maximumFractionDigits = 0
            return "\(f.string(from: meters as NSNumber) ?? "\(Int(meters))") m"
        }
        f.maximumFractionDigits = 1
        return "\(f.string(from: (meters / 1_000) as NSNumber) ?? "") km"
    }

    static func durationText(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
