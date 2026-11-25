import XCTest

/// M3 (SPEC 6.1, S01, S08): Apple Health verbinden, Zeitraum wählen, Import sehen, Import-Status. Gegen die
/// Fake-Quelle (`-UITestHealth`), nie gegen HealthKit.
final class HealthUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testOnboardingConnectsWithChosenWindowImportsAndAppliesDeletions() {
        let app = launch("fresh", health: "workouts")
        app.buttons["onboardingNext"].tapWhenReady()
        XCTAssertTrue(app.buttons["window.90"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["window.90"].isSelected, "Vorgabe: letzte 90 Tage")
        app.tapRevealed(app.buttons["window.365"])
        XCTAssertTrue(app.buttons["window.365"].isSelected)
        app.buttons["onboardingHealthConnect"].tapWhenReady()
        app.buttons["onboardingFirstGearLater"].tapWhenReady()

        app.tabBars.buttons["Verlauf"].tapWhenReady()
        XCTAssertTrue(app.element(labelContaining: "42,3 km").waitForExistence(timeout: 10))
        XCTAssertTrue(app.element(labelContaining: "7,5 km").exists)

        app.buttons["settingsButton"].tapWhenReady()
        XCTAssertTrue(app.element(labelContaining: "Abgeglichen").waitForExistence(timeout: 10))
        XCTAssertTrue(app.element(labelContaining: "Letzte 365 Tage").exists)
        // Zweiter Abgleich: die Quelle meldet den Lauf als gelöscht.
        app.tapRevealed(app.buttons["healthSync"])
        app.buttons["settingsDone"].tapWhenReady()
        XCTAssertTrue(app.element(labelContaining: "7,5 km").waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.element(labelContaining: "42,3 km").exists)
    }

    @MainActor
    func testConnectingInSettingsWithNothingVisibleStaysNeutral() {
        let app = launch("empty", health: "empty")
        app.buttons["settingsButton"].tapWhenReady()
        XCTAssertTrue(app.element(labelContaining: "Nicht verbunden").waitForExistence(timeout: 8))
        app.tapRevealed(app.buttons["healthConnect"])
        XCTAssertTrue(app.element(labelContaining: "Keine Trainings sichtbar").waitForExistence(timeout: 10))
        XCTAssertFalse(app.element(labelContaining: "verweigert").exists, "nie eine Diagnose zum Zugriff (F-04)")
    }

    @MainActor
    func testUnavailableHealthIsExplainedInsideSettings() {
        let app = launch("empty", health: "unavailable")
        app.buttons["settingsButton"].tapWhenReady()
        app.tapRevealed(app.buttons["healthConnect"])
        XCTAssertTrue(app.alerts.staticTexts["Apple Health ist auf diesem Gerät nicht verfügbar."].waitForExistence(timeout: 8))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.element(labelContaining: "Nicht verbunden").exists)
    }

    @MainActor
    func testLockedDeviceShowsPendingImportAndRecovers() {
        let app = launch("empty", health: "locked")
        app.buttons["settingsButton"].tapWhenReady()
        app.tapRevealed(app.buttons["healthConnect"])
        XCTAssertTrue(app.element(labelContaining: "Import ausstehend").waitForExistence(timeout: 10))
        app.tapRevealed(app.buttons["healthSync"])
        XCTAssertTrue(app.element(labelContaining: "Abgeglichen").waitForExistence(timeout: 10))
    }
}
