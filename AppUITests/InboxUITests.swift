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
        XCTAssertTrue(app.navigationBars["Ausrüstung"].waitForExistence(timeout: 8))
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
        remember.flip()
        XCTAssertEqual(remember.value as? String, "1", "„Merken“ ist eingeschaltet")
        app.buttons["inboxConfirm"].firstMatch.tap()
        XCTAssertTrue(app.buttons["inboxChange"].firstMatch.waitForExistence(timeout: 8))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["settingsButton"].tapWhenReady()
        app.buttons["rulesLink"].tapWhenReady()
        XCTAssertTrue(app.navigationBars["Regeln"].waitForExistence(timeout: 8))
        let toggle = app.switches["ruleToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), "Die gemerkte Regel steht in der Regelansicht")
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.flip()
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
        app.switches["gearToggle.Canyon Endurace"].flip()
        app.switches["gearToggle.Cube Agree"].flip()
        app.buttons["assignConfirm"].tapWhenReady()
        let list = app.staticTexts["activityGearList"]
        // Das Blatt schließt, während die Anzeige noch den alten Stand trägt: auf den neuen warten.
        expectation(for: NSPredicate(format: "label CONTAINS 'Cube Agree'"), evaluatedWith: list)
        waitForExpectations(timeout: 8)
        XCTAssertFalse(app.staticTexts["activityGearList"].label.contains("Canyon"))
    }

    @MainActor
    func testCreatePresetAndMakeItTheDefault() {
        let app = launch("inbox")
        app.buttons["settingsButton"].tapWhenReady()
        app.buttons["presetsLink"].tapWhenReady()
        XCTAssertTrue(app.buttons["preset.Rennrad komplett"].waitForExistence(timeout: 8) || app.staticTexts["Rennrad komplett"].exists)
        app.buttons["presetAdd"].tapWhenReady()
        let name = app.textFields["presetName"]
        name.tapWhenReady()
        name.typeText("Pendeln")
        app.switches["presetMember.Cube Agree"].flip()
        app.buttons["presetSave"].tapWhenReady()
        XCTAssertTrue(app.element(labelContaining: "Pendeln").waitForExistence(timeout: 8), "Das neue Set steht in der Liste")
        // Standard-Set je Sportart (Radsport ist im Fixture eingerichtet).
        let picker = app.buttons["defaultPreset.cycling"]
        XCTAssertTrue(app.reveal(picker))
        picker.tap()
        app.buttons["Pendeln"].tapWhenReady()
        XCTAssertTrue(app.buttons["defaultPreset.cycling"].label.contains("Pendeln"), app.buttons["defaultPreset.cycling"].label)
    }
}
