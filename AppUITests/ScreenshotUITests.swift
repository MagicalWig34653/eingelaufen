import XCTest

/// Erzeugt Screenshots der Kernscreens in hell, dunkel und XXL (PLAN M2). Prüft nebenbei, dass nichts abgeschnitten
/// unerreichbar ist: Primäraktionen bleiben bei XXL erreichbar. Dateien nur mit TEST_RUNNER_SCREENSHOT_DIR.
final class ScreenshotUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testCoreScreens() {
        do {
            // Darstellung stellt der Aufrufer systemweit per `simctl ui` ein (hell, dunkel, XXL); der Name kommt aus SCREENSHOT_TAG.
            let tag = ProcessInfo.processInfo.environment["SCREENSHOT_TAG"] ?? "light"

            var app = launch("fresh")
            XCTAssertTrue(app.buttons["onboardingNext"].waitForExistence(timeout: 8))
            shot(app, "\(tag)-1-onboarding-sportarten")
            app.buttons["onboardingNext"].tap()
            shot(app, "\(tag)-2-onboarding-health")
            XCTAssertTrue(app.buttons["onboardingHealthLater"].isHittable)
            app.terminate()

            app = launch("empty")
            XCTAssertTrue(app.buttons["addFirstGear"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["addFirstGear"].isHittable)
            shot(app, "\(tag)-3-uebersicht-leer")
            app.terminate()

            app = launch("basic")
            XCTAssertTrue(app.tabBars.buttons["Ausrüstung"].waitForExistence(timeout: 8))
            shot(app, "\(tag)-4-uebersicht")
            app.tabBars.buttons["Ausrüstung"].tap()
            XCTAssertTrue(app.buttons["gear.Canyon Endurace"].waitForExistence(timeout: 8))
            shot(app, "\(tag)-5-ausruestung")
            app.buttons["gear.Canyon Endurace"].tap()
            XCTAssertTrue(app.buttons["detailName"].exists || app.staticTexts["detailName"].waitForExistence(timeout: 8))
            shot(app, "\(tag)-6-detail")
            XCTAssertTrue(app.reveal(app.buttons["detailAddActivity"]))
            app.buttons["detailAddActivity"].tap()
            XCTAssertTrue(app.buttons["activitySave"].waitForExistence(timeout: 8))
            shot(app, "\(tag)-7-aktivitaet-eintragen")
            app.buttons["activityCancel"].tap()
            app.navigationBars.buttons.firstMatch.tap()
            app.tabBars.buttons["Verlauf"].tap()
            XCTAssertTrue(app.buttons["historyAddButton"].waitForExistence(timeout: 8))
            shot(app, "\(tag)-8-verlauf")
            app.buttons["historyAddButton"].tap()
            XCTAssertTrue(app.buttons["activityCancel"].waitForExistence(timeout: 8))
            app.buttons["activityCancel"].tap()
            app.tabBars.buttons["Ausrüstung"].tap()
            app.buttons["gearAddButton"].tapWhenReady()
            XCTAssertTrue(app.buttons["category.cycling"].waitForExistence(timeout: 8))
            shot(app, "\(tag)-9-vorlage-kategorie")
            app.buttons["category.cycling"].tap()
            shot(app, "\(tag)-10-vorlage-liste")
            app.terminate()
        }
    }
}
