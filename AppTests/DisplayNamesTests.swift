import Foundation
import GearCore
import SwiftUI
import Testing
@testable import Eingelaufen

/// Jeder Anzeigeschlüssel des Kerns hat einen deutschen Text (SPEC 1.4; en-US folgt in M9).
@Suite struct DisplayNamesTests {
    @Test func everyCategoryHasAGermanName() {
        for c in SportCategory.allCases {
            let name = DisplayNames.name(for: c)
            #expect(!name.isEmpty && name != "category.\(c.rawValue)", "Kategorie \(c) ohne Text")
        }
        #expect(DisplayNames.name(for: SportCategory.cycling) == "Radsport")
        #expect(DisplayNames.name(for: SportCategory.other) == "Sonstige")
    }

    @Test func everySubtypeHasAGermanName() {
        for s in SportSubtype.allCases {
            let name = DisplayNames.name(for: s)
            #expect(!name.isEmpty && name != "subtype.\(s.rawValue)", "Unterkategorie \(s) ohne Text")
        }
    }

    @Test func everyTemplateAndComponentHasAGermanName() {
        for t in GearTemplateCatalog.all {
            let name = DisplayNames.name(for: t)
            #expect(name != t.nameKey, "Vorlage \(t.id) ohne Text")
            for c in t.components {
                #expect(DisplayNames.name(for: c) != c.nameKey, "Komponente \(c.id) ohne Text")
            }
        }
    }

    @Test func everyStatusHasAGermanName() {
        for s in GearStatus.allCases { #expect(DisplayNames.name(for: s) != "status.\(s.rawValue)") }
        #expect(DisplayNames.name(for: GearStatus.archived) == "Archiviert")
    }

    @Test func unknownDataIsShownAsNoDataNeverZero() {
        #expect(DisplayNames.distance(.noData) == "Keine Daten")
        #expect(DisplayNames.distance(.measured(0, isComplete: true)).hasPrefix("0"))
        #expect(DisplayNames.distance(.measured(12_340, isComplete: true)).contains("12"))
        #expect(DisplayNames.distance(.measured(12_340, isComplete: false)).contains("unvollständig"))
        #expect(DisplayNames.distance(.estimate(5_000, basis: .firstUsage)).contains("Schätzung"))
    }

    // M5-Befund „Warnfarbe bei überfälliger Wartung“: Farbe nur zusätzlich zu Symbol und Text (SPEC 1.4).
    @Test func overdueMaintenanceIsMarkedByColorSymbolAndText() {
        let due = DisplayNames.statusStyle(for: .due), soon = DisplayNames.statusStyle(for: .dueSoon)
        #expect(due.color == .red && soon.color == .orange)
        #expect(DisplayNames.statusStyle(for: .unknown).color == .secondary)
        #expect(DisplayNames.statusStyle(for: .belowInterval).color == .secondary)
        let symbols = RuleStateSet.all.map { DisplayNames.statusStyle(for: $0).symbol }
        #expect(Set(symbols).count == symbols.count, "Jeder Zustand hat ein eigenes Symbol")
        #expect(RuleStateSet.all.allSatisfy { !DisplayNames.name(for: $0).isEmpty })
    }

    // M5-Befund „verschachtelte Komponenten“: der Weg bis zur obersten Ausrüstung steht im Detail.
    @Test func installedInShowsTheWholePath() {
        #expect(DisplayNames.installedIn(path: ["Canyon Endurace"]) == "Canyon Endurace")
        #expect(DisplayNames.installedIn(path: ["Canyon Endurace", "Laufrad"]) == "Canyon Endurace › Laufrad")
        #expect(DisplayNames.installedIn(path: []) == "")
    }

    // M5-Befund „Einheit der Messgrenze“: die Einheit legt der Nutzer fest, die Texte sagen es.
    @Test func measurementLimitTextNamesTheUnitRule() {
        let text = DisplayNames.limitText(0.5)
        #expect(text.contains("0,5") || text.contains("0.5"))
        #expect(text.contains("Einheit wie beim Messwert"))
    }
}

/// Alle Zustände einer Regel, damit neue Fälle in den Tests auffallen.
private enum RuleStateSet { static let all: [RuleState] = [.unknown, .belowInterval, .dueSoon, .due] }
