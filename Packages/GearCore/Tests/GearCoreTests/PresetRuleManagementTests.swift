import Testing
import Foundation
@testable import GearCore

// M4: Presets (SPEC 4.1) und Zuordnungsregeln (SPEC 6.3) verwalten. Rein; der PersistenceActor schreibt das Ergebnis.

private let bikeA = id(3), bikeB = id(4), helmet = id(6), cycShoes = id(7), shoesA = id(1)
private let now = day(30)

private func item(_ n: UUID, _ category: SportCategory, created: Int = 0, status: GearStatus = .active) -> GearItem {
    GearItem(id: n, name: "G\(n.uuidString.suffix(2))", status: status, createdAt: day(created), category: category)
}

private func base() -> GearDataset {
    var d = GearDataset()
    d.gear = [item(bikeA, .cycling), item(bikeB, .cycling, created: 1), item(helmet, .cycling, created: 2),
              item(cycShoes, .cycling, created: 3), item(shoesA, .running)]
    d.sportProfiles = [SportProfile(id: id(900), sportType: cycling)]
    return d
}

@Suite("PresetPlanner (SPEC 4.1)")
struct PresetPlannerTests {

    @Test("Anlegen: Name getrimmt, Mitglieder ohne Dopplung in gegebener Reihenfolge")
    func createTrims() throws {
        let p = try PresetPlanner.create(name: "  Rennrad komplett ", sportTypes: [cycling], members: [bikeA, helmet, bikeA],
                                         in: base(), id: id(700))
        #expect(p.name == "Rennrad komplett" && p.memberGearIDs == [bikeA, helmet] && p.isEnabled && p.id == id(700))
    }

    @Test("Anlegen: leerer Name, keine Mitglieder, keine Sportart, unbekannter Gegenstand werden abgewiesen")
    func createValidates() {
        let d = base()
        #expect(throws: PresetError.emptyName) { try PresetPlanner.create(name: "  ", sportTypes: [cycling], members: [bikeA], in: d) }
        #expect(throws: PresetError.noMembers) { try PresetPlanner.create(name: "X", sportTypes: [cycling], members: [], in: d) }
        #expect(throws: PresetError.noSportTypes) { try PresetPlanner.create(name: "X", sportTypes: [], members: [bikeA], in: d) }
        #expect(throws: PresetError.unknownGear(id(77))) { try PresetPlanner.create(name: "X", sportTypes: [cycling], members: [id(77)], in: d) }
    }

    @Test("Angebot für eine Aktivität: aktive Presets der Sportart, nur verfügbare Mitglieder, Standard zuerst")
    func offeredForActivity() throws {
        var d = base()
        d.gear[3].status = .retired     // Radschuhe ausgemustert
        d.statusChanges = [GearStatusChange(gearID: cycShoes, status: .retired, effectiveAt: day(2))]
        let road = GearPreset(id: id(701), name: "Rennrad", sportTypes: [cycling], memberGearIDs: [bikeA, helmet, cycShoes])
        let commute = GearPreset(id: id(702), name: "Pendeln", sportTypes: [cycling], memberGearIDs: [bikeB])
        let running = GearPreset(id: id(703), name: "Laufen", sportTypes: [run], memberGearIDs: [shoesA])
        let off = GearPreset(id: id(704), name: "Aus", sportTypes: [cycling], memberGearIDs: [bikeA], isEnabled: false)
        d.presets = [road, commute, running, off]
        d.sportProfiles[0].defaultPresetID = id(702)

        let offers = PresetPlanner.offered(for: activity(1, start: day(5)), in: d)
        #expect(offers.map(\.preset.id) == [id(702), id(701)], "Standard zuerst; Laufen und deaktiviertes fehlen")
        try #require(offers.count == 2)
        #expect(offers[1].availableGearIDs == [bikeA, helmet])
        #expect(offers[1].unavailableGearIDs == [cycShoes])
        #expect(offers[0].isDefault && !offers[1].isDefault)
    }

