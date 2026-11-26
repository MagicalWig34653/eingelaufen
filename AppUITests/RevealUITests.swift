import XCTest

/// Befund 25.11. (Karte D2E0F20D): Nach einem Wischer mit Nachlauf lag die Zeile „Frühere Komponenten → Kette“ unter der
/// durchsichtigen Navigationsleiste. `reveal` hielt sie trotzdem für sichtbar, der Tap traf die Statusleiste (Liste springt
/// nach oben) und die alte Komponente öffnete sich nicht. Dieser Test stellt die Lage gezielt her.
final class RevealUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testRevealBringsARowOutFromUnderTheNavigationBar() {
        let app = launch("maintenance")
        app.tabBars.buttons["Ausrüstung"].tapWhenReady()
        app.buttons["gear.Canyon Endurace"].tapWhenReady()
        let row = app.buttons["component.Kette"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        let bar = app.navigationBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5))

        // Ohne Nachlauf so weit ziehen, dass die Zeile mitten unter der Navigationsleiste liegt.
        for _ in 0..<4 where row.frame.midY > bar.frame.maxY {
            app.drag(by: row.frame.midY - bar.frame.midY)
        }
        XCTAssertTrue(row.exists)
        XCTAssertLessThan(row.frame.midY, bar.frame.maxY, "Vorbedingung: Zeile liegt unter der Navigationsleiste")

        XCTAssertTrue(app.reveal(row))
        XCTAssertGreaterThan(row.frame.midY, bar.frame.maxY, "reveal holt die Zeile unter der Navigationsleiste hervor")
        row.tap()
        let title = app.staticTexts["detailName"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertEqual(title.label, "Kette", "Der Tap öffnet die Komponente")
    }
}
