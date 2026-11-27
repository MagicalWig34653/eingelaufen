import Testing
import Foundation
@testable import GearCore

// M6: Planer für lokale Benachrichtigungen (SPEC 7.2, 7.4; ARCHITEKTUR 6.2; PLATTFORM F-10).

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()
private let now = day(30, hour: 12)
private let bikeA = id(3), bikeB = id(4)

private func suggested(_ n: Int, revision: Int = 1, state: PendingState = .suggested) -> PendingAssignment {
    PendingAssignment(id: id(500 + n), activityID: id(1_000 + n), state: state, proposedGearIDs: [bikeA],
                      alternatives: [[bikeB]], reason: .history, confidence: .medium, proposalRevision: revision, createdAt: day(29))
}

private func ambiguous(_ n: Int) -> PendingAssignment {
    PendingAssignment(id: id(500 + n), activityID: id(1_000 + n), state: .unresolved, candidateGearIDs: [bikeA, bikeB],
                      reason: .multipleCandidates, createdAt: day(29))
}

private func plan(_ open: [PendingAssignment] = [], maintenance: [MaintenanceHint] = [], sent: [SentNotification] = [],
                  existing: Set<String> = [], prefs: NotificationPreferences = .init(), authorized: Bool = true,
                  at: Date = now) -> NotificationPlan {
    NotificationPlanner.plan(open: open, maintenance: maintenance, sent: sent, existing: existing,
                             preferences: prefs, authorized: authorized, now: at, calendar: utc)
}

private func due(_ rule: Int, gear: Int = 3) -> MaintenanceHint {
    MaintenanceHint(gearID: id(gear), ruleID: id(rule), state: .due, source: .interval)
}

@Suite("NotificationPlanner (Spec 7.2, 7.4)")
struct NotificationPlannerTests {

    // MARK: Aktionen in fester Reihenfolge (F-10)

    @Test func proposalActionsInFixedOrderSoTheFirstTwoAreConfirmAndChoose() {
        #expect(NotificationCatalog.actions(for: .proposal) == [.confirm, .choose, .later])
        #expect(Array(NotificationCatalog.actions(for: .proposal).prefix(2)) == [.confirm, .choose])
    }

    @Test func ambiguousOffersChooseInsteadOfAForcedProposal() {
        #expect(NotificationCatalog.actions(for: .choose) == [.choose, .later])
        #expect(!NotificationCatalog.actions(for: .choose).contains(.confirm))
        #expect(NotificationCatalog.actions(for: .maintenance) == [.checkMaintenance])
        #expect(NotificationCatalog.actions(for: .inboxSummary).isEmpty)
    }

    @Test func onlyChooseAndCheckOpenTheApp() {
        #expect(NotificationAction.allCases.filter(\.opensApp) == [.choose, .checkMaintenance])
    }

    // MARK: Einzelmeldung, Payload, Idempotenz

    @Test func singleSuggestionBecomesProposalWithPendingAndRevisionInPayload() {
        let p = plan([suggested(1, revision: 3)])
        #expect(p.schedule.count == 1)
        guard let n = p.schedule.first else { return }
        #expect(n.identifier == NotificationIdentifier.pending(id(501)))
        #expect(n.category == .proposal)
        #expect(n.threadID == NotificationIdentifier.inboxThread)
        #expect(n.deliverAt == now)
        #expect(n.payload.pendingID == id(501))
        #expect(n.payload.proposalRevision == 3)
        #expect(n.payload.activityID == id(1_001))
        #expect(p.records == [SentNotification(relatedID: id(501), revision: 3, identifier: n.identifier, sentAt: now)])
    }

    @Test func ambiguousEntryUsesChooseCategory() {
        #expect(plan([ambiguous(1)]).schedule.first?.category == .choose)
    }

    @Test func payloadSurvivesUserInfoRoundTrip() {
        let payload = NotificationPayload(pendingID: id(501), proposalRevision: 4, activityID: id(1_001), gearID: id(3), count: 2)
        #expect(NotificationPayload(userInfo: payload.userInfo) == payload)
        #expect(NotificationPayload(userInfo: ["pendingID": "kaputt", "proposalRevision": "x"]) == NotificationPayload())
    }

    @Test func samePendingAndRevisionIsNotNotifiedTwice() {
        let first = plan([suggested(1)])
        let second = plan([suggested(1)], sent: first.records, existing: [NotificationIdentifier.pending(id(501))])
        #expect(second.schedule.isEmpty)
        #expect(second.records.isEmpty)
        #expect(second.remove.isEmpty)
    }