    @Test("Standard-Preset setzen: legt das Profil an, wenn es fehlt, und lehnt fremde Sportarten ab")
    func setDefault() throws {
        var d = base()
        d.presets = [GearPreset(id: id(701), name: "Rennrad", sportTypes: [cycling], memberGearIDs: [bikeA])]
        let updated = try PresetPlanner.setDefault(id(701), for: cycling, in: d, profileID: id(950))
        #expect(updated.sportType == cycling && updated.defaultPresetID == id(701) && updated.id == id(900))

        d.sportProfiles = []
        let created = try PresetPlanner.setDefault(id(701), for: cycling, in: d, profileID: id(950))
        #expect(created.id == id(950) && created.defaultPresetID == id(701))

        #expect(throws: PresetError.presetDoesNotCover(run)) {
            _ = try PresetPlanner.setDefault(id(701), for: run, in: d, profileID: id(951))
        }
        #expect(throws: PresetError.presetNotFound(id(555))) {
            _ = try PresetPlanner.setDefault(id(555), for: cycling, in: d, profileID: id(951))
        }
        let cleared = try PresetPlanner.setDefault(nil, for: cycling, in: base(), profileID: id(951))
        #expect(cleared.defaultPresetID == nil)
    }

    @Test("Preset entfernen: Standard-Verweise in Sportprofilen werden gelöst")
    func removeClearsDefaults() {
        var d = base()
        d.presets = [GearPreset(id: id(701), name: "Rennrad", sportTypes: [cycling], memberGearIDs: [bikeA])]
        d.sportProfiles[0].defaultPresetID = id(701)
        let after = PresetPlanner.remove(id(701), from: d)
        #expect(after.presets.isEmpty && after.sportProfiles.first?.defaultPresetID == nil)
    }

    @Test("E2E: Standard-Preset ordnet beim Import alle verfügbaren Mitglieder ohne Nachfrage zu")
    func defaultPresetDrivesImport() throws {
        var d = base()
        d.presets = [GearPreset(id: id(701), name: "Rennrad", sportTypes: [cycling], memberGearIDs: [bikeA, helmet, cycShoes])]
        d.sportProfiles = [try PresetPlanner.setDefault(id(701), for: cycling, in: d, profileID: id(900))]
        let incoming = IncomingWorkout(sourceID: "W1", sportType: cycling, startAt: day(8),
                                       endAt: day(8).addingTimeInterval(3_600), distanceMeters: 30_000, durationSeconds: 3_600)
        var n = 80_000
        let out = ImportReconciler.reconcile(d, ImportBatch(upserts: [incoming]), now: now, makeID: { n += 1; return id(n) })
        #expect(out.pendingCreated.isEmpty && out.autoAssigned.count == 1)
        #expect(Set(out.dataset.assignments.map(\.gearID)) == [bikeA, helmet, cycShoes])
        #expect(out.dataset.assignments.allSatisfy { $0.origin == .preset })
    }
}

@Suite("RuleManager (SPEC 6.3, Regelansicht)")
struct RuleManagerTests {

    private func withRules() -> GearDataset {
        var d = base()
        d.assignmentRules = [AssignmentRule(id: id(801), sportType: cycling, kind: .remembered, gearIDs: [bikeA]),
                             AssignmentRule(id: id(802), sportType: cycling, kind: .explicitDefault, gearIDs: [bikeB], priority: 5)]
        return d
    }

    @Test("Deaktivieren und wieder aktivieren: nur diese Regel ändert sich")
    func toggle() throws {
        let off = try RuleManager.setEnabled(id(801), false, in: withRules())
        #expect(off.assignmentRules.map(\.enabled) == [false, true])
        let on = try RuleManager.setEnabled(id(801), true, in: off)
        #expect(on == withRules())
    }

    @Test("Unbekannte Regel wird abgewiesen")
    func unknown() {
        #expect(throws: RuleError.notFound(id(999))) { _ = try RuleManager.setEnabled(id(999), false, in: withRules()) }
        #expect(throws: RuleError.notFound(id(999))) { _ = try RuleManager.remove(id(999), from: withRules()) }
    }

    @Test("Entfernen löscht nur die Regel, Zuordnungen bleiben (kein rückwirkender Eingriff)")
    func removeKeepsAssignments() throws {
        var d = withRules()
        d.activities = [activity(1, start: day(2))]
        d.assignments = [assign(d.activities[0], bikeA)]
        let after = try RuleManager.remove(id(801), from: d)
        #expect(after.assignmentRules.map(\.id) == [id(802)] && after.assignments == d.assignments)
    }

    @Test("E2E: deaktivierte gemerkte Regel wirkt beim nächsten Import nicht mehr, aktive schon")
    func disabledRuleStopsAutomation() throws {
        let incoming = IncomingWorkout(sourceID: "W1", sportType: cycling, startAt: day(8),
                                       endAt: day(8).addingTimeInterval(3_600), distanceMeters: 30_000, durationSeconds: 3_600)
        func run(_ d: GearDataset) -> ReconcileOutput {
            var n = 90_000
            return ImportReconciler.reconcile(d, ImportBatch(upserts: [incoming]), now: now, makeID: { n += 1; return id(n) })
        }
        var only = base(); only.assignmentRules = [AssignmentRule(id: id(801), sportType: cycling, kind: .remembered, gearIDs: [bikeA])]
        #expect(run(only).autoAssigned.count == 1)
        let off = try RuleManager.setEnabled(id(801), false, in: only)
        let result = run(off)
        #expect(result.autoAssigned.isEmpty, "ohne Regel nur Nachfrage oder Vorschlag")
        #expect(result.pendingCreated.count == 1)
    }
}
