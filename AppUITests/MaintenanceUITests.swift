import XCTest

/// M5 (PLAN, SPEC 13/14.3): Wartung in höchstens drei Aktionen ab Detail, Komponente tauschen und alte Historie aufrufen
/// (T-02 im UI), Starter-Vorlagen, Hinweise auf der Übersicht.
final class MaintenanceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func openBikeDetail(_ app: XCUIApplication) {
        app.tabBars.buttons["Ausrüstung"].tapWhenReady()
        app.buttons["gear.Canyon Endurace"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["detailName"].waitForExistence(timeout: 8))
    }

    /// Spec 13: „bestehendes Teil öffnen und einfache Wartung in höchstens drei Nutzeraktionen speichern (ausgehend vom Detailbildschirm)“.
    @MainActor
    func testQuickMaintenanceNeedsOneActionFromDetail() {
        let app = launch("maintenance")
        openBikeDetail(app)
        var actions = 0
        app.buttons["quick.lubricated"].tapWhenReady(); actions += 1
        XCTAssertTrue(app.reveal(app.staticTexts["maintenanceEvent.lubricated"]), "Ereignis steht sofort in der Wartungsliste")
        XCTAssertTrue(app.staticTexts["maintenanceEvent.lubricated"].label.contains("Geschmiert"))
        XCTAssertLessThanOrEqual(actions, 3)
    }

    @MainActor
    func testMeasurementNeedsThreeActionsAtMost() {
        let app = launch("maintenance")
        openBikeDetail(app)
        var actions = 0
        app.buttons["quick.wearMeasured"].tapWhenReady(); actions += 1
        let value = app.textFields["maintenanceMeasurement"]
        value.tapWhenReady(); actions += 1
        value.typeText("0,4")
        app.buttons["keyboardDone"].tapWhenReady()
        app.buttons["maintenanceSave"].tapWhenReady(); actions += 1
        let row = app.staticTexts["maintenanceEvent.wearMeasured"]
        XCTAssertTrue(app.reveal(row))
        XCTAssertTrue(row.label.contains("0,4"), row.label)
        XCTAssertLessThanOrEqual(actions, 3)
    }

    @MainActor
    func testCustomMaintenanceNeedsADescription() {
        let app = launch("maintenance")
        openBikeDetail(app)
        app.buttons["quick.custom"].tapWhenReady()
        XCTAssertTrue(app.buttons["maintenanceSave"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["maintenanceSave"].isEnabled, "Frei definierte Wartung braucht eine Bezeichnung")
    }

    @MainActor
    func testAllSevenQuickActionsAreOffered() {
        let app = launch("maintenance")
        openBikeDetail(app)
        for key in ["cleaned", "lubricated", "inspected", "wearMeasured", "partChange", "repaired", "custom"] {
            XCTAssertTrue(app.buttons["quick.\(key)"].waitForExistence(timeout: 5), "Schnellaktion \(key)")
        }
    }

    /// SPEC 14.3 „Komponente tauschen, alte Historie weiterhin aufrufen“ und T-02: die alte Kette behält ihre 4 Nutzungen und 147,3 km,
    /// die neue beginnt ohne Daten.
    @MainActor
    func testReplaceChainKeepsOldHistoryAndStartsNewChainEmpty() {
        let app = launch("maintenance")
        openBikeDetail(app)
        XCTAssertTrue(app.buttons["component.Kette"].waitForExistence(timeout: 8))
        app.tapRevealed(app.buttons["component.Kette"])
        XCTAssertTrue(app.buttons["componentReplace.Kette"].waitForExistence(timeout: 8), "Ersetzen an der Seite der Komponente")
        app.buttons["componentReplace.Kette"].tap()
        let name = app.textFields["replaceName"]
        name.tapWhenReady()
        let current = (name.value as? String) ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        name.typeText("Kette neu")
        app.buttons["keyboardDone"].tapWhenReady()
        app.buttons["replaceConfirm"].tapWhenReady()

        // Die alte Kette bleibt aufrufbar: ihre Seite zeigt Nutzung und Status, nichts ist zurückgesetzt (T-02).
        XCTAssertTrue(app.staticTexts["detailName"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["detailName"].label, "Kette")
        XCTAssertTrue(app.element(id: "usageUses").label.hasSuffix("4"), "Nutzung bleibt: \(app.element(id: "usageUses").label)")
        XCTAssertTrue(app.element(id: "usageDistance").label.contains("147,3 km"), app.element(id: "usageDistance").label)
        XCTAssertTrue(app.element(id: "detailStatus").label.hasSuffix("Eingelagert"), app.element(id: "detailStatus").label)
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(app.buttons["component.Kette neu"].waitForExistence(timeout: 8), "Neue Kette ist montiert")
        XCTAssertFalse(app.buttons["component.Kette"].exists, "Die alte Kette ist nicht mehr unter den aktuellen Komponenten")
        let old = app.buttons["previousComponent.Kette"]
        XCTAssertTrue(app.reveal(old), "Alte Komponente bleibt unter „Frühere Komponenten“ aufrufbar")
        old.tap()
        XCTAssertTrue(app.staticTexts["detailName"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["detailName"].label, "Kette", "Die alte Komponente öffnet ihre eigene Historie")
        app.navigationBars.buttons.firstMatch.tap()

        app.swipeDown(); app.swipeDown()   // nach dem Zurück steht die Liste weiter unten
        app.tapRevealed(app.buttons["component.Kette neu"])
        XCTAssertTrue(app.element(id: "usageUses").waitForExistence(timeout: 8))
        XCTAssertTrue(app.element(id: "usageUses").label.hasSuffix("0"), "Neue Kette startet bei 0 Nutzungen: \(app.element(id: "usageUses").label)")
        XCTAssertTrue(app.element(id: "usageDistance").label.contains("Keine Daten"), "Keine erfundene 0 km: \(app.element(id: "usageDistance").label)")
    }

    @MainActor
    func testAddComponentFromStarterTemplate() {
        let app = launch("basic")
        openBikeDetail(app)
        app.tapRevealed(app.buttons["componentAdd"])
        app.buttons["componentTemplate.chain"].tapWhenReady()
        XCTAssertEqual(app.textFields["componentName"].value as? String, "Kette", "Die Vorlage schlägt den Namen vor")
        app.buttons["componentSave"].tapWhenReady()
        XCTAssertTrue(app.buttons["component.Kette"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testMountedComponentIsHiddenFromTheGearListAndNamesItsParent() {
        let app = launch("maintenance")
        app.tabBars.buttons["Ausrüstung"].tapWhenReady()
        XCTAssertTrue(app.buttons["gear.Canyon Endurace"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["gear.Kette"].exists, "Keine Komponentenstruktur in der Liste (SPEC S03)")
        app.buttons["gear.Canyon Endurace"].tap()
        app.tapRevealed(app.buttons["component.Kette"])
        XCTAssertTrue(app.element(id: "installedIn").waitForExistence(timeout: 8))
        XCTAssertTrue(app.element(id: "installedIn").label.contains("Canyon Endurace"))
    }

    @MainActor
    func testRuleStatusesAreSeparatedAndForecastIsAbsentWithoutEnoughData() {
        let app = launch("maintenance")
        openBikeDetail(app)
        app.tapRevealed(app.buttons["component.Kette"])
        let interval = app.buttons["ruleStatus.lubricated"]
        XCTAssertTrue(app.reveal(interval))
        XCTAssertTrue(interval.label.contains("105 km"), interval.label)
        XCTAssertTrue(interval.label.contains("Prüfen"), interval.label)
        let measurement = app.staticTexts["measurementStatus"]
        XCTAssertTrue(app.reveal(measurement))
        XCTAssertTrue(measurement.label.contains("0,3"), measurement.label)
        XCTAssertFalse(app.staticTexts["forecastStatus"].exists, "Prognose nur mit ausreichend Daten (SPEC 8.2)")
    }

    @MainActor
    func testOverviewShowsAtMostThreeHints() {
        let app = launch("maintenance")
        XCTAssertTrue(app.element(id: "hint.Kette").waitForExistence(timeout: 8))
        XCTAssertTrue(app.element(id: "hint.Kette").label.contains("Prüfen"))
        let hints = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'hint.'"))
        XCTAssertLessThanOrEqual(hints.count, 3)
    }

    @MainActor
    func testCanAddARuleFromTheDetail() {
        let app = launch("maintenance")
        openBikeDetail(app)
        app.tapRevealed(app.buttons["ruleAdd"])
        let interval = app.textFields["ruleInterval"]
        interval.tapWhenReady()
        interval.typeText("200")
        app.buttons["keyboardDone"].tapWhenReady()
        app.buttons["ruleSave"].tapWhenReady()
        XCTAssertTrue(app.element(id: "ruleStatus.cleaned").waitForExistence(timeout: 8), "Neue Regel (Standard: Gereinigt, Distanz) erscheint mit Status")
    }
}