    @Test func newRevisionReplacesUnderTheSameIdentifier() {
        let first = plan([suggested(1, revision: 1)])
        let second = plan([suggested(1, revision: 2)], sent: first.records, existing: [NotificationIdentifier.pending(id(501))])
        #expect(second.schedule.map(\.identifier) == [NotificationIdentifier.pending(id(501))])
        #expect(second.schedule.first?.payload.proposalRevision == 2)
    }

    @Test func laterDoesNotRenotifyTheSameRevision() {
        let sent = [SentNotification(relatedID: id(501), revision: 1, identifier: NotificationIdentifier.pending(id(501)), sentAt: day(29))]
        #expect(plan([suggested(1, state: .ignored)], sent: sent).schedule.isEmpty)
    }

    @Test func resolvedOrVanishedEntryRemovesItsNotification() {
        let ident = NotificationIdentifier.pending(id(501))
        let p = plan([], existing: [ident, "fremd.123"])
        #expect(p.remove == [ident])
        #expect(p.schedule.isEmpty)
    }

    @Test func entryWithoutAnyCandidateIsNotNotified() {
        var none = ambiguous(1)
        none.candidateGearIDs = []
        none.reason = .noCandidates
        #expect(plan([none]).schedule.isEmpty)
    }

    // MARK: Bündelung

    @Test func twoOrMoreOpenEntriesBecomeOneSummary() {
        let p = plan([suggested(1), ambiguous(2), suggested(3)])
        #expect(p.schedule.count == 1)
        #expect(p.schedule.first?.identifier == NotificationIdentifier.inboxSummary)
        #expect(p.schedule.first?.category == .inboxSummary)
        #expect(p.schedule.first?.payload.count == 3)
        #expect(Set(p.records.map(\.relatedID)) == [id(501), id(502), id(503)])
    }

    @Test func summaryReplacesTheEarlierSingleNotification() {
        let first = plan([suggested(1)])
        let second = plan([suggested(1), suggested(2)], sent: first.records, existing: [NotificationIdentifier.pending(id(501))])
        #expect(second.schedule.map(\.identifier) == [NotificationIdentifier.inboxSummary])
        #expect(second.schedule.first?.payload.count == 2)
        #expect(second.remove == [NotificationIdentifier.pending(id(501))])
    }

    @Test func summaryDisappearsWhenFewerThanTwoRemainOpen() {
        let sent = [1, 2].map { SentNotification(relatedID: id(500 + $0), revision: 1, identifier: NotificationIdentifier.inboxSummary, sentAt: day(29)) }
        let p = plan([suggested(1)], sent: sent, existing: [NotificationIdentifier.inboxSummary])
        #expect(p.remove == [NotificationIdentifier.inboxSummary])
        #expect(p.schedule.isEmpty)
    }

    // MARK: Ruhezeiten

    @Test func insideQuietHoursDeliveryMovesToTheirEnd() {
        let quiet = NotificationPreferences(level: .assignmentAndMaintenance, quietHours: QuietHours(startMinute: 22 * 60, endMinute: 7 * 60))
        let late = day(30, hour: 23)
        #expect(plan([suggested(1)], prefs: quiet, at: late).schedule.first?.deliverAt == day(31, hour: 7))
        let early = day(30, hour: 5)
        #expect(plan([suggested(1)], prefs: quiet, at: early).schedule.first?.deliverAt == day(30, hour: 7))
        #expect(plan([suggested(1)], prefs: quiet, at: now).schedule.first?.deliverAt == now)
    }

    @Test func quietHoursWithinOneDayAndEmptyRange() {
        let lunch = QuietHours(startMinute: 12 * 60, endMinute: 13 * 60 + 30)
        #expect(lunch.contains(day(1, hour: 12), calendar: utc))
        #expect(!lunch.contains(day(1, hour: 14), calendar: utc))
        #expect(lunch.deliveryDate(for: day(1, hour: 12), calendar: utc) == day(1, hour: 12).addingTimeInterval(90 * 60))
        #expect(!QuietHours(startMinute: 600, endMinute: 600).contains(day(1, hour: 10), calendar: utc))
    }

    // MARK: Stufen und Berechtigung

    @Test func levelOffOrMissingPermissionSchedulesNothingAndClearsOwnNotifications() {
        let existing: Set<String> = [NotificationIdentifier.pending(id(501)), "fremd.1"]
        for p in [plan([suggested(1)], maintenance: [due(70)], existing: existing, prefs: .init(level: .off)),
                  plan([suggested(1)], maintenance: [due(70)], existing: existing, authorized: false)] {
            #expect(p.schedule.isEmpty)
            #expect(p.records.isEmpty)
            #expect(p.remove == [NotificationIdentifier.pending(id(501))])
        }
    }

