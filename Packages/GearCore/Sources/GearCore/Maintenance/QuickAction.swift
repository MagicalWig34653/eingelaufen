import Foundation

// Schnellaktionen und Wartungsereignis (SPEC 8.1, S07).

/// Die sieben Ereignistypen der Spec (8.1). „Teil eingebaut/ausgebaut/ersetzt“ ist ein Typ mit drei Ausprägungen.
public enum QuickAction: String, CaseIterable, Sendable {
    case cleaned, lubricated, inspected, wearMeasured, partChange, repaired, custom
}

public enum MaintenanceEntryError: Error, Equatable, Sendable {
    case notImplemented
    case performedInFuture, negativeCost, invalidMeasurement, measurementRequired, noteRequired
}

public enum MaintenanceEntry {
    public static func make(kind: MaintenanceKind, gearID: UUID, performedAt: Date?, now: Date,
                            measurement: Double? = nil, costMinor: Int? = nil, notes: String? = nil,
                            id: UUID = UUID()) throws -> MaintenanceEvent {
        MaintenanceEvent(id: id, gearID: gearID, kind: kind, performedAt: now)
    }
}

extension QuickAction {
    /// `true`: ein Tipp speichert sofort, ohne Formular (SPEC S07).
    public var savesImmediately: Bool { false }
    public var kinds: [MaintenanceKind] { [] }
}
