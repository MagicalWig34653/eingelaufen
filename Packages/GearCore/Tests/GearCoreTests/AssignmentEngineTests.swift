import Testing
import Foundation
@testable import GearCore

// Gear-IDs: 1/2 Laufschuhe, 3/4 Rennräder, 5 Kette (montiert), 6 Helm
private let shoesA = id(1), shoesB = id(2), bikeA = id(3), bikeB = id(4), chain = id(5), helmet = id(6)

private func item(_ n: UUID, _ category: SportCategory, status: GearStatus = .active,
                  purchase: Date? = nil, created: Int = 0) -> GearItem {
    GearItem(id: n, name: "G\(n.uuidString.suffix(2))", purchaseDate: purchase, status: status,
             createdAt: day(created), category: category)
}

private let berlin: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}()
private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func context(gear: [GearItem], rules: [AssignmentRule] = [], presets: [GearPreset] = [],
                     profiles: [SportProfile] = [], statusChanges: [GearStatusChange] = [],
                     installations: [Installation] = [], history: [ConfirmedAssignment] = [],
                     calendar: Calendar = utc, policy: EnginePolicy = EnginePolicy()) -> AssignmentContext {
    AssignmentContext(gear: gear, statusChanges: statusChanges, installations: installations, presets: presets,
                      sportProfiles: profiles, rules: rules, history: history, calendar: calendar, policy: policy)
}

private func decide(_ a: ActivityRecord, _ c: AssignmentContext) -> AssignmentDecision {
    AssignmentEngine.decide(for: a, context: c)
}

/// Standard seit Review (P-09 nicht von der Spec gedeckt): ein einziger Kandidat wird nur vorgeschlagen.
private func sole(_ g: UUID) -> AssignmentDecision {
    .propose(primary: [g], alternatives: [], reason: .soleCandidate, confidence: .medium)
}

@Suite("AssignmentEngine (SPEC 6.2, T-12)")
struct AssignmentEngineTests {

    // MARK: Explizite Information zuerst

