import XCTest

/// M4 (PLAN, Spec Phase 1): Posteingang S05. Fixture „inbox“: Canyon Endurace und Cube Agree (Rennräder), Helm, Radschuhe,
/// Set „Rennrad komplett“ (Canyon, Helm, Radschuhe), eine abgeschlossene Fahrt auf dem Canyon (Tag 2) und zwei offene
/// Aktivitäten: Tag 8 mit Vorschlag Canyon (neueste zuerst), Tag 6 ohne Vorschlag (Cube und Canyon gleich plausibel).
final class InboxUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func openInbox(_ app: XCUIApplication) {
        let link = app.buttons["inboxLink"]
        XCTAssertTrue(app.reveal(link), "Übersicht zeigt offene Zuordnungen prominent")
        XCTAssertTrue(link.label.contains("2"), "zwei offene Aktivitäten: \(link.label)")
        link.tap()
        XCTAssertTrue(app.navigationBars["Zuordnung"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testTwoBikesOneOpenActivityOneTap() {
        let app = launch("inbox")
        openInbox(app)
        let confirm = app.buttons["inboxConfirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Canyon Endurace"].firstMatch.exists, "Vorschlag ist sichtbar benannt")
        confirm.tap()
        // Die bestätigte Karte verschwindet, die zweite bleibt (ohne Vorschlag gibt es keinen Bestätigen-Knopf).
        XCTAssertTrue(app.buttons["inboxChange"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["inboxConfirm"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        let link = app.buttons["inboxLink"]
        XCTAssertTrue(app.reveal(link))
        XCTAssertTrue(link.label.contains("1"), "noch eine offen: \(link.label)")
    }

    @MainActor
    func testBikeHelmetAndShoesInOneDialog() {
        let app = launch("inbox")
        openInbox(app)
        app.buttons["inboxChange"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.navigationBars["Ausrüstung wählen"].waitForExistence(timeout: 8))
        app.buttons["presetOffer.Rennrad komplett"].tapWhenReady()
        app.buttons["assignConfirm"].tapWhenReady()
        XCTAssertTrue(app.navigationBars["Zuordnung"].waitForExistence(timeout: 8))
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["Verlauf"].tapWhenReady()
        let row = app.element(labelContaining: "Canyon Endurace, Helm, Radschuhe")
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Die Aktivität trägt alle drei Teile")
    }

    @MainActor
    func testRememberCreatesRuleThatCanBeSwitchedOff() {
        let app = launch("inbox")
        openInbox(app)
        let remember = app.switches["inboxRemember"].firstMatch
        XCTAssertTrue(remember.waitForExistence(timeout: 8))
        remember.tap()
        app.buttons["inboxConfirm"].firstMatch.tap()
        XCTAssertTrue(app.buttons["inboxChange"].firstMatch.waitForExistence(timeout: 8))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["settingsButton"].tapWhenReady()
        app.buttons["rulesLink"].tapWhenReady()
        XCTAssertTrue(app.navigationBars["Regeln"].waitForExistence(timeout: 8))
        let toggle = app.switches["ruleToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), "Die gemerkte Regel steht in der Regelansicht")
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap()
        XCTAssertEqual(app.switches["ruleToggle"].firstMatch.value as? String, "0", "abschaltbar")
    }

    @MainActor
    func testCorrectionFromHistory() {
        let app = launch("inbox")
        app.tabBars.buttons["Verlauf"].tapWhenReady()
        let done = app.buttons["activityRow.Canyon Endurace"].firstMatch
        XCTAssertTrue(app.reveal(done), "abgeschlossene Fahrt mit Canyon")
        done.tap()
        app.buttons["changeGear"].tapWhenReady()
        app.buttons["gearToggle.Canyon Endurace"].tapWhenReady()
        app.buttons["gearToggle.Cube Agree"].tapWhenReady()
        app.buttons["assignConfirm"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["activityGearList"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["activityGearList"].label.contains("Cube Agree"))
        XCTAssertFalse(app.staticTexts["activityGearList"].label.contains("Canyon"))
    }
}
