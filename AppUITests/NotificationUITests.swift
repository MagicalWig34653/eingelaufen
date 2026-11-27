import XCTest

/// M6 (PLAN, SPEC 7.2, 14.2 „Notification-Kategorien, Actions“): Fixture „inboxOne“: Canyon Endurace und Cube Agree,
/// eine erledigte Fahrt auf dem Canyon (Tag 2) und genau eine offene Fahrt (Tag 8) mit Vorschlag Canyon.
final class NotificationUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func launchWithNotifications(delay: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-EingelaufenInMemory", "-UITestFixture", "inboxOne", "-UITestNotifications",
                               "-UITestNotificationDelay", "\(delay)", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        return app
    }

    /// Ende zu Ende: echte lokale Mitteilung auf dem Home-Bildschirm, Aktion „Vorschlag übernehmen“ (läuft im Hintergrund,
    /// ohne die App zu öffnen), danach in der App: nichts mehr offen, die Fahrt trägt den Canyon.
    @MainActor
    func testConfirmActionOnTheHomeScreenBooksTheProposal() {
        let app = launchWithNotifications(delay: 8)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(app.reveal(app.buttons["inboxLink"]), "vorher: eine offene Zuordnung")
        XCUIDevice.shared.press(.home)
        // Systemdialog erscheint nur, solange der Simulator noch nicht gefragt hat (kontextbezogen: es gibt eine offene Zuordnung).
        guard let banner = waitForBanner(containing: "Ausrüstung bestätigen", on: springboard) else {
            return XCTFail("Mitteilung erscheint auf dem Home-Bildschirm")
        }
        XCTAssertTrue(banner.label.contains("Canyon Endurace"), "Vorschlag steht in der Mitteilung: \(banner.label)")
        banner.press(forDuration: 1.5)
        let confirm = springboard.buttons["Vorschlag übernehmen"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8), "erste Aktion ist „Vorschlag übernehmen“")
        XCTAssertTrue(springboard.buttons["Andere auswählen"].exists, "zweite Aktion ist „Andere auswählen“")
        confirm.tap()

        app.activate()
        XCTAssertTrue(app.tabBars.buttons["Verlauf"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["inboxLink"].waitForExistence(timeout: 4), "nichts mehr offen")
        app.tabBars.buttons["Verlauf"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "activityRow.Canyon Endurace").element(boundBy: 1).waitForExistence(timeout: 8),
                      "beide Fahrten tragen den Canyon")
        XCTAssertFalse(app.buttons["activityRow.Zuordnung offen"].exists)
    }

    /// Ohne Erlaubnis (stille Mitteilungszentrale wie „nicht erlaubt“) bleibt alles bedienbar; Einstellungen erklären es.
    @MainActor
    func testWithoutPermissionTheAppStaysFullyUsable() {
        let app = launch("inboxOne")
        app.buttons["settingsButton"].tapWhenReady()
        let status = app.first(id: "notificationStatus")
        XCTAssertTrue(app.reveal(status), "Status der Erlaubnis steht in den Einstellungen")
        XCTAssertTrue(status.label.contains("iOS-Einstellungen aus"), status.label)
        let toggle = app.switches["quietHoursToggle"]
        XCTAssertTrue(app.reveal(toggle))
        toggle.flip()
        XCTAssertTrue(app.first(id: "quietHoursStart").waitForExistence(timeout: 8), "Ruhezeit lässt sich einstellen")
        app.buttons["settingsDone"].tap()

        let link = app.buttons["inboxLink"]
        XCTAssertTrue(app.reveal(link))
        link.tap()
        app.buttons["inboxConfirm"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.element(id: "inboxEmpty").waitForExistence(timeout: 8), "Posteingang funktioniert ohne Mitteilungen")
    }
}
