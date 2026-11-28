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

extension XCTestCase {
    /// M6: wartet auf dem Home-Bildschirm auf die Mitteilung; ein Systemdialog „Erlauben“ (erste Anfrage im Simulator kommt
    /// spät) wird unterwegs bestätigt. Liefert die Mitteilung oder `nil`.
    @MainActor
    func waitForBanner(containing text: String, on springboard: XCUIApplication, timeout: TimeInterval = 60) -> XCUIElement? {
        let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Erlauben", "Allow"])).firstMatch
        let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if allow.exists { allow.tap() }
            if banner.exists { return banner }
            Thread.sleep(forTimeInterval: 1)
        }
        return nil
    }
}

extension XCUIApplication {
    /// Erstes Element mit dieser Kennung (Beschriftungen mit Symbol liefern mehrere Treffer).
    func first(id: String) -> XCUIElement { descendants(matching: .any).matching(identifier: id).firstMatch }

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

extension XCUIElement {
    /// Der Schalter sitzt rechts in der Zeile; ein Tipp in die Mitte trifft nur die Beschriftung (siehe FlowUITests).
    func flip(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForExistence(timeout: 8), "Schalter fehlt: \(self)", file: file, line: line)
        coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }
}

extension XCTestCase {
    /// Bestätigungsdialoge erscheinen als Popover ohne „Abbrechen“: ein Tipp daneben bricht ab.
    @MainActor
    func dismissDialog(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let outside = app.element(id: "PopoverDismissRegion")
        if outside.exists { outside.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap() }
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 5), "Dialog schließt nicht", file: file, line: line)
    }

    /// Fake-Trainingsquelle (Debug, Szenarien `slow`/`slow-error`): Der Abgleich läuft, bis der Test ihn freigibt.
    /// Darwin-Mitteilung, weil Test und App getrennte Prozesse im selben Simulator sind
    /// (Name wie `DebugHealthSource.releaseName`).
    func releaseHealthSync() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName("de.linolaske.eingelaufen.uitest.releaseHealth" as CFString),
                                             nil, nil, true)
    }
}

extension XCTestCase {
    // MARK: Systemdialoge (Dateien)

    /// Sichern-Dialog von `fileExporter`: Ort „Auf meinem iPhone“ und „Sichern“.
    @MainActor
    func saveInFilesPicker(_ app: XCUIApplication) {
        let save = app.buttons.matching(NSPredicate(format: "label IN %@", ["Sichern", "Save", "Bewegen", "Move"])).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 15), "Sichern-Dialog fehlt")
        let onDevice = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Auf meinem iPhone", "On My iPhone"])).firstMatch
        if onDevice.waitForExistence(timeout: 3), onDevice.isHittable { onDevice.tap() }
        save.tap()
        // Der Dateiname trägt die Uhrzeit, ein „Ersetzen“ (läuft außerhalb der App) sollte nie kommen.
        let replace = app.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Ersetzen", "Replace"])).firstMatch
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if replace.exists { replace.tap() }
            if !save.exists && !replace.exists { return }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTFail("Sichern-Dialog schließt nicht")
    }

    /// Öffnen-Dialog von `fileImporter`: die zuletzt gesicherte Backup-Datei wählen.
    @MainActor
    func openFromFilesPicker(_ app: XCUIApplication) {
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