    @Test("Eine explizite Default-Regel wird ohne Nachfrage angewendet, Konfidenz explicit")
    func explicitRuleAutoAssigns() {
        let rule = AssignmentRule(sportType: run, gearIDs: [shoesA])
        let c = context(gear: [item(shoesA, .running), item(shoesB, .running)], rules: [rule])
        #expect(decide(activity(1, start: day(5), sport: run), c)
                == .autoAssign(gear: [shoesA], reason: .rule(rule.id), confidence: .explicit))
    }

    @Test("Deaktivierte Regel und Regel für andere Sportart greifen nicht")
    func disabledOrOtherSportRuleIgnored() {
        let off = AssignmentRule(sportType: run, gearIDs: [shoesA], enabled: false)
        let other = AssignmentRule(sportType: cycling, gearIDs: [shoesA])
        let c = context(gear: [item(shoesA, .running), item(shoesB, .running)], rules: [off, other])
        #expect(decide(activity(1, start: day(5), sport: run), c)
                == .choose(candidates: [shoesA, shoesB], reason: .multipleCandidates))
    }

    @Test("Indoor-Bedingung greift nur bei belegtem Indoor-Wert, nie aus der Distanz geraten (SPEC 3.3)")
    func indoorConditionNeedsEvidence() {
        let rule = AssignmentRule(sportType: cycling, conditions: RuleConditions(isIndoor: true), gearIDs: [bikeA])
        let c = context(gear: [item(bikeA, .cycling), item(bikeB, .cycling)], rules: [rule])

        var unknown = activity(1, start: day(5), distance: nil)
        unknown.isIndoor = nil
        #expect(decide(unknown, c) == .choose(candidates: [bikeA, bikeB], reason: .multipleCandidates))

        var outdoor = activity(2, start: day(5)); outdoor.isIndoor = false
        #expect(decide(outdoor, c) == .choose(candidates: [bikeA, bikeB], reason: .multipleCandidates))

        var indoor = activity(3, start: day(5), distance: nil); indoor.isIndoor = true
        #expect(decide(indoor, c) == .autoAssign(gear: [bikeA], reason: .rule(rule.id), confidence: .explicit))
    }

    @Test("Wochentag wird in der Zeitzone der Anzeige ausgewertet, gespeichert bleibt UTC (SPEC 10.4)")
    func weekdayUsesCalendarTimeZone() {
        // 2026-01-04 23:30 UTC = Sonntag in UTC, aber Montag 00:30 in Berlin.
        let a = activity(1, start: day(3, hour: 23).addingTimeInterval(1_800), sport: run)
        let monday = AssignmentRule(sportType: run, conditions: RuleConditions(weekdays: [2]), gearIDs: [shoesA])
        let gear = [item(shoesA, .running), item(shoesB, .running)]
        #expect(decide(a, context(gear: gear, rules: [monday], calendar: berlin))
                == .autoAssign(gear: [shoesA], reason: .rule(monday.id), confidence: .explicit))
        #expect(decide(a, context(gear: gear, rules: [monday], calendar: utc))
                == .choose(candidates: [shoesA, shoesB], reason: .multipleCandidates))
    }

    @Test("Höhere Priorität gewinnt; gleichrangige widersprüchliche Regeln führen zur Nachfrage")
    func rulePriorityAndConflict() {
        let low = AssignmentRule(sportType: run, gearIDs: [shoesA], priority: 1)
        let high = AssignmentRule(sportType: run, gearIDs: [shoesB], priority: 5)
        let gear = [item(shoesA, .running), item(shoesB, .running)]
        #expect(decide(activity(1, start: day(5), sport: run), context(gear: gear, rules: [low, high]))
                == .autoAssign(gear: [shoesB], reason: .rule(high.id), confidence: .explicit))

        let tie = AssignmentRule(sportType: run, gearIDs: [shoesB], priority: 1)
        #expect(decide(activity(1, start: day(5), sport: run), context(gear: gear, rules: [low, tie]))
                == .choose(candidates: [shoesA, shoesB], reason: .conflictingRules))
    }

    // MARK: T-12 Verfügbarkeit

    @Test("T-12: Ein eingelagerter Gegenstand wird nicht aus Gewohnheit automatisch zugewiesen")
    func t12_storedGearIsNotAutoAssigned() {
        let rule = AssignmentRule(sportType: run, kind: .remembered, gearIDs: [shoesA])
        let c = context(gear: [item(shoesA, .running, status: .stored)], rules: [rule])
        #expect(decide(activity(1, start: day(5), sport: run), c) == .noGear)
    }

    @Test("T-12: Ausgemustert, verkauft, archiviert zählen nie als Kandidat; nur aktive bleiben übrig")
    func t12_inactiveStatusesExcluded() {
        for status in [GearStatus.stored, .retired, .sold, .disposed, .lost, .archived] {
            let c = context(gear: [item(shoesA, .running, status: status), item(shoesB, .running)])
            #expect(decide(activity(1, start: day(5), sport: run), c) == sole(shoesB), "\(status)")
        }
    }

    @Test("T-12: Maßgeblich ist der Status im Aktivitätszeitraum, nicht der heutige")
    func t12_statusAtActivityTime() {
        let gear = [item(shoesA, .running, status: .stored)]   // heute eingelagert
        let changes = [GearStatusChange(gearID: shoesA, status: .active, effectiveAt: day(0)),
                       GearStatusChange(gearID: shoesA, status: .stored, effectiveAt: day(10))]
        let c = context(gear: gear, statusChanges: changes)
        #expect(decide(activity(1, start: day(5), sport: run), c) == sole(shoesA))
        #expect(decide(activity(2, start: day(12), sport: run), c) == .noGear)
    }

    @Test("T-12: Noch nicht gekaufter Gegenstand wird nicht vorgeschlagen")
    func t12_notYetPurchased() {
        let c = context(gear: [item(shoesA, .running, purchase: day(20))])
        #expect(decide(activity(1, start: day(5), sport: run), c) == .noGear)
        #expect(decide(activity(2, start: day(25), sport: run), c) == sole(shoesA))
    }

    @Test("Eine Regel mit teils nicht verfügbaren Mitgliedern wird nur vorgeschlagen, nie automatisch")
    func ruleWithUnavailableMemberOnlyProposes() {
        let rule = AssignmentRule(sportType: cycling, gearIDs: [bikeA, helmet])
        let gear = [item(bikeA, .cycling), item(helmet, .cycling, status: .retired)]
        #expect(decide(activity(1, start: day(5)), context(gear: gear, rules: [rule]))
                == .propose(primary: [bikeA], alternatives: [], reason: .unavailableMembersDropped, confidence: .medium))
    }

    // MARK: Presets

    @Test("Standard-Preset aus dem Sportprofil gilt explizit, ein einziges passendes Preset gilt mit high")
    func presetsApplyWithoutPrompt() {
        let preset = GearPreset(name: "Rennrad-Set", sportTypes: [cycling], memberGearIDs: [bikeA, helmet])
        let gear = [item(bikeA, .cycling), item(helmet, .cycling), item(bikeB, .cycling)]
        let withDefault = context(gear: gear, presets: [preset],
                                  profiles: [SportProfile(sportType: cycling, defaultPresetID: preset.id)])
        #expect(decide(activity(1, start: day(5)), withDefault)
                == .autoAssign(gear: [bikeA, helmet], reason: .defaultPreset(preset.id), confidence: .explicit))

        let single = context(gear: gear, presets: [preset])
        #expect(decide(activity(1, start: day(5)), single)
                == .autoAssign(gear: [bikeA, helmet], reason: .preset(preset.id), confidence: .high))
    }

    @Test("Mehrere passende Presets ohne Standard: nachfragen statt eines zu erzwingen")
    func multiplePresetsAsk() {
        let p1 = GearPreset(name: "A", sportTypes: [cycling], memberGearIDs: [bikeA])
        let p2 = GearPreset(name: "B", sportTypes: [cycling], memberGearIDs: [bikeB])
        let c = context(gear: [item(bikeA, .cycling), item(bikeB, .cycling)], presets: [p1, p2])
        #expect(decide(activity(1, start: day(5)), c) == .choose(candidates: [bikeA, bikeB], reason: .multipleCandidates))
    }

    @Test("Ein Fahrrad impliziert nie automatisch Helm oder Schuhe (SPEC 5.2)")
    func noImplicitInheritanceBetweenIndependentGear() {
        let gear = [item(bikeA, .cycling), item(helmet, .cycling)]
        if case let .autoAssign(assigned, _, _) = decide(activity(1, start: day(5)), context(gear: gear)) {
            Issue.record("Zwei unabhängige Kandidaten dürfen nicht automatisch gewählt werden: \(assigned)")
        }
    }

    // MARK: Heuristik, konservativ

    @Test("Ein einziger passender Kandidat wird vorgeschlagen, die Kette im Fahrrad zählt nicht als Kandidat")
    func soleCandidateIgnoresMountedComponents() {
        let gear = [item(bikeA, .cycling), item(chain, .cycling)]
        let mounted = [mount(chain, in: bikeA, from: day(0))]
        #expect(decide(activity(1, start: day(5)), context(gear: gear, installations: mounted)) == sole(bikeA))
        // Ausgebaut zum Aktivitätszeitpunkt: dann ist die Kette wieder ein eigener Kandidat.
        let unmounted = [mount(chain, in: bikeA, from: day(0), to: day(3))]
        #expect(decide(activity(1, start: day(5)), context(gear: gear, installations: unmounted))
                == .choose(candidates: [bikeA, chain], reason: .multipleCandidates))
    }

    @Test("P-09: Ohne Regel wird auch ein einziger Kandidat nie automatisch gebucht, nur vorgeschlagen (Spec 6.2, 17)")
    func soleCandidateIsOnlyProposedByDefault() {
        #expect(EnginePolicy().autoAssignSoleCandidate == false)
        let c = context(gear: [item(shoesA, .running)])
        #expect(decide(activity(1, start: day(5), sport: run), c) == sole(shoesA))
    }

    @Test("P-09: Die Option autoAssignSoleCandidate bleibt als ausdrücklicher Schalter erhalten")
    func soleCandidateOptIn() {
        let c = context(gear: [item(shoesA, .running)], policy: EnginePolicy(autoAssignSoleCandidate: true))
        #expect(decide(activity(1, start: day(5), sport: run), c)
                == .autoAssign(gear: [shoesA], reason: .soleCandidate, confidence: .high))
    }

    @Test("Mehrere Kandidaten ohne Regel: nachfragen, nie raten")
    func multipleCandidatesAsk() {
        let c = context(gear: [item(shoesA, .running), item(shoesB, .running)])
        #expect(decide(activity(1, start: day(5), sport: run), c)
                == .choose(candidates: [shoesA, shoesB], reason: .multipleCandidates))
    }

    @Test("Konsistente bestätigte Historie ergibt höchstens einen Vorschlag mit medium, nie eine Automatik")
    func historyOnlyProposes() {
        let gear = [item(shoesA, .running), item(shoesB, .running)]
        let history = [ConfirmedAssignment(sportType: run, gearIDs: [shoesB], confirmedAt: day(1)),
                       ConfirmedAssignment(sportType: run, gearIDs: [shoesB], confirmedAt: day(2))]
        #expect(decide(activity(1, start: day(5), sport: run), context(gear: gear, history: history))
                == .propose(primary: [shoesB], alternatives: [[shoesA]], reason: .history, confidence: .medium))
    }

    @Test("Uneinheitliche oder zu kurze Historie: nachfragen")
    func weakHistoryAsks() {
        let gear = [item(shoesA, .running), item(shoesB, .running)]
        let mixed = [ConfirmedAssignment(sportType: run, gearIDs: [shoesB], confirmedAt: day(1)),
                     ConfirmedAssignment(sportType: run, gearIDs: [shoesA], confirmedAt: day(2))]
        let short = [ConfirmedAssignment(sportType: run, gearIDs: [shoesB], confirmedAt: day(1))]
        for history in [mixed, short] {
            #expect(decide(activity(1, start: day(5), sport: run), context(gear: gear, history: history))
                    == .choose(candidates: [shoesA, shoesB], reason: .multipleCandidates))
        }
    }

    @Test("Historie mit inzwischen nicht verfügbarem Gegenstand schlägt diesen nicht mehr vor")
    func historyIgnoresUnavailableGear() {
        let gear = [item(shoesA, .running), item(shoesB, .running, status: .retired), item(helmet, .running)]
        let history = [ConfirmedAssignment(sportType: run, gearIDs: [shoesB], confirmedAt: day(1)),
                       ConfirmedAssignment(sportType: run, gearIDs: [shoesB], confirmedAt: day(2))]
        #expect(decide(activity(1, start: day(5), sport: run), context(gear: gear, history: history))
                == .choose(candidates: [shoesA, helmet], reason: .multipleCandidates))
    }

    @Test("Ohne passende Ausrüstung: Ohne Ausrüstung; deaktivierte Sportart ebenso")
    func noGearAndDisabledSport() {
        #expect(decide(activity(1, start: day(5), sport: run), context(gear: [item(bikeA, .cycling)])) == .noGear)
        let off = SportProfile(sportType: run, enabled: false)
        #expect(decide(activity(1, start: day(5), sport: run), context(gear: [item(shoesA, .running)], profiles: [off])) == .noGear)
    }

    @Test("Unbekannte Sportart landet in Sonstige und kann dennoch Kandidaten finden")
    func unknownSportUsesOtherCategory() {
        let weird = SportType(rawValue: 9_999)
        let c = context(gear: [item(shoesA, .other)])
        #expect(decide(activity(1, start: day(5), sport: weird), c) == sole(shoesA))
    }

    @Test("Die Entscheidung ist deterministisch, unabhängig von der Eingabereihenfolge")
    func deterministic() {
        let gear = [item(shoesA, .running, created: 1), item(shoesB, .running, created: 2)]
        let a = activity(1, start: day(5), sport: run)
        #expect(decide(a, context(gear: gear)) == decide(a, context(gear: gear.reversed())))
    }
}
