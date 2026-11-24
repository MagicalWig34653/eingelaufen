import Testing
import Foundation
@testable import GearCore

// Gear-IDs: 1 Fahrrad, 2 Laufradsatz, 3 Reifen, 4 Kette, 5 zweites Fahrrad
private let bike = id(1), wheel = id(2), tire = id(3), chain = id(4), bike2 = id(5)

@Suite("InstallationGraph (I-01…I-03, T-13)")
struct InstallationGraphTests {

    @Test("T-13: Montagekreis direkt (A in B, B in A) wird erkannt")
    func t13_directCycle() {
        let graph = InstallationGraph([
            mount(wheel, in: bike, from: day(0)),
            mount(bike, in: wheel, from: day(0)),
        ])
        let issues = graph.validate()
        #expect(issues.contains { if case .cycle = $0 { true } else { false } })
    }

    @Test("T-13: Kreis über drei Ebenen (Fahrrad → Laufrad → Reifen → Fahrrad)")
    func t13_transitiveCycle() {
        let graph = InstallationGraph([
            mount(wheel, in: bike, from: day(0)),
            mount(tire, in: wheel, from: day(0)),
            mount(bike, in: tire, from: day(0)),
        ])
        #expect(graph.validate().contains { if case .cycle = $0 { true } else { false } })
    }

    @Test("T-13: Kreis entsteht nur in einem Zeitfenster, nicht „jetzt“ (alle Intervallgrenzen geprüft)")
    func t13_cycleOnlyInPast() {
        // Zwischen Tag 2 und Tag 3 hängen beide ineinander; heute (Tag 10) nicht mehr.
        let graph = InstallationGraph([
            mount(wheel, in: bike, from: day(0), to: day(3)),
            mount(bike, in: wheel, from: day(2), to: day(4)),
        ])
        let cycles = graph.validate().compactMap { issue -> Date? in
            if case let .cycle(at, _) = issue { at } else { nil }
        }
        #expect(cycles == [day(2)])
    }

