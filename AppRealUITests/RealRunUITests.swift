import XCTest

/// **Echter Lauf**: ohne `-EingelaufenInMemory`, ohne Fixtures, ohne Fake-Quelle. Echter Dateispeicher und echtes
/// HealthKit des Simulators. Läuft nur im Schema `EingelaufenEcht` auf frisch installierter App
/// (`scripts/echter-lauf.sh`), nie in der normalen Suite.
final class RealRunUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func log(_ text: String) { print("ECHT \(Date().formatted(.iso8601)): \(text)") }

    @MainActor
    private func start() -> XCUIApplication {
        let app = XCUIApplication()
        // Nur Sprache: kein Schalter der App.
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        return app
    }

    /// Systemdialog von Health: alle Kategorien einschalten und bestätigen. Je nach iOS gehört er zum App- oder
    /// zu einem Dienstprozess, die Sprache folgt dem Gerät.
    @MainActor
    private func allowHealth(for app: XCUIApplication, shotName: String) {
        let hosts = [app,
                     XCUIApplication(bundleIdentifier: "com.apple.HealthPrivacyService"),
                     XCUIApplication(bundleIdentifier: "com.apple.springboard")]
        func find(_ labels: [String], timeout: TimeInterval, buttonsOnly: Bool = false) -> XCUIElement? {
            let predicate = NSPredicate(format: "label IN %@ OR identifier IN %@", labels, labels)
            let end = Date().addingTimeInterval(timeout)
            repeat {
                for host in hosts where host.state != .notRunning {
                    for query in (buttonsOnly ? [host.buttons] : [host.buttons, host.switches, host.cells, host.staticTexts]) {
                        let element = query.matching(predicate).firstMatch
                        if element.exists { return element }
                    }
                }
                RunLoop.current.run(until: Date().addingTimeInterval(1))
            } while Date() < end
            return nil
        }
        let allLabels = ["UIA.Health.AuthSheet.AllCategoryButton", "Alle aktivieren", "Alle einschalten", "Turn On All"]
        guard let all = find(allLabels, timeout: 40) else {
            for host in hosts where host.state != .notRunning { print(host.debugDescription) }
            return XCTFail("Health-Dialog nicht gefunden (\(shotName))")
        }
        log("Health-Systemdialog sichtbar (\(shotName))")
        shot(app, "echt-\(shotName)-dialog")
        all.tap()
        let allowLabels = ["UIA.Health.Allow.Button", "Erlauben", "Zulassen", "Allow"]
        // Bei vielen Themen (die App liest Trainings und neun Distanzarten) liegt „Erlauben“ unter der Liste.
        var allowed = find(allowLabels, timeout: 3, buttonsOnly: true)
        var swipes = 0
        while allowed == nil && swipes < 12 {
            for host in hosts where host.state != .notRunning { host.swipeUp() }
            swipes += 1
            allowed = find(allowLabels, timeout: 2, buttonsOnly: true)
        }
        guard let allow = allowed else {
            for host in hosts where host.state != .notRunning { print(host.debugDescription) }
            return XCTFail("Knopf zum Erlauben nicht gefunden (\(shotName))")
        }
        // Der Standard-Tap scrollt hier nicht: manuell ans untere Ende wischen, dann per Koordinate tippen.
        let screen = app.windows.firstMatch.frame
        var guardSwipes = 0
        while guardSwipes < 12 && !(allow.frame.midY > 0 && allow.frame.midY < screen.height * 0.92) {
            for host in hosts where host.state != .notRunning { host.swipeUp() }
            guardSwipes += 1
        }
        shot(app, "echt-\(shotName)-ausgewaehlt")
        print("ECHT-DEBUG Erlauben: type=\(allow.elementType.rawValue) frame=\(allow.frame) hittable=\(allow.isHittable) id=\(allow.identifier)")
        allow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        shot(app, "echt-\(shotName)-nach-erlauben")
        // iOS 26: Lesende Apps bekommen eine zweite Seite „Wie viele Daten teilen?“. Die App braucht den Verlauf,
        // also „Alle Dateneinträge“ wählen und noch einmal bestätigen.
        if let range = find(["Alle Dateneinträge und zukünftige Daten", "All Records and Future Data"], timeout: 5) {
            log("Zweite Seite „Wie viele Daten teilen?“ sichtbar, wähle alle Dateneinträge")
            range.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            shot(app, "echt-\(shotName)-zeitraum")
            guard let confirm = find(allowLabels, timeout: 10, buttonsOnly: true) else {
                return XCTFail("Bestätigen auf der zweiten Seite nicht gefunden (\(shotName))")
            }
            confirm.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(2))
        }
        log("Health-Zugriff bestätigt (\(shotName))")
    }

    /// „Importierte Trainings“ ist ein LabeledContent: Titel und Zahl können als Label oder als Wert ankommen.
    @MainActor
    private func assertImported(_ app: XCUIApplication, _ count: Int, timeout: TimeInterval,
                                file: StaticString = #filePath, line: UInt = #line) {
        let row = app.element(labelContaining: "Importierte Trainings")
        let end = Date().addingTimeInterval(timeout)
        var seen = ""
        repeat {
            if row.exists {
                seen = "\(row.label) | \(row.value as? String ?? "")"
                let digits = seen.split(whereSeparator: { !$0.isNumber }).map(String.init)
                if digits == ["\(count)"] { return }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < end
        print(app.debugDescription)
        XCTFail("Importierte Trainings: erwartet \(count), gesehen „\(seen)“", file: file, line: line)
    }

    @MainActor
    func testRealStoreSurvivesRestartAndRealHealthKitImports() {
        // 1. Echter Dateispeicher
        var app = start()
        app.buttons["onboardingNext"].tapWhenReady(timeout: 30)
        app.buttons["onboardingHealthLater"].tapWhenReady()
        app.buttons["onboardingChooseTemplate"].tapWhenReady()
        app.buttons["category.running"].tapWhenReady()
        app.buttons["template.running.shoes"].tapWhenReady()
        app.buttons["gearSave"].tapWhenReady()
        app.buttons["onboardingDone"].tapWhenReady()
        app.tabBars.buttons["Ausrüstung"].tapWhenReady()
        XCTAssertTrue(app.buttons["gear.Laufschuhe"].waitForExistence(timeout: 15))
        log("Ausrüstung „Laufschuhe“ angelegt (frische Installation, Onboarding)")
        shot(app, "echt-1-angelegt")
        app.terminate()
        log("App beendet")
        app = start()
        app.tabBars.buttons["Ausrüstung"].tapWhenReady(timeout: 30)
        XCTAssertTrue(app.buttons["gear.Laufschuhe"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["onboardingNext"].exists)
        log("Nach Neustart: „Laufschuhe“ noch da, kein Onboarding → echter Dateispeicher")
        shot(app, "echt-2-nach-neustart")
        app.terminate()

        // 2. Ein Training in Health anlegen (nur das Test-Hilfsziel schreibt).
        let seeder = XCUIApplication(bundleIdentifier: "de.linolaske.eingelaufen.healthseeder")
        seeder.launch()
        seeder.buttons["seed"].tapWhenReady(timeout: 30)
        allowHealth(for: seeder, shotName: "3-hilfsziel-schreiben")
        let status = seeder.staticTexts["seedStatus"]
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'gespeichert' OR label BEGINSWITH 'Fehler'"),
                                             object: status)
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: 40), .completed, "Hilfsziel antwortet nicht")
        log("Test-Hilfsziel: \(status.label)")
        XCTAssertTrue(status.label.hasPrefix("gespeichert"), status.label)
        seeder.terminate()

        // 3. Echtes HealthKit: Lesefreigabe im Systemdialog, Abgleich importiert.
        app = start()
        app.buttons["settingsButton"].tapWhenReady(timeout: 30)
        app.tapRevealed(app.buttons["healthConnect"])
        allowHealth(for: app, shotName: "4-app-lesen")
        XCTAssertTrue(app.element(labelContaining: "Abgeglichen").waitForExistence(timeout: 40), "kein Abgleich")
        assertImported(app, 1, timeout: 10)
        log("Echtes HealthKit: Status „Abgeglichen“, importierte Trainings: 1")
        shot(app, "echt-5-abgeglichen")
        app.tapRevealed(app.buttons["healthSync"])
        assertImported(app, 1, timeout: 20)
        log("Zweiter Abgleich mit echtem Anker: weiterhin 1")
        app.buttons["settingsDone"].tapWhenReady()
        app.tabBars.buttons["Verlauf"].tapWhenReady()
        XCTAssertTrue(app.element(labelContaining: "5,4 km").waitForExistence(timeout: 15))
        log("Verlauf zeigt den Lauf mit 5,4 km")
        shot(app, "echt-6-verlauf")
        app.terminate()
        app = start()
        app.tabBars.buttons["Verlauf"].tapWhenReady(timeout: 30)
        XCTAssertTrue(app.element(labelContaining: "5,4 km").waitForExistence(timeout: 15))
        app.buttons["settingsButton"].tapWhenReady()
        assertImported(app, 1, timeout: 20)
        log("Nach Neustart: Import und Anker gespeichert, keine Doppelung")
        shot(app, "echt-7-nach-neustart")
    }
}