    @Test func assignmentOnlySkipsMaintenance() {
        let p = plan([suggested(1)], maintenance: [due(70)], existing: [NotificationIdentifier.maintenance(id(70))],
                     prefs: .init(level: .assignmentOnly))
        #expect(p.schedule.map(\.category) == [.proposal])
        #expect(p.remove == [NotificationIdentifier.maintenance(id(70))])
    }

    @Test func permissionIsRequestedOnlyInContext() {
        #expect(!NotificationPlanner.shouldRequestAuthorization(undetermined: true, level: .assignmentAndMaintenance,
                                                                openAssignments: 0, enabledMaintenanceRules: 0))
        #expect(NotificationPlanner.shouldRequestAuthorization(undetermined: true, level: .assignmentOnly,
                                                               openAssignments: 1, enabledMaintenanceRules: 0))
        #expect(NotificationPlanner.shouldRequestAuthorization(undetermined: true, level: .assignmentAndMaintenance,
                                                               openAssignments: 0, enabledMaintenanceRules: 1))
        #expect(!NotificationPlanner.shouldRequestAuthorization(undetermined: true, level: .assignmentOnly,
                                                                openAssignments: 0, enabledMaintenanceRules: 1))
        #expect(!NotificationPlanner.shouldRequestAuthorization(undetermined: true, level: .off,
                                                                openAssignments: 3, enabledMaintenanceRules: 3))
        #expect(!NotificationPlanner.shouldRequestAuthorization(undetermined: false, level: .assignmentAndMaintenance,
                                                                openAssignments: 3, enabledMaintenanceRules: 3))
    }

    // MARK: Wartung mit Cooldown (SPEC 7.4)

    @Test func dueMaintenanceSaysCheckWithDeepLinkPayload() {
        let p = plan(maintenance: [due(70, gear: 3)])
        #expect(p.schedule.count == 1)
        #expect(p.schedule.first?.identifier == NotificationIdentifier.maintenance(id(70)))
        #expect(p.schedule.first?.category == .maintenance)
        #expect(p.schedule.first?.threadID == NotificationIdentifier.maintenanceThread)
        #expect(p.schedule.first?.payload.gearID == id(3))
        #expect(p.records.first?.relatedID == id(70))
    }

    @Test func dueSoonIsNoReminder() {
        #expect(plan(maintenance: [MaintenanceHint(gearID: id(3), ruleID: id(70), state: .dueSoon, source: .interval)]).schedule.isEmpty)
    }

    @Test func maintenanceRepeatsOnlyAfterSevenDayCooldown() {
        let ident = NotificationIdentifier.maintenance(id(70))
        let sent = [SentNotification(relatedID: id(70), revision: RuleState.due.rawValue, identifier: ident, sentAt: now)]
        #expect(plan(maintenance: [due(70)], sent: sent, at: now.addingTimeInterval(6 * 86_400)).schedule.isEmpty)
        #expect(plan(maintenance: [due(70)], sent: sent, at: now.addingTimeInterval(7 * 86_400)).schedule.map(\.identifier) == [ident])
    }

    @Test func measurementLimitWithoutRuleIsKeyedByGear() {
        let p = plan(maintenance: [MaintenanceHint(gearID: id(3), ruleID: nil, state: .due, source: .measurement)])
        #expect(p.schedule.first?.identifier == NotificationIdentifier.maintenance(id(3)))
    }

    @Test func severalDueMaintenancesAreBundledAndStopWhenDone() {
        let p = plan(maintenance: [due(70, gear: 3), due(71, gear: 4)])
        #expect(p.schedule.map(\.identifier) == [NotificationIdentifier.maintenanceSummary])
        #expect(p.schedule.first?.payload.count == 2)
        let done = plan(maintenance: [], existing: [NotificationIdentifier.maintenanceSummary, NotificationIdentifier.maintenance(id(70))])
        #expect(Set(done.remove) == [NotificationIdentifier.maintenanceSummary, NotificationIdentifier.maintenance(id(70))])
    }

    @Test func onlyEnabledRulesProduceDueMaintenance() {
        let gear = GearItem(id: id(3), name: "Rad", createdAt: day(0), category: .cycling)
        let on = MaintenanceRule(id: id(70), gearID: id(3), kind: .inspected, metric: .calendarAge, intervalValue: 10)
        var off = MaintenanceRule(id: id(71), gearID: id(3), kind: .lubricated, metric: .calendarAge, intervalValue: 10)
        off.enabled = false
        let hints = NotificationPlanner.dueMaintenance(rules: [on, off], events: [], entries: [], installations: [],
                                                       gear: [gear], now: day(30))
        #expect(hints.map(\.ruleID) == [id(70)])
        #expect(hints.allSatisfy { $0.state == .due })
    }

    @Test func assignmentsComeBeforeMaintenanceInThePlan() {
        let p = plan([suggested(1)], maintenance: [due(70)])
        #expect(p.schedule.map(\.category) == [.proposal, .maintenance])
    }

    // MARK: Antwort auf eine Aktion (T-10 mit dem Reducer)

    @Test func confirmActionMapsToTheSameInboxCommandWithRevision() {
        let info = NotificationPayload(pendingID: id(501), proposalRevision: 2).userInfo
        #expect(NotificationResponse.effect(actionIdentifier: "confirm", categoryIdentifier: "proposal", userInfo: info)
                == .resolve(pendingID: id(501), action: .confirm(proposalRevision: 2)))
        #expect(NotificationResponse.effect(actionIdentifier: "later", categoryIdentifier: "proposal", userInfo: info)
                == .resolve(pendingID: id(501), action: .later))
        #expect(NotificationResponse.effect(actionIdentifier: "choose", categoryIdentifier: "proposal", userInfo: info)
                == .openInbox(pendingID: id(501)))
    }

    @Test func tapsAndMaintenanceOpenTheRightScreen() {
        let maint = NotificationPayload(gearID: id(3)).userInfo
        #expect(NotificationResponse.effect(actionIdentifier: "checkMaintenance", categoryIdentifier: "maintenance", userInfo: maint)
                == .openMaintenance(gearID: id(3)))
        #expect(NotificationResponse.effect(actionIdentifier: NotificationResponse.defaultActionIdentifier,
                                            categoryIdentifier: "maintenance", userInfo: maint) == .openMaintenance(gearID: id(3)))
        #expect(NotificationResponse.effect(actionIdentifier: NotificationResponse.defaultActionIdentifier,
                                            categoryIdentifier: "inboxSummary", userInfo: NotificationPayload(count: 2).userInfo)
                == .openInbox(pendingID: nil))
        #expect(NotificationResponse.effect(actionIdentifier: NotificationResponse.dismissActionIdentifier,
                                            categoryIdentifier: "proposal", userInfo: NotificationPayload(pendingID: id(501)).userInfo) == .none)
    }

    @Test func confirmWithoutRevisionOrPendingDoesNothing() {
        #expect(NotificationResponse.effect(actionIdentifier: "confirm", categoryIdentifier: "proposal",
                                            userInfo: NotificationPayload(pendingID: id(501)).userInfo) == .none)
        #expect(NotificationResponse.effect(actionIdentifier: "confirm", categoryIdentifier: "proposal", userInfo: [:]) == .none)
    }

    @Test func T10_repeatedNotificationActionBooksAtMostOnce() {
        let pending = suggested(1, revision: 2)
        guard case let .resolve(pid, action) = NotificationResponse.effect(
            actionIdentifier: "confirm", categoryIdentifier: "proposal",
            userInfo: NotificationPayload(pendingID: pending.id, proposalRevision: 2).userInfo) else {
            Issue.record("keine Auflösung"); return
        }
        #expect(pid == pending.id)
        let first = InboxReducer.reduce(pending, action, now: now)
        #expect(first.result == .applied && first.assignments.count == 1)
        let second = InboxReducer.reduce(first.pending, action, now: now)
        #expect(second.result == .noOp(.alreadyFinal(.resolved)) && second.assignments.isEmpty)
    }

    @Test func T10_staleNotificationAfterEditBooksNothing() {
        let shown = suggested(1, revision: 1)
        let edited = InboxReducer.reduce(shown, .propose(gear: [bikeB], alternatives: [], reason: .history, confidence: .medium), now: now).pending
        guard case let .resolve(_, action) = NotificationResponse.effect(
            actionIdentifier: "confirm", categoryIdentifier: "proposal",
            userInfo: NotificationPayload(pendingID: shown.id, proposalRevision: shown.proposalRevision).userInfo) else {
            Issue.record("keine Auflösung"); return
        }
        let outcome = InboxReducer.reduce(edited, action, now: now)
        #expect(outcome.result == .noOp(.staleRevision))
        #expect(outcome.assignments.isEmpty)
    }
}
