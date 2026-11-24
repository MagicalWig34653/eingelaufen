import Testing
import Foundation
@testable import GearCore

private let bike = id(1)

@Suite("Schnellaktionen und Wartungsereignis (SPEC 8.1, S07)")
struct QuickActionTests {

    @Test("Es gibt genau die sieben Typen der Spec")
    func sevenTypes() {
        #expect(QuickAction.allCases.count == 7)
        let kinds = Set(QuickAction.allCases.flatMap(\.kinds))
        #expect(kinds == Set(MaintenanceKind.allCases))     // jeder Ereignistyp ist über genau eine Aktion erreichbar
    }

    @Test("Teil eingebaut/ausgebaut/ersetzt ist ein Typ mit drei Ausprägungen")
    func partChangeKinds() {
        #expect(QuickAction.partChange.kinds == [.partInstalled, .partRemoved, .partReplaced])
    }

    @Test("Gereinigt, geschmiert, geprüft, repariert speichern sofort ohne Formular; Messen und Frei brauchen eine Eingabe")
    func immediateSave() {
        #expect(QuickAction.allCases.filter(\.savesImmediately).sorted { $0.rawValue < $1.rawValue }
                == [.cleaned, .inspected, .lubricated, .repaired])
    }

    @Test("Sofort speichern: Datum = jetzt, keine erfundenen Messwerte/Kosten")
    func quickSaveUsesNow() throws {
        let e = try MaintenanceEntry.make(kind: .lubricated, gearID: bike, performedAt: nil, now: day(7, hour: 9), id: id(50))
        #expect(e == MaintenanceEvent(id: id(50), gearID: bike, kind: .lubricated, performedAt: day(7, hour: 9)))
        #expect(e.measurement == nil && e.costMinor == nil && e.notes == nil)
    }

    @Test("Optional rückdatieren, Messwert, Kosten und Notiz (getrimmt, leer = nil)")
    func optionalFields() throws {
        let e = try MaintenanceEntry.make(kind: .wearMeasured, gearID: bike, performedAt: day(2), now: day(7),
                                          measurement: 0.5, costMinor: 1_299, notes: "  Lehre 0,5  ")
        #expect(e.performedAt == day(2) && e.measurement == 0.5 && e.costMinor == 1_299 && e.notes == "Lehre 0,5")
        let blank = try MaintenanceEntry.make(kind: .cleaned, gearID: bike, performedAt: nil, now: day(7), notes: "   ")
        #expect(blank.notes == nil)
    }

    @Test("Zukünftiges Datum, negative Kosten und ungültige Messwerte sind abgelehnt")
    func validation() {
        #expect(throws: MaintenanceEntryError.performedInFuture) {
            try MaintenanceEntry.make(kind: .cleaned, gearID: bike, performedAt: day(9), now: day(7))
        }
        #expect(throws: MaintenanceEntryError.negativeCost) {
            try MaintenanceEntry.make(kind: .repaired, gearID: bike, performedAt: nil, now: day(7), costMinor: -1)
        }
        #expect(throws: MaintenanceEntryError.invalidMeasurement) {
            try MaintenanceEntry.make(kind: .wearMeasured, gearID: bike, performedAt: nil, now: day(7), measurement: .nan)
        }
        #expect(throws: MaintenanceEntryError.invalidMeasurement) {
            try MaintenanceEntry.make(kind: .wearMeasured, gearID: bike, performedAt: nil, now: day(7), measurement: -0.1)
        }
    }

    @Test("Verschleiß gemessen braucht einen Wert; frei definierte Wartung braucht eine Bezeichnung")
    func requiredInput() {
        #expect(throws: MaintenanceEntryError.measurementRequired) {
            try MaintenanceEntry.make(kind: .wearMeasured, gearID: bike, performedAt: nil, now: day(7))
        }
        #expect(throws: MaintenanceEntryError.noteRequired) {
            try MaintenanceEntry.make(kind: .custom, gearID: bike, performedAt: nil, now: day(7), notes: " ")
        }
        #expect(throws: Never.self) {
            try MaintenanceEntry.make(kind: .custom, gearID: bike, performedAt: nil, now: day(7), notes: "Kettenblatt gewendet")
        }
    }

    @Test("Kleine Uhrenabweichung (≤ 5 Min.) gilt nicht als Zukunft")
    func clockToleranceIsAccepted() {
        #expect(throws: Never.self) {
            try MaintenanceEntry.make(kind: .cleaned, gearID: bike, performedAt: day(7).addingTimeInterval(240), now: day(7))
        }
    }
}
