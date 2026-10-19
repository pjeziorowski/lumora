// App/UITests/ScreenshotTests.swift
//
// Walks through every screen delivered so far on the simulator and saves a screenshot of
// each, as an XCTest attachment and, when SCREENSHOT_DIR is set (CI passes
// TEST_RUNNER_SCREENSHOT_DIR), as numbered PNG files. The app runs with a fixed place and
// time so the captures are reproducible.

import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {
    private var counter = 0

    /// Phase 2: Sun and Moon tools and the shared location picker.
    func testPhase2SunAndMoonTools() throws {
        continueAfterFailure = false
        // 21 June 2026, 20:30 in Warsaw: evening golden hour, Moon just past first quarter.
        let app = launch(date: "2026-06-21T18:30:00Z", place: "Warsaw")

        app.tabBars.buttons["Tools"].tap()
        expectVisible(app.buttons["Sun"].firstMatch)
        snap(app, "tools")

        app.buttons["Sun"].firstMatch.tap()
        expectVisible(app, "Sunrise")
        snap(app, "sun-day-warsaw")
        for (segment, marker, name) in [
            ("Twilight", "Astronomical dawn", "sun-twilight-warsaw"),
            ("Graph", "Highest", "sun-graph-warsaw"),
            ("Month", "Next month", "sun-month-warsaw"),
            ("Seasons", "Next year", "sun-seasons-warsaw"),
        ] {
            app.segmentedControls.buttons[segment].tap()
            expectVisible(app, marker)
            snap(app, name)
        }

        app.buttons["pill.location"].firstMatch.tap()
        expectVisible(app.buttons["place.Tromsø"].firstMatch)
        snap(app, "location-picker")
        app.buttons["place.Tromsø"].firstMatch.tap()

        // Tromsø on the same date: midnight sun, no sunrise or sunset.
        app.segmentedControls.buttons["Day"].tap()
        expectVisible(app, "Sunrise")
        snap(app, "sun-day-tromso-midnight-sun")
        app.segmentedControls.buttons["Twilight"].tap()
        expectVisible(app, "Astronomical dawn")
        snap(app, "sun-twilight-tromso-midnight-sun")
        app.segmentedControls.buttons["Seasons"].tap()
        expectVisible(app, "Midnight sun")
        snap(app, "sun-seasons-tromso-polar-days")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Moon"].firstMatch.tap()
        expectVisible(app, "Moonrise")
        snap(app, "moon-day-tromso")

        // Sydney: southern hemisphere, the Moon's lit side is mirrored.
        app.buttons["pill.location"].firstMatch.tap()
        expectVisible(app.buttons["place.Sydney"].firstMatch)
        app.buttons["place.Sydney"].firstMatch.tap()
        expectVisible(app, "Moonrise")
        snap(app, "moon-day-sydney")
        for (segment, marker, name) in [
            ("Calendar", "This month", "moon-calendar-sydney"),
            ("Full & new", "Full moons", "moon-full-new-sydney"),
        ] {
            app.segmentedControls.buttons[segment].tap()
            expectVisible(app, marker)
            snap(app, name)
        }
        app.swipeUp()
        snap(app, "moon-full-new-sydney-scrolled")
    }

    // MARK: Helpers

    private func launch(date: String, place: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-fixedDate", date, "-place", place]
        app.launch()
        return app
    }

    /// Waits for any element whose label starts with `label` (rows combine label and value).
    private func expectVisible(_ app: XCUIApplication, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        expectVisible(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH[c] %@", label)).firstMatch,
                      in: app, file: file, line: line)
    }

    private func expectVisible(_ element: XCUIElement, in app: XCUIApplication? = nil,
                               file: StaticString = #filePath, line: UInt = #line) {
        if !element.waitForExistence(timeout: 15) {
            // Keep a picture of what was on screen instead of the missing element.
            snap(app ?? XCUIApplication(), "FAILED-step")
            XCTFail("Not found: \(element)", file: file, line: line)
        }
        // Let async reports and charts finish drawing.
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        counter += 1
        let fileName = String(format: "%02d-%@", counter, name)
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(fileName).png")
            try? shot.pngRepresentation.write(to: url)
        }
    }
}
