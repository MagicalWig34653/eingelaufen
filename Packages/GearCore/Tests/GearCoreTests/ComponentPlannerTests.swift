import Testing
import Foundation
@testable import GearCore

private let bike = id(1), wheel = id(2), chain = id(4), newChain = id(40), bike2 = id(5)

private func gear(_ ids: UUID...) -> [GearItem] { ids.map { GearItem(id: $0, name: "G\($0.uuidString.suffix(3))") } }

@Suite("ComponentPlanner (SPEC 4.3, 4.4, 8.4; T-02)")
struct ComponentPlannerTests {

    // MARK: montieren

    @Test("Montieren legt eine offene Montage ab dem Zeitpunkt an und vermerkt „Teil eingebaut“ am Elternteil")
    func mountCreatesOpenInstallation() throws {
        let plan = try ComponentPlanner.mount(child: chain, parent: bike, at: day(3), graph: InstallationGraph([]),
                                              gear: gear(bike, chain), installationID: id(900))
        #expect(plan.installations == [Installation(id: id(900), parentGearID: bike, childGearID: chain, startedAt: day(3))])
        #expect(plan.maintenanceEvents.map(\.kind) == [.partInstalled])
        #expect(plan.maintenanceEvents.first?.gearID == bike)
        #expect(plan.maintenanceEvents.first?.performedAt == day(3))
        #expect(plan.newGear.isEmpty)
    }

