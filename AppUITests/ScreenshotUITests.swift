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

    /// M3: Onboarding-Schritt 2, importierter Verlauf, Import-Status (abgeglichen, nichts sichtbar, ausstehend).
    @MainActor
    func testHealthScreens() {
        let tag = ProcessInfo.processInfo.environment["SCREENSHOT_TAG"] ?? "light"
        var app = launch("fresh", health: "workouts")
        app.buttons["onboardingNext"].tapWhenReady()
        XCTAssertTrue(app.buttons["onboardingHealthConnect"].waitForExistence(timeout: 8))
        shot(app, "\(tag)-m3-1-onboarding-health")
        app.buttons["onboardingHealthConnect"].tap()
        app.buttons["onboardingFirstGearLater"].tapWhenReady()
        app.tabBars.buttons["Verlauf"].tapWhenReady()
        XCTAssertTrue(app.element(labelContaining: "42,3 km").waitForExistence(timeout: 10))
        shot(app, "\(tag)-m3-2-verlauf-importiert")
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.element(labelContaining: "Abgeglichen").waitForExistence(timeout: 10))
        shot(app, "\(tag)-m3-3-einstellungen-abgeglichen")
        app.terminate()

        for (scenario, status, name) in [("empty", "Keine Trainings sichtbar", "4-einstellungen-nichts-sichtbar"),
                                         ("locked", "Import ausstehend", "5-einstellungen-ausstehend")] {
            app = launch("empty", health: scenario)
            app.buttons["settingsButton"].tapWhenReady()
            if scenario == "empty" { shot(app, "\(tag)-m3-6-einstellungen-nicht-verbunden") }
            app.tapRevealed(app.buttons["healthConnect"])
            XCTAssertTrue(app.element(labelContaining: status).waitForExistence(timeout: 10))
            shot(app, "\(tag)-m3-\(name)")
            app.terminate()
        }
    }

    /// M5: Komponenten, Wartung, Regel-/Messwert-Status, Hinweise (hell/dunkel stellt der Aufrufer ein).
    @MainActor
    func testNestedScreens() {
        let tag = ProcessInfo.processInfo.environment["SCREENSHOT_TAG"] ?? "light"
        let app = launch("nested")
        app.tabBars.buttons["Ausrüstung"].tapWhenReady()
        app.buttons["gear.Canyon Endurace"].tapWhenReady()
        XCTAssertTrue(app.buttons["component.Laufrad"].waitForExistence(timeout: 8))
        app.tapRevealed(app.buttons["component.Laufrad"])
        app.tapRevealed(app.buttons["component.Reifen"])
        XCTAssertTrue(app.element(id: "installedIn").waitForExistence(timeout: 8))
        XCTAssertTrue(app.element(id: "installedIn").label.contains("Canyon Endurace › Laufrad"))
        shot(app, "\(tag)-m5-6-verschachtelt-pfad")
    }

    @MainActor
    func testMaintenanceScreens() {
        let tag = ProcessInfo.processInfo.environment["SCREENSHOT_TAG"] ?? "light"
        let app = launch("maintenance")
        XCTAssertTrue(app.element(id: "hint.Kette").waitForExistence(timeout: 10))
        shot(app, "\(tag)-m5-1-uebersicht-hinweis")
        app.tabBars.buttons["Ausrüstung"].tapWhenReady()
        app.buttons["gear.Canyon Endurace"].tapWhenReady()
        XCTAssertTrue(app.buttons["component.Kette"].waitForExistence(timeout: 8))
        shot(app, "\(tag)-m5-2-detail-komponenten-wartung")
        app.tapRevealed(app.buttons["component.Kette"])
        XCTAssertTrue(app.staticTexts["detailName"].waitForExistence(timeout: 8))
        shot(app, "\(tag)-m5-3-komponente-kopf")
        app.swipeUp()
        shot(app, "\(tag)-m5-4-komponente-wartung-status")
        app.swipeDown(); app.swipeDown()
        app.buttons["componentReplace.Kette"].tapWhenReady()
        XCTAssertTrue(app.textFields["replaceName"].waitForExistence(timeout: 8))
        shot(app, "\(tag)-m5-5-ersetzen")
    }

    /// M4: Übersicht mit offener Zuordnung, Posteingang, Auswahl-Dialog, Verlauf, Regeln und Sets (hell/dunkel stellt der Aufrufer ein).
    @MainActor
    func testInboxScreens() {
        let tag = ProcessInfo.processInfo.environment["SCREENSHOT_TAG"] ?? "light"
        let app = launch("inbox")
        let link = app.buttons["inboxLink"]
        XCTAssertTrue(app.reveal(link))
        shot(app, "\(tag)-m4-1-uebersicht-offen")
        link.tap()
        XCTAssertTrue(app.buttons["inboxConfirm"].waitForExistence(timeout: 8))
        shot(app, "\(tag)-m4-2-posteingang")
        app.buttons["inboxChange"].firstMatch.tap()
        XCTAssertTrue(app.buttons["presetOffer.Rennrad komplett"].waitForExistence(timeout: 8))
        app.buttons["presetOffer.Rennrad komplett"].tap()
        shot(app, "\(tag)-m4-3-auswahl-set")
        app.buttons["assignCancel"].tap()
        app.switches["inboxRemember"].firstMatch.flip()
        app.buttons["inboxConfirm"].firstMatch.tap()
        XCTAssertTrue(app.buttons["inboxChange"].firstMatch.waitForExistence(timeout: 8))
        shot(app, "\(tag)-m4-4-posteingang-eine-offen")
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["Verlauf"].tapWhenReady()
        XCTAssertTrue(app.element(id: "historyList").waitForExistence(timeout: 8))
        shot(app, "\(tag)-m4-5-verlauf")
        app.buttons["settingsButton"].tapWhenReady()
        app.buttons["rulesLink"].tapWhenReady()
        XCTAssertTrue(app.switches["ruleToggle"].firstMatch.waitForExistence(timeout: 8))
        shot(app, "\(tag)-m4-6-regeln")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["presetsLink"].tapWhenReady()
        XCTAssertTrue(app.element(labelContaining: "Rennrad komplett").waitForExistence(timeout: 8))
        shot(app, "\(tag)-m4-7-sets")
    }
}
