import XCTest

/// Erste UI-Tests (PLAN M2, SPEC 14.3): Onboarding, drei Tabs, Ausrüstung mit Vorlage anlegen und archivieren,
/// manuelle Aktivität ohne HealthKit.
final class FlowUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testOnboardingWithoutHealthEndsOnOverviewWithEmptyState() {
        let app = launch("fresh")
        XCTAssertTrue(app.staticTexts["onboardingStep"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["onboardingStep"].label, "Schritt 1 von 3")
        app.buttons["sport.cycling"].tapWhenReady()
        app.buttons["sport.running"].tapWhenReady()
        app.buttons["onboardingNext"].tapWhenReady()
        XCTAssertEqual(app.staticTexts["onboardingStep"].label, "Schritt 2 von 3")
        app.buttons["onboardingHealthLater"].tapWhenReady()
        XCTAssertEqual(app.staticTexts["onboardingStep"].label, "Schritt 3 von 3")
        app.buttons["onboardingFirstGearLater"].tapWhenReady()
        // Leerer Zustand: nur der Einstieg, keine Statistik, keine Warnung (SPEC 1.3).
        XCTAssertTrue(app.buttons["addFirstGear"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Status"].exists)
    }

    @MainActor
    func testOnboardingWithFirstGearFromTemplate() {
        let app = launch("fresh")
        app.buttons["onboardingNext"].tapWhenReady()
        app.buttons["onboardingHealthLater"].tapWhenReady()
        app.buttons["onboardingChooseTemplate"].tapWhenReady()
        app.buttons["category.running"].tapWhenReady()
        app.buttons["template.running.shoes"].tapWhenReady()
        app.buttons["gearSave"].tapWhenReady()
        app.buttons["onboardingDone"].tapWhenReady()
        app.tabBars.buttons["Ausrüstung"].tapWhenReady()
        XCTAssertTrue(app.buttons["gear.Laufschuhe"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testThreeTabsAndSettingsAreReachable() {
        let app = launch("empty")
        let tabs = app.tabBars.buttons
        XCTAssertEqual(tabs.count, 3)
        for title in ["Übersicht", "Ausrüstung", "Verlauf"] {
            tabs[title].tapWhenReady()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "Titel \(title)")
            XCTAssertTrue(app.buttons["settingsButton"].exists, "Einstellungen oben rechts auf \(title)")
        }
        app.buttons["settingsButton"].tapWhenReady()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))
        app.buttons["settingsDone"].tapWhenReady()
        XCTAssertTrue(app.navigationBars["Verlauf"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCreateGearFromTemplateInThreeTaps() {
        let app = launch("empty")
        app.buttons["addFirstGear"].tapWhenReady()
        app.buttons["category.cycling"].tapWhenReady()
        app.buttons["template.cycling.road-bike"].tapWhenReady()
        let name = app.textFields["gearNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Rennrad", "Die Vorlage schlägt den Namen vor")
        app.buttons["gearSave"].tapWhenReady()
        app.tabBars.buttons["Ausrüstung"].tapWhenReady()
        let row = app.buttons["gear.Rennrad"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertTrue(row.label.contains("Noch nicht verwendet"), "Neue Ausrüstung zeigt keine erfundene 0: \(row.label)")
    }

    @MainActor
    func testFreeGearNeedsAName() {
        let app = launch("empty")
        app.buttons["addFirstGear"].tapWhenReady()
        app.buttons["category.fitness"].tapWhenReady()
        app.buttons["template.free"].tapWhenReady()
        XCTAssertFalse(app.buttons["gearSave"].isEnabled, "Ohne Namen kein Speichern")
        let name = app.textFields["gearNameField"]
        name.tapWhenReady()
        name.typeText("Kettlebell")
        XCTAssertTrue(app.buttons["gearSave"].isEnabled)
    }

    @MainActor
    func testArchiveHidesGearAndKeepsItInTheArchiveFilter() {
        let app = launch("basic")
        app.tabBars.buttons["Ausrüstung"].tapWhenReady()
        XCTAssertTrue(app.buttons["gear.Laufschuhe Pegasus"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["gear.Alte Laufschuhe"].exists, "Archiviertes ist standardmäßig ausgeblendet")
        app.buttons["gear.Laufschuhe Pegasus"].tap()
        app.buttons["detailArchive"].tapWhenReady()
        app.sheets.firstMatch.buttons["Archivieren"].tapWhenReady()   // Bestätigungsdialog (Aktionsblatt)
        XCTAssertTrue(app.navigationBars["Ausrüstung"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["gear.Laufschuhe Pegasus"].exists)
        app.buttons["gearFilter"].tapWhenReady()
        app.buttons["toggleArchived"].tapWhenReady()
        XCTAssertTrue(app.buttons["gear.Laufschuhe Pegasus"].waitForExistence(timeout: 8), "Archivieren löscht nicht")
        XCTAssertTrue(app.buttons["gear.Alte Laufschuhe"].exists)
        app.buttons["gear.Laufschuhe Pegasus"].tap()
        XCTAssertTrue(app.element(id: "detailStatus").label.hasSuffix("Archiviert"), app.element(id: "detailStatus").label)
        XCTAssertTrue(app.element(labelContaining: "7,5 km").exists, "Verlauf bleibt nach dem Archivieren erhalten")
    }

    @MainActor
    func testManualActivityWorksWithoutHealthAndShowsInHistoryAndGear() {
        let app = launch("basic")
        app.tabBars.buttons["Verlauf"].tapWhenReady()
        app.buttons["historyAddButton"].tapWhenReady()
        // Der Schalter sitzt rechts in der Zeile; ein Tipp in die Mitte trifft nur die Beschriftung.
        for name in ["Canyon Endurace", "Radschuhe"] {
            let toggle = app.switches["pick.\(name)"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            XCTAssertEqual("\(toggle.value ?? "nil")", "1", "\(name) muss gewählt sein")
        }
        let minutes = app.textFields["activityMinutes"]
        minutes.tapWhenReady()
        minutes.typeText("45")
        let distance = app.textFields["activityDistance"]
        distance.tapWhenReady()
        distance.typeText("12,5")
        app.buttons["keyboardDone"].tapWhenReady()
        app.buttons["activitySave"].tapWhenReady()
        // Verlauf: neue Aktivität mit beiden Ausrüstungsteilen.
        let entry = app.element(labelContaining: "45 min · 12,5 km")
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        // Ausrüstungsdetail: 2 Nutzungen (vorher 2 Fahrten mit dem Rad: 42,3 + ohne Distanz → unvollständig), jetzt 3.
        app.tabBars.buttons["Ausrüstung"].tapWhenReady()
        app.buttons["gear.Canyon Endurace"].tapWhenReady()
        XCTAssertTrue(app.element(id: "usageUses").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(id: "usageUses").label.hasSuffix("3"), "3 Nutzungen: \(app.element(id: "usageUses").label)")
        XCTAssertTrue(app.element(id: "usageDistance").label.contains("54,8 km (unvollständig)"), "Eine Fahrt ohne Distanz macht die Summe unvollständig: \(app.element(id: "usageDistance").label)")
    }

    @MainActor
    func testManualActivityWithoutDurationCannotBeSaved() {
        let app = launch("empty")
        app.buttons["addMenu"].tapWhenReady()
        app.buttons["menuAddActivity"].tapWhenReady()
        XCTAssertTrue(app.buttons["activitySave"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["activitySave"].isEnabled)
    }

    @MainActor
    func testRenameGear() {
        let app = launch("basic")
        app.tabBars.buttons["Ausrüstung"].tapWhenReady()
        app.buttons["gear.Radschuhe"].tapWhenReady()
        app.buttons["detailRename"].tapWhenReady()
        let alert = app.alerts["Umbenennen"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        field.tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        field.typeText("Gravel-Schuhe")
        alert.buttons["Speichern"].tap()
        XCTAssertTrue(app.staticTexts["detailName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detailName"].label, "Gravel-Schuhe")
    }
}
