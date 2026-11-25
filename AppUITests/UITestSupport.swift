import XCTest

extension XCTestCase {
    /// `fixture`: fresh (Onboarding), empty (fertig, ohne Daten), basic (5 Ausrüstungsteile, 4 Aktivitäten).
    @MainActor
    func launch(_ fixture: String, health: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-EingelaufenInMemory", "-UITestFixture", fixture,
                               "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        // Fake-Trainingsquelle (Debug): workouts, empty, locked, unavailable. Ohne Angabe liefert sie nichts.
        if let health { app.launchArguments += ["-UITestHealth", health] }
        app.launch()
        return app
    }

    /// Legt den Screenshot an den Test an und, wenn SCREENSHOT_DIR (TEST_RUNNER_SCREENSHOT_DIR) gesetzt ist, auch als Datei ab.
    @MainActor
    func shot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}

extension XCUIApplication {
    /// Irgendein Element, dessen Beschriftung den Text enthält (zusammengefasste Zeilen tragen einen Gesamttext).
    func element(labelContaining text: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
    func element(id: String) -> XCUIElement { descendants(matching: .any)[id] }
}

extension XCUIElement {
    @discardableResult
    func tapWhenReady(timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertTrue(waitForExistence(timeout: timeout), "Element fehlt: \(self)", file: file, line: line)
        tap()
        return self
    }
}

extension XCUIApplication {
    /// Listen laden lazy und die schwebende Tab-Leiste verdeckt den unteren Rand: nach oben wischen, bis das Element
    /// existiert, tippbar ist und im oberen Dreiviertel des Bildschirms liegt.
    @discardableResult
    func reveal(_ element: XCUIElement, attempts: Int = 8) -> Bool {
        var n = 0
        func ready() -> Bool { element.exists && element.isHittable && element.frame.midY < frame.height * 0.75 }
        while !(element.waitForExistence(timeout: 2) && ready()) && n < attempts { swipeUp(); n += 1 }
        return ready() || element.exists
    }

    func tapRevealed(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(reveal(element), "Element fehlt: \(element)", file: file, line: line)
        element.tap()
    }
}
