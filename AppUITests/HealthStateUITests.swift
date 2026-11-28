import XCTest

/// Zustandsanzeigen rund um Apple Health: jede erscheint **und verschwindet wieder**, auch bei Fehler und „nichts
/// Neues“. Bildfolge vorher/während/nachher mit `TEST_RUNNER_SCREENSHOT_DIR` und `TEST_RUNNER_SCREENSHOT_TAG`.
final class HealthStateUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private var tag: String { ProcessInfo.processInfo.environment["SCREENSHOT_TAG"] ?? "light" }

    @MainActor
    private func settings(_ health: String) -> XCUIApplication {
        let app = launch("empty", health: health)
        app.buttons["settingsButton"].tapWhenReady()
        XCTAssertTrue(app.buttons["healthConnect"].waitForExistence(timeout: 8))
        return app
    }

    @MainActor
    private func appears(_ app: XCUIApplication, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.element(labelContaining: text).waitForExistence(timeout: 15), "fehlt: \(text)", file: file, line: line)
    }

    @MainActor
    private func disappears(_ app: XCUIApplication, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.element(labelContaining: text).waitForNonExistence(timeout: 15), "bleibt stehen: \(text)",
                      file: file, line: line)
    }

    @MainActor
    private func becomesEnabled(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 20), .completed, "bleibt gesperrt", file: file, line: line)
    }

    @MainActor
    func testPendingImportAppearsAndDisappears() {
        let app = settings("locked")
        shot(app, "\(tag)-ausstehend-1-vorher")
        app.tapRevealed(app.buttons["healthConnect"])
        appears(app, "Import ausstehend")
        appears(app, "Das Gerät war gesperrt")
        shot(app, "\(tag)-ausstehend-2-waehrend")
        app.tapRevealed(app.buttons["healthSync"])
        appears(app, "Abgeglichen")
        disappears(app, "Import ausstehend")
        disappears(app, "Das Gerät war gesperrt")
        shot(app, "\(tag)-ausstehend-3-nachher")
    }

    @MainActor
    func testFailureDisappearsAfterASyncWithNothingNew() {
        let app = settings("error")
        shot(app, "\(tag)-fehler-1-vorher")
        app.tapRevealed(app.buttons["healthConnect"])
        appears(app, "Abgleich fehlgeschlagen")
        appears(app, "Health hat nicht geantwortet")
        shot(app, "\(tag)-fehler-2-waehrend")
        app.tapRevealed(app.buttons["healthSync"])
        appears(app, "Keine Trainings sichtbar")
        disappears(app, "Abgleich fehlgeschlagen")
        disappears(app, "Health hat nicht geantwortet")
        shot(app, "\(tag)-fehler-3-nachher")
    }

    @MainActor
    func testNothingVisibleDisappearsWhenWorkoutsArrive() {
        let app = settings("later")
        shot(app, "\(tag)-leer-1-vorher")
        app.tapRevealed(app.buttons["healthConnect"])
        appears(app, "Keine Trainings sichtbar")
        appears(app, "Prüfe in der Health-App")
        shot(app, "\(tag)-leer-2-waehrend")
        app.tapRevealed(app.buttons["healthSync"])
        appears(app, "Abgeglichen")
        disappears(app, "Keine Trainings sichtbar")
        disappears(app, "Prüfe in der Health-App")
        shot(app, "\(tag)-leer-3-nachher")
    }

    /// Ursache der früheren Instabilität (Lauf 27.11. 20:45, Last durch parallele Läufe): Die Fake-Quelle hielt den Abgleich
    /// nur 6 s fest, der Test las „gesperrt“ irgendwann danach; eine einzige XCUI-Abfrage dauerte unter Last ~7 s, das
    /// Fenster war dann vorbei. Jetzt endet der Abgleich erst, wenn der Test ihn freigibt (`releaseHealthSync`).
    @MainActor
    func testBusyAndWaitingOnlyWhileSyncing() {
        let app = settings("slow")
        shot(app, "\(tag)-laden-1-vorher")
        app.tapRevealed(app.buttons["healthConnect"])
        let sync = app.buttons["healthSync"]
        XCTAssertTrue(sync.waitForExistence(timeout: 20))
        XCTAssertFalse(sync.isEnabled, "während des Abgleichs gesperrt")
        appears(app, "Abgleich steht aus")
        shot(app, "\(tag)-laden-2-waehrend")
        // Die Anzeige hängt am Abgleich, nicht an einer Uhr: auch lange ohne Freigabe bleibt alles gesperrt.
        Thread.sleep(forTimeInterval: 8)
        XCTAssertFalse(sync.isEnabled, "ohne Freigabe weiter gesperrt")
        XCTAssertTrue(app.element(labelContaining: "Abgleich steht aus").exists, "ohne Freigabe weiter „Abgleich steht aus“")
        releaseHealthSync()
        becomesEnabled(sync)
        appears(app, "Abgeglichen")
        disappears(app, "Abgleich steht aus")
        shot(app, "\(tag)-laden-3-nachher")
    }

    @MainActor
    func testBusyEndsWhenTheSyncFails() {
        let app = settings("slow-error")
        app.tapRevealed(app.buttons["healthConnect"])
        let sync = app.buttons["healthSync"]
        XCTAssertTrue(sync.waitForExistence(timeout: 20))
        XCTAssertFalse(sync.isEnabled)
        releaseHealthSync()
        becomesEnabled(sync)
        appears(app, "Abgleich fehlgeschlagen")
        disappears(app, "Abgleich steht aus")
    }

    @MainActor
    func testUnavailableAlertDisappears() {
        let app = settings("unavailable")
        shot(app, "\(tag)-meldung-1-vorher")
        app.tapRevealed(app.buttons["healthConnect"])
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 8))
        shot(app, "\(tag)-meldung-2-waehrend")
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 8))
        becomesEnabled(app.buttons["healthConnect"])
        shot(app, "\(tag)-meldung-3-nachher")
    }

    @MainActor
    func testEmptyHistoryDisappearsAfterImport() {
        let app = launch("empty", health: "workouts")
        app.tabBars.buttons["Verlauf"].tapWhenReady()
        appears(app, "Noch keine Aktivitäten")
        shot(app, "\(tag)-verlauf-1-vorher")
        app.buttons["settingsButton"].tap()
        app.tapRevealed(app.buttons["healthConnect"])
        appears(app, "Abgeglichen")
        shot(app, "\(tag)-verlauf-2-waehrend")
        app.buttons["settingsDone"].tap()
        appears(app, "42,3 km")
        disappears(app, "Noch keine Aktivitäten")
        shot(app, "\(tag)-verlauf-3-nachher")
    }
}