    @Test("Montieren einer schon montierten Komponente ist ein Umbau, kein Montieren (I-01)")
    func mountAlreadyMountedFails() {
        let graph = InstallationGraph([mount(chain, in: bike, from: day(0))])
        #expect(throws: ComponentPlanError.alreadyMounted(currentParent: bike)) {
            try ComponentPlanner.mount(child: chain, parent: bike2, at: day(3), graph: graph, gear: gear(bike, bike2, chain))
        }
    }

    @Test("Montieren auf sich selbst oder in den eigenen Teilebaum ist abgelehnt (I-02)")
    func mountRejectsCycles() {
        let graph = InstallationGraph([mount(wheel, in: bike, from: day(0))])
        #expect(throws: ComponentPlanError.sameGear) {
            try ComponentPlanner.mount(child: bike, parent: bike, at: day(1), graph: graph, gear: gear(bike, wheel))
        }
        #expect(throws: ComponentPlanError.wouldCreateCycle) {
            try ComponentPlanner.mount(child: bike, parent: wheel, at: day(1), graph: graph, gear: gear(bike, wheel))
        }
    }

    @Test("Unbekannter Gegenstand wird gemeldet, nicht stillschweigend montiert")
    func mountUnknownGear() {
        #expect(throws: ComponentPlanError.gearNotFound(chain)) {
            try ComponentPlanner.mount(child: chain, parent: bike, at: day(1), graph: InstallationGraph([]), gear: gear(bike))
        }
    }

    @Test("Rückdatiertes Montieren, das eine frühere Montage derselben Komponente überlappt, ist abgelehnt (I-01)")
    func mountBackdatedOverlapFails() {
        // Kette war von Tag 0 bis Tag 10 auf bike2; Montage auf bike ab Tag 5 überlappt.
        let graph = InstallationGraph([mount(chain, in: bike2, from: day(0), to: day(10))])
        #expect(throws: ComponentPlanError.overlapsExistingInstallation) {
            try ComponentPlanner.mount(child: chain, parent: bike, at: day(5), graph: graph, gear: gear(bike, bike2, chain))
        }
        // Nach dem Ausbau ist es zulässig.
        #expect(throws: Never.self) {
            try ComponentPlanner.mount(child: chain, parent: bike, at: day(10), graph: graph, gear: gear(bike, bike2, chain))
        }
    }

    // MARK: ausbauen

    @Test("Ausbauen beendet die offene Montage zum Zeitpunkt, das Teil bleibt bestehen")
    func unmountEndsInstallation() throws {
        let installation = mount(chain, in: bike, from: day(0))
        let plan = try ComponentPlanner.unmount(child: chain, at: day(8), graph: InstallationGraph([installation]),
                                                gear: gear(bike, chain))
        #expect(plan.installations.count == 1)
        #expect(plan.installations.first?.id == installation.id)
        #expect(plan.installations.first?.endedAt == day(8))
        #expect(plan.maintenanceEvents.map(\.kind) == [.partRemoved])
        #expect(plan.maintenanceEvents.first?.gearID == bike)
        #expect(plan.newGear.isEmpty && plan.statusChanges.isEmpty)
    }

    @Test("Ausbauen ohne Montage oder vor dem Einbau ist abgelehnt")
    func unmountInvalid() {
        #expect(throws: ComponentPlanError.notMounted) {
            try ComponentPlanner.unmount(child: chain, at: day(1), graph: InstallationGraph([]), gear: gear(bike, chain))
        }
        let graph = InstallationGraph([mount(chain, in: bike, from: day(5))])
        #expect(throws: ComponentPlanError.beforeInstallationStart) {
            try ComponentPlanner.unmount(child: chain, at: day(5), graph: graph, gear: gear(bike, chain))
        }
    }

    // MARK: umbauen

    @Test("Umbauen beendet die alte und startet die neue Montage zum selben Zeitpunkt; die Komponente bleibt dieselbe")
    func moveSwitchesParent() throws {
        let old = mount(chain, in: bike, from: day(0))
        let plan = try ComponentPlanner.move(child: chain, to: bike2, at: day(6), graph: InstallationGraph([old]),
                                             gear: gear(bike, bike2, chain), installationID: id(901))
        #expect(plan.installations.count == 2)
        #expect(plan.installations.first { $0.id == old.id }?.endedAt == day(6))
        let new = plan.installations.first { $0.id == id(901) }
        #expect(new?.parentGearID == bike2 && new?.childGearID == chain && new?.startedAt == day(6) && new?.endedAt == nil)
        #expect(plan.newGear.isEmpty)
        // Ergebnis ist als Ganzes gültig (keine Überlappung, kein Kreis).
        #expect(InstallationGraph(plan.installations).validate().isEmpty)
    }

    @Test("Umbauen auf dasselbe Elternteil ist abgelehnt")
    func moveToSameParent() {
        let graph = InstallationGraph([mount(chain, in: bike, from: day(0))])
        #expect(throws: ComponentPlanError.sameParent) {
            try ComponentPlanner.move(child: chain, to: bike, at: day(2), graph: graph, gear: gear(bike, chain))
        }
    }

    @Test("Umbauen in den eigenen Teilebaum ist abgelehnt (I-02), auf sich selbst ebenso")
    func moveIntoOwnSubtree() {
        // Fahrrad → Laufrad → Kette: das Laufrad auf die Kette zu setzen, wäre ein Kreis.
        let graph = InstallationGraph([mount(wheel, in: bike, from: day(0)), mount(chain, in: wheel, from: day(0))])
        #expect(throws: ComponentPlanError.wouldCreateCycle) {
            try ComponentPlanner.move(child: wheel, to: chain, at: day(2), graph: graph, gear: gear(bike, wheel, chain))
        }
        #expect(throws: ComponentPlanError.sameGear) {
            try ComponentPlanner.move(child: wheel, to: wheel, at: day(2), graph: graph, gear: gear(bike, wheel, chain))
        }
    }

    // MARK: ersetzen (SPEC 4.4)

    @Test("Ersetzen: alte Montage endet, neues Teil entsteht, neue Montage startet, altes Teil wird eingelagert")
    func replaceCreatesNewInstance() throws {
        let old = mount(chain, in: bike, from: day(0))
        let new = GearItem(id: newChain, name: "Kette neu", createdAt: day(10), category: .cycling)
        let plan = try ComponentPlanner.replace(old: chain, with: new, oldBecomes: .stored, at: day(10),
                                                graph: InstallationGraph([old]), gear: gear(bike, chain),
                                                installationID: id(902))
        #expect(plan.newGear == [new])
        #expect(plan.installations.first { $0.id == old.id }?.endedAt == day(10))
        let started = plan.installations.first { $0.id == id(902) }
        #expect(started?.parentGearID == bike && started?.childGearID == newChain && started?.startedAt == day(10))
        #expect(plan.statusChanges.map(\.gearID) == [chain])
        #expect(plan.statusChanges.map(\.status) == [.stored])
        #expect(plan.statusChanges.first?.effectiveAt == day(10))
        #expect(plan.maintenanceEvents.map(\.kind) == [.partReplaced])
        #expect(plan.maintenanceEvents.first?.gearID == bike)
    }

    @Test("Ersetzen ohne Statusänderung des alten Teils (optional, SPEC 4.4)")
    func replaceKeepsOldStatusWhenNil() throws {
        let old = mount(chain, in: bike, from: day(0))
        let plan = try ComponentPlanner.replace(old: chain, with: GearItem(id: newChain, name: "N"), oldBecomes: nil, at: day(4),
                                                graph: InstallationGraph([old]), gear: gear(bike, chain))
        #expect(plan.statusChanges.isEmpty)
    }

    @Test("Ersetzen verlangt eine Montage und ein wirklich neues Teil")
    func replaceInvalid() {
        #expect(throws: ComponentPlanError.notMounted) {
            try ComponentPlanner.replace(old: chain, with: GearItem(id: newChain, name: "N"), oldBecomes: nil, at: day(1),
                                         graph: InstallationGraph([]), gear: gear(bike, chain))
        }
        let graph = InstallationGraph([mount(chain, in: bike, from: day(0))])
        #expect(throws: ComponentPlanError.gearAlreadyExists(chain)) {
            try ComponentPlanner.replace(old: chain, with: GearItem(id: chain, name: "N"), oldBecomes: nil, at: day(1),
                                         graph: graph, gear: gear(bike, chain))
        }
        #expect(throws: ComponentPlanError.emptyName) {
            try ComponentPlanner.replace(old: chain, with: GearItem(id: newChain, name: "  "), oldBecomes: nil, at: day(1),
                                         graph: graph, gear: gear(bike, chain))
        }
    }

    // MARK: T-02 Kettenwechsel historisch konsistent

    /// Aktivitäten: Tag 2 und Tag 5 vor dem Wechsel (Tag 10), Tag 12 danach. Alle am Fahrrad zugeordnet.
    private func ride(_ n: Int, _ d: Int) -> ActivityRecord { activity(n, start: day(d), distance: 20_000) }

    @Test("T-02: Aktivität von vorher zählt der alten, nachher der neuen Kette; der Verschleiß der alten wird nicht zurückgesetzt")
    func t02_chainChangeIsHistoricallyConsistent() throws {
        let rides = [ride(1, 2), ride(2, 5), ride(3, 12)]
        let old = mount(chain, in: bike, from: day(0))
        let plan = try ComponentPlanner.replace(old: chain, with: GearItem(id: newChain, name: "Kette neu"), oldBecomes: .retired,
                                                at: day(10), graph: InstallationGraph([old]), gear: gear(bike, chain))
        let input = LedgerInput(activities: rides, assignments: rides.map { assign($0, bike) }, installations: plan.installations)
        let q = UsageQuery(entries: LedgerBuilder.build(input).entries, installations: plan.installations)
        #expect(q.lifetime(of: chain).distanceMeters == .measured(40_000, isComplete: true))
        #expect(q.lifetime(of: chain).uses == 2)
        #expect(q.lifetime(of: newChain).distanceMeters == .measured(20_000, isComplete: true))
        #expect(q.lifetime(of: newChain).uses == 1)
        #expect(q.lifetime(of: bike).uses == 3)
    }

    @Test("T-02 rückdatiert: Wechsel nachträglich auf Tag 4 verschiebt die Nutzung dazwischen, inkrementell == Neuaufbau (I-10)")
    func t02_backdatedReplaceMatchesFullRebuild() throws {
        let rides = [ride(1, 2), ride(2, 5), ride(3, 12)]
        let old = mount(chain, in: bike, from: day(0))
        let base = LedgerInput(activities: rides, assignments: rides.map { assign($0, bike) }, installations: [old])
        var projection = LedgerProjection(input: base)
        #expect(projection.entries.filter { $0.gearID == chain }.count == 3)   // vor dem Wechsel: alte Kette fährt alles

        let plan = try ComponentPlanner.replace(old: chain, with: GearItem(id: newChain, name: "Kette neu"), oldBecomes: nil,
                                                at: day(4), graph: InstallationGraph([old]), gear: gear(bike, chain))
        for installation in plan.installations { projection.apply(.upsertInstallation(installation)) }

        let full = LedgerBuilder.build(LedgerInput(activities: rides, assignments: rides.map { assign($0, bike) },
                                                   installations: plan.installations)).entries
        #expect(projection.entries == full)
        #expect(projection.entries.filter { $0.gearID == chain }.map(\.activityID) == [rides[0].id])
        #expect(Set(projection.entries.filter { $0.gearID == newChain }.map(\.activityID)) == [rides[1].id, rides[2].id])
        // Nur die vom Wechsel berührten Aktivitäten wurden neu berechnet, nicht alle.
        #expect(projection.lastRecomputedActivityCount <= 3)
    }

    @Test("Betroffene Aktivitäten einer Montage: nur die im Intervall beginnenden (für gezieltes Neuberechnen)")
    func activitiesTouchingInstallation() {
        let a = [activity(1, start: day(1)), activity(2, start: day(5)), activity(3, start: day(9))]
        let touched = LedgerProjection.activitiesTouching(Installation(parentGearID: bike, childGearID: chain, startedAt: day(4), endedAt: day(8)),
                                                          activities: a, segments: [])
        #expect(touched == [a[1].id])
    }

    // MARK: Historie

    @Test("Komponentenhistorie: aktuelle zuerst, ausgebaute danach mit Zeitraum; nach dem Tausch bleibt die alte aufrufbar")
    func historyKeepsOldComponents() throws {
        let old = mount(chain, in: bike, from: day(0))
        let plan = try ComponentPlanner.replace(old: chain, with: GearItem(id: newChain, name: "Neu"), oldBecomes: .stored,
                                                at: day(10), graph: InstallationGraph([old]), gear: gear(bike, chain),
                                                installationID: id(903))
        let history = ComponentHistory.entries(parent: bike, installations: plan.installations)
        #expect(history.map(\.childID) == [newChain, chain])
        #expect(history.map(\.isCurrent) == [true, false])
        #expect(history.last?.startedAt == day(0) && history.last?.endedAt == day(10))
        #expect(ComponentHistory.entries(parent: bike2, installations: plan.installations).isEmpty)
    }
}