    @Test("T-13: zeitlich überlappende Montagen derselben Komponente werden erkannt")
    func t13_overlappingChildInstallations() {
        let first = mount(chain, in: bike, from: day(0), to: day(10))
        let second = mount(chain, in: bike2, from: day(5))
        let issues = InstallationGraph([first, second]).validate()
        #expect(issues.contains(.overlappingChildInstallations(
            childGearID: chain, first: first.id, second: second.id)) ||
                issues.contains(.overlappingChildInstallations(
                    childGearID: chain, first: second.id, second: first.id)))
    }

    @Test("Umbau ohne Lücke: Ende = Beginn der Folgemontage ist erlaubt (halb offenes Intervall)")
    func touchingIntervalsAreFine() {
        let graph = InstallationGraph([
            mount(chain, in: bike, from: day(0), to: day(5)),
            mount(chain, in: bike2, from: day(5)),
        ])
        #expect(graph.validate().isEmpty)
        #expect(graph.parent(of: chain, at: day(5).addingTimeInterval(-1)) == bike)
        #expect(graph.parent(of: chain, at: day(5)) == bike2)
    }

    @Test("Zwei offene Montagen derselben Komponente überlappen immer")
    func twoOpenEndedOverlap() {
        let graph = InstallationGraph([
            mount(chain, in: bike, from: day(0)),
            mount(chain, in: bike2, from: day(100)),
        ])
        #expect(graph.validate().contains { if case .overlappingChildInstallations = $0 { true } else { false } })
    }

    @Test("I-03: Ende muss nach dem Beginn liegen")
    func endMustBeAfterStart() {
        let equal = mount(chain, in: bike, from: day(3), to: day(3))
        let before = mount(tire, in: wheel, from: day(3), to: day(1))
        let issues = InstallationGraph([equal, before]).validate()
        #expect(issues.contains(.endNotAfterStart(installationID: equal.id)))
        #expect(issues.contains(.endNotAfterStart(installationID: before.id)))
    }

    @Test("Ein Gegenstand kann nicht in sich selbst montiert sein")
    func selfInstallation() {
        let selfMount = mount(bike, in: bike, from: day(0))
        #expect(InstallationGraph([selfMount]).validate().contains(.selfInstallation(installationID: selfMount.id)))
    }

    @Test("I-03: Montage vor dem Kaufdatum ist nur eine Warnung, keine Sperre")
    func startsBeforePurchaseIsWarning() {
        let gear = GearItem(id: chain, name: "Kette", purchaseDate: day(10))
        let early = mount(chain, in: bike, from: day(2))
        let graph = InstallationGraph([early])
        #expect(graph.validate().isEmpty)
        let warnings = graph.purchaseWarnings(gear: [gear])
        #expect(warnings == [.startsBeforePurchase(installationID: early.id, gearID: chain)])
        #expect(warnings.allSatisfy { $0.isWarning })
    }

    @Test("Unbekanntes Kaufdatum erzeugt keine Warnung")
    func unknownPurchaseDateNoWarning() {
        let graph = InstallationGraph([mount(chain, in: bike, from: day(2))])
        #expect(graph.purchaseWarnings(gear: [GearItem(id: chain, name: "Kette")]).isEmpty)
    }

    @Test("Nachfahren sind transitiv und zeitabhängig (Fahrrad → Laufrad → Reifen)")
    func descendantsAreTransitiveAndTimeDependent() {
        let graph = InstallationGraph([
            mount(wheel, in: bike, from: day(0)),
            mount(tire, in: wheel, from: day(0), to: day(5)),
            mount(chain, in: bike, from: day(0)),
        ])
        #expect(Set(graph.descendants(of: bike, at: day(1))) == [wheel, tire, chain])
        #expect(Set(graph.descendants(of: bike, at: day(5))) == [wheel, chain])
        #expect(graph.descendants(of: chain, at: day(1)).isEmpty)
        #expect(graph.children(of: bike, at: day(1)).count == 2)
    }

    @Test("Vorfahren: der Weg vom Teil bis zur obersten Ausrüstung, zeitabhängig und kreissicher (M5-Befund)")
    func ancestorsWalkUpToTheTopAndTerminate() {
        let graph = InstallationGraph([
            mount(wheel, in: bike, from: day(0), to: day(5)),
            mount(wheel, in: bike2, from: day(5)),
            mount(tire, in: wheel, from: day(0)),
        ])
        #expect(graph.ancestors(of: tire, at: day(1)) == [wheel, bike])
        #expect(graph.ancestors(of: tire, at: day(6)) == [wheel, bike2])
        #expect(graph.ancestors(of: bike, at: day(1)).isEmpty)
        let loop = InstallationGraph([mount(wheel, in: bike, from: day(0)), mount(bike, in: wheel, from: day(0))])
        #expect(loop.ancestors(of: wheel, at: day(1)).count <= 2)
    }

    @Test("Nachfahren-Suche terminiert auch bei kaputten Daten mit Kreis")
    func descendantsTerminateOnCycle() {
        let graph = InstallationGraph([
            mount(wheel, in: bike, from: day(0)),
            mount(bike, in: wheel, from: day(0)),
        ])
        #expect(Set(graph.descendants(of: bike, at: day(1))) == [wheel])
    }

    @Test("Neue Montage prüfen: erlaubter Umbau liefert keine Probleme")
    func validatingAddingValid() {
        let existing = mount(chain, in: bike, from: day(0), to: day(5))
        let graph = InstallationGraph([existing])
        #expect(graph.validating(adding: mount(chain, in: bike2, from: day(5))).isEmpty)
    }

    @Test("Neue Montage prüfen: rückdatierte Überlappung und Kreis werden abgelehnt, Bestand bleibt unberührt")
    func validatingAddingRejectsOverlapAndCycle() {
        let existing = mount(wheel, in: bike, from: day(0))
        let graph = InstallationGraph([existing])
        // Rückdatiert in ein anderes Fahrrad, obwohl noch im ersten montiert
        let overlap = graph.validating(adding: mount(wheel, in: bike2, from: day(3)))
        #expect(overlap.contains { if case .overlappingChildInstallations = $0 { true } else { false } })
        // Fahrrad in sein eigenes Laufrad hängen
        let cycle = graph.validating(adding: mount(bike, in: wheel, from: day(1)))
        #expect(cycle.contains { if case .cycle = $0 { true } else { false } })
        #expect(graph.installations.count == 1)
    }

    @Test("Aktuelle Montage einer Komponente = die ohne Ende")
    func currentInstallation() {
        let old = mount(chain, in: bike, from: day(0), to: day(5))
        let current = mount(chain, in: bike2, from: day(5))
        let graph = InstallationGraph([old, current])
        #expect(graph.currentInstallation(of: chain)?.id == current.id)
        #expect(InstallationGraph([old]).currentInstallation(of: chain) == nil)
    }
}
