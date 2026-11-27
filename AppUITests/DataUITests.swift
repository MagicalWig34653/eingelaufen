import XCTest

/// M8 Datensicherung und Löschen (SPEC 11, S08): Ende zu Ende über die echten Dateidialoge des Systems.
final class DataUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testDeleteGearFromDetail() {
        let app = launch("basic")
        app.tabBars.buttons["Ausrüstung"].tapWhenReady()
        app.buttons["gear.Tennisschläger"].tapWhenReady()
        app.tapRevealed(app.buttons["detailDelete"])
        app.sheets.firstMatch.buttons["confirmDeleteGear"].firstMatch.tapWhenReady()   // Bestätigungsdialog (Aktionsblatt)
        XCTAssertTrue(app.buttons["gear.Canyon Endurace"].waitForExistence(timeout: 8), "Zurück in der Liste")
        XCTAssertFalse(app.buttons["gear.Tennisschläger"].exists)
        app.tabBars.buttons["Verlauf"].tapWhenReady()
        XCTAssertTrue(app.buttons["activityRow.Ohne Ausrüstung"].waitForExistence(timeout: 8),
                      "Die Aktivität bleibt, nur die Ausrüstung ist weg")
    }

    @MainActor
    func testDeleteActivityFromHistory() {
        let app = launch("basic")
        app.tabBars.buttons["Verlauf"].tapWhenReady()
        app.buttons["activityRow.Laufschuhe Pegasus"].tapWhenReady()
        app.tapRevealed(app.buttons["activityDelete"])
        app.sheets.firstMatch.buttons["confirmDeleteActivity"].firstMatch.tapWhenReady()   // Bestätigungsdialog (Aktionsblatt)
        XCTAssertTrue(app.buttons["activityRow.Tennisschläger"].waitForExistence(timeout: 8), "Zurück im Verlauf")
        XCTAssertFalse(app.buttons["activityRow.Laufschuhe Pegasus"].exists)
        app.tabBars.buttons["Ausrüstung"].tapWhenReady()
        let shoes = app.buttons["gear.Laufschuhe Pegasus"]
        XCTAssertTrue(shoes.waitForExistence(timeout: 8))
        XCTAssertTrue(shoes.label.contains("Noch nicht verwendet"), "Nutzung neu berechnet: \(shoes.label)")
    }

    /// Export mit Hinweis → Datei im System sichern → alle Daten löschen (Onboarding) → Datei importieren → Vorschau → Ersetzen.
    @MainActor
    func testExportDeleteAllAndRestoreFromFile() {
        let app = launch("basic")
        app.buttons["settingsButton"].tapWhenReady()
        app.tapRevealed(app.buttons["exportBackup"])
        XCTAssertTrue(app.element(labelContaining: "nicht verschlüsselt").waitForExistence(timeout: 5), "Hinweis auf unverschlüsselte Weitergabe")
        app.sheets.firstMatch.buttons["exportConfirm"].firstMatch.tapWhenReady()   // Bestätigungsdialog (Aktionsblatt)
        saveInFilesPicker(app)
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 15))

        app.tapRevealed(app.buttons["deleteAllData"])
        app.sheets.firstMatch.buttons["confirmDeleteAll"].firstMatch.tapWhenReady()   // Bestätigungsdialog (Aktionsblatt)
        XCTAssertTrue(app.staticTexts["onboardingStep"].waitForExistence(timeout: 10), "Nach dem Löschen beginnt das Onboarding")
        app.buttons["onboardingNext"].tapWhenReady()
        app.buttons["onboardingHealthLater"].tapWhenReady()
        app.buttons["onboardingFirstGearLater"].tapWhenReady()
        XCTAssertTrue(app.buttons["addFirstGear"].waitForExistence(timeout: 8), "Bestand ist leer")

        app.buttons["settingsButton"].tapWhenReady()
        app.tapRevealed(app.buttons["importBackup"])
        openFromFilesPicker(app)
        let previewShown = app.navigationBars["Vorschau"].waitForExistence(timeout: 15)
        if !previewShown { shot(app, "m8-import-fehlt") }
        XCTAssertTrue(previewShown, "Vorschau nach der Dateiauswahl")
        let gearRow = app.element(id: "previewCount.gear")
        XCTAssertTrue(gearRow.waitForExistence(timeout: 5))
        XCTAssertTrue(gearRow.label.contains("5"), "Vorschau zählt 5 Ausrüstungsteile: \(gearRow.label)")
        shot(app, "m8-vorschau")
        app.buttons["restoreConfirm"].tapWhenReady()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 10))
        app.buttons["settingsDone"].tapWhenReady()
        app.tabBars.buttons["Ausrüstung"].tapWhenReady()
        XCTAssertTrue(app.buttons["gear.Canyon Endurace"].waitForExistence(timeout: 8), "Wiederhergestellt")
        XCTAssertTrue(app.buttons["gear.Tennisschläger"].exists)
    }
}
