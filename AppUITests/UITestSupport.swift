import XCTest

extension XCTestCase {
    /// `fixture`: fresh (Onboarding), empty (fertig, ohne Daten), basic (5 Ausrüstungsteile, 4 Aktivitäten).
    @MainActor
    func launch(_ fixture: String, health: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-EingelaufenInMemory", "-UITestFixture", fixture,
                               "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        // Fake-Trainingsquelle (Debug): workouts, empty, locked, error, later, slow, slow-error, unavailable.
        // Ohne Angabe liefert sie nichts.
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
    /// Listen laden lazy, die schwebende Tab-Leiste verdeckt den unteren Rand und Inhalt läuft unter die durchsichtige
    /// Navigationsleiste. Das Element gilt erst als sichtbar, wenn es zwischen beiden Leisten liegt; ein Tap darüber träfe
    /// die Statusleiste (Liste springt nach oben, Befund 25.11.). Fehlt es noch, wird gewischt; existiert es, wird es ohne
    /// Nachlauf in die Mitte gezogen.
    @discardableResult
    func reveal(_ element: XCUIElement, attempts: Int = 8) -> Bool {
        func band() -> (top: CGFloat, bottom: CGFloat) {
            let bar = navigationBars.firstMatch, tabs = tabBars.firstMatch
            let top = bar.exists ? bar.frame.maxY : frame.height * 0.12
            let bottom = tabs.exists ? tabs.frame.minY : frame.height * 0.9
            return (top, bottom)
        }
        func visible() -> Bool {
            guard element.exists, element.isHittable else { return false }
            let (top, bottom) = band(), y = element.frame.midY
            return y > top && y < bottom
        }
        for _ in 0..<attempts {
            guard element.waitForExistence(timeout: 2) else { swipeUp(); continue }
            if visible() { return true }
            let (top, bottom) = band()
            drag(by: element.frame.midY - (top + bottom) / 2)
        }
        return visible()
    }

    /// Zieht den Inhalt ruhig um `delta` Punkte nach oben (negativ: nach unten), ohne Nachlauf: der Finger hält am Ende kurz an.
    /// Höchstens 40 % der Bildschirmhöhe je Zug, damit Start und Ziel auf dem Bildschirm bleiben.
    func drag(by delta: CGFloat) {
        let h = frame.height
        let d = max(-0.4 * h, min(0.4 * h, delta))
        let startY = d > 0 ? 0.7 * h : 0.3 * h
        let origin = coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.width / 2, dy: startY))
        let end = origin.withOffset(CGVector(dx: frame.width / 2, dy: startY - d))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    func tapRevealed(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(reveal(element), "Element fehlt: \(element)", file: file, line: line)
        element.tap()
    }
}
