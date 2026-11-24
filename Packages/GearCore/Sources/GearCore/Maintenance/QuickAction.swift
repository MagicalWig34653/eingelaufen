import Foundation

// Schnellaktionen und Wartungsereignis (SPEC 8.1, S07): Wartung ohne Formularzwang.

/// Die sieben Ereignistypen der Spec (8.1). „Teil eingebaut/ausgebaut/ersetzt“ ist ein Typ mit drei Ausprägungen.
public enum QuickAction: String, CaseIterable, Sendable {
    case cleaned, lubricated, inspected, wearMeasured, partChange, repaired, custom

    /// Die Ereignistypen hinter der Aktion.
    public var kinds: [MaintenanceKind] {
        switch self {
        case .cleaned: [.cleaned]
        case .lubricated: [.lubricated]
        case .inspected: [.inspected]
        case .wearMeasured: [.wearMeasured]
        case .partChange: [.partInstalled, .partRemoved, .partReplaced]
        case .repaired: [.repaired]
        case .custom: [.custom]
        }
    }

    /// `true`: ein Tipp speichert sofort, ohne Formular (SPEC S07). Messen braucht einen Wert, Frei eine Bezeichnung,
    /// Teilewechsel läuft über den Komponentenablauf.
    public var savesImmediately: Bool {
        switch self {
        case .cleaned, .lubricated, .inspected, .repaired: true
        case .wearMeasured, .partChange, .custom: false
        }
    }
}

public enum MaintenanceEntryError: Error, Equatable, Sendable {
    case performedInFuture, negativeCost, invalidMeasurement, measurementRequired, noteRequired
}

public enum MaintenanceEntry {
    /// Toleranz für Uhrenabweichung; „später heute“ ist keine Wartung, die schon stattgefunden hat.
    private static let clockTolerance: TimeInterval = 300

    /// Prüft die Eingaben und erzeugt das Ereignis. Datum = `now`, wenn nicht angegeben. Fehlende Werte bleiben `nil`.
    public static func make(kind: MaintenanceKind, gearID: UUID, performedAt: Date?, now: Date,
                            measurement: Double? = nil, costMinor: Int? = nil, notes: String? = nil,
                            id: UUID = UUID()) throws -> MaintenanceEvent {
        let date = performedAt ?? now
        guard date <= now.addingTimeInterval(clockTolerance) else { throw MaintenanceEntryError.performedInFuture }
        if let costMinor, costMinor < 0 { throw MaintenanceEntryError.negativeCost }
        if let measurement, !(measurement.isFinite && measurement >= 0) { throw MaintenanceEntryError.invalidMeasurement }
        let note = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = (note?.isEmpty ?? true) ? nil : note
        if kind == .wearMeasured, measurement == nil { throw MaintenanceEntryError.measurementRequired }
        if kind == .custom, cleanNote == nil { throw MaintenanceEntryError.noteRequired }
        return MaintenanceEvent(id: id, gearID: gearID, kind: kind, performedAt: date,
                                measurement: measurement, costMinor: costMinor, notes: cleanNote)
    }
}
