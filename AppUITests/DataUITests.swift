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
        app.buttons["confirmDeleteGear"].tapWhenReady()
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
        app.buttons["confirmDeleteActivity"].tapWhenReady()
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
        app.buttons["exportConfirm"].tapWhenReady()
        saveInFilesPicker(app)
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 15))

        app.tapRevealed(app.buttons["deleteAllData"])
        app.buttons["confirmDeleteAll"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["onboardingStep"].waitForExistence(timeout: 10), "Nach dem Löschen beginnt das Onboarding")
        app.buttons["onboardingNext"].tapWhenReady()
        app.buttons["onboardingHealthLater"].tapWhenReady()
        app.buttons["onboardingFirstGearLater"].tapWhenReady()
        XCTAssertTrue(app.buttons["addFirstGear"].waitForExistence(timeout: 8), "Bestand ist leer")

        app.buttons["settingsButton"].tapWhenReady()
        app.tapRevealed(app.buttons["importBackup"])
        openFromFilesPicker(app)
        XCTAssertTrue(app.navigationBars["Backup prüfen"].waitForExistence(timeout: 15))
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

    // MARK: Systemdialoge (Dateien)

    /// Sichern-Dialog von `fileExporter`: Ort „Auf meinem iPhone“ und „Sichern“.
    @MainActor
    private func saveInFilesPicker(_ app: XCUIApplication) {
        let save = app.buttons.matching(NSPredicate(format: "label IN %@", ["Sichern", "Save", "Bewegen", "Move"])).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 15), "Sichern-Dialog fehlt")
        let onDevice = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Auf meinem iPhone", "On My iPhone"])).firstMatch
        if onDevice.waitForExistence(timeout: 3), onDevice.isHittable { onDevice.tap() }
        save.tap()
        // Gibt es die Datei schon (früherer Lauf), fragt das System nach „Ersetzen“.
        let replace = app.buttons.matching(NSPredicate(format: "label IN %@", ["Ersetzen", "Replace"])).firstMatch
        if replace.waitForExistence(timeout: 3) { replace.tap() }
    }

    /// Öffnen-Dialog von `fileImporter`: die zuletzt gesicherte Backup-Datei wählen.
    @MainActor
    private func openFromFilesPicker(_ app: XCUIApplication) {
        let file = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Eingelaufen-Backup")).firstMatch
        if !file.waitForExistence(timeout: 10) {
            let browse = app.buttons.matching(NSPredicate(format: "label IN %@", ["Durchsuchen", "Browse"])).firstMatch
            if browse.exists { browse.tap() }
            let onDevice = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Auf meinem iPhone", "On My iPhone"])).firstMatch
            if onDevice.waitForExistence(timeout: 5) { onDevice.tap() }
        }
        XCTAssertTrue(file.waitForExistence(timeout: 10), "Backup-Datei im Öffnen-Dialog fehlt")
        file.tap()
        let open = app.buttons.matching(NSPredicate(format: "label IN %@", ["Öffnen", "Open"])).firstMatch
        if open.waitForExistence(timeout: 2) { open.tap() }
    }
}
