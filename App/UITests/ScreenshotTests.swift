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
    /// File names start with the phase ("p3-07-…") so every phase's captures can share one folder.
    private var phase = 2

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

    /// Phase 3: Planner map with Sun/Moon overlays, panels 1–4, time bar and jumps, map
    /// styles, the pin/device time toggle, and antimeridian, polar and southern pins.
    func testPhase3Planner() throws {
        continueAfterFailure = false
        phase = 3
        // 21 June 2026, 20:30 in Warsaw: evening golden hour, waxing Moon in the south-west.
        let app = launch(date: "2026-06-21T18:30:00Z", place: "Warsaw")
        app.tabBars.buttons["Planner"].tap()
        waitFor(app, id: "planner.panel.pin")
        settleMap()
        snap(app, "planner-warsaw-pin")
        for panel in ["sun", "moon", "twilights"] {
            app.buttons["planner.panelTab.\(panel)"].tap()
            waitFor(app, id: "planner.panel.\(panel)")
            snap(app, "planner-warsaw-\(panel)")
        }

        app.buttons["planner.panelTab.sun"].tap()
        tapJump(app, "sunrise")
        settleMap()
        snap(app, "planner-jump-sunrise")
        tapJump(app, "moonrise")
        app.buttons["planner.panelTab.moon"].tap()
        settleMap()
        snap(app, "planner-jump-moonrise")
        tapJump(app, "now")
        let ruler = app.descendants(matching: .any)["planner.timebar"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        ruler.swipeLeft()
        settleMap()
        snap(app, "planner-scrubbed-later")

        for style in ["Satellite", "Hybrid", "Terrain"] {
            app.buttons["planner.options"].tap()
            app.buttons[style].firstMatch.tap()
            settleMap(seconds: 4)
            snap(app, "planner-style-\(style.lowercased())")
        }
        app.buttons["planner.options"].tap()
        app.buttons["Standard"].firstMatch.tap()

        app.buttons["planner.panelTab.pin"].tap()
        app.buttons["planner.options"].tap()
        app.buttons["planner.timezoneToggle"].firstMatch.tap()
        settleMap(seconds: 1)
        snap(app, "planner-device-time")
        app.buttons["planner.options"].tap()
        app.buttons["planner.timezoneToggle"].firstMatch.tap()

        // Taveuni sits on the antimeridian: lines cross it without wrapping round the map.
        app.buttons["planner.search"].firstMatch.tap()
        expectVisible(app.buttons["place.Taveuni"].firstMatch)
        snap(app, "planner-search")
        pickPlace(app, "Taveuni")
        app.buttons["planner.panelTab.sun"].tap()
        settleMap(seconds: 4)
        snap(app, "planner-taveuni-antimeridian")

        // Longyearbyen in June: midnight sun, no sunrise or sunset lines.
        app.buttons["planner.search"].firstMatch.tap()
        pickPlace(app, "Longyearbyen")
        settleMap(seconds: 4)
        snap(app, "planner-longyearbyen-midnight-sun")
        app.buttons["planner.panelTab.twilights"].tap()
        snap(app, "planner-longyearbyen-twilights")

        // Sydney: southern hemisphere, the Sun's path arcs through the north.
        app.buttons["planner.search"].firstMatch.tap()
        pickPlace(app, "Sydney")
        app.buttons["planner.panelTab.sun"].tap()
        tapJump(app, "sunrise")
        settleMap(seconds: 4)
        snap(app, "planner-sydney-sunrise")
    }

    /// Phase 4: Milky Way pill (night windows, core path and arc orientation, best months and
    /// nights) for northern and southern sites, and the Planner's Milky Way panel, arc and jumps.
    func testPhase4MilkyWay() throws {
        continueAfterFailure = false
        phase = 4
        // 14 July 2026, 23:30 in New York: new moon, the core low in the south.
        let app = launch(date: "2026-07-15T03:30:00Z", place: "New York")

        app.tabBars.buttons["Planner"].tap()
        waitFor(app, id: "planner.panel.pin")
        app.buttons["planner.panelTab.milkyWay"].tap()
        waitFor(app, id: "planner.panel.milkyWay")
        settleMap()
        snap(app, "planner-milkyway-panel-newyork")
        tapJump(app, "milkyWayEnd")
        settleMap()
        snap(app, "planner-jump-milkyway-end")
        tapJump(app, "milkyWayStart")
        settleMap()
        snap(app, "planner-jump-milkyway-start")
        // Only the Milky Way layer: the band's arc across the sky and the core's direction.
        for layer in ["sun", "moon"] {
            app.buttons["planner.options"].tap()
            app.descendants(matching: .any)["planner.layer.\(layer)"].firstMatch.tap()
        }
        settleMap()
        snap(app, "planner-milkyway-layer-only")
        for layer in ["sun", "moon"] {
            app.buttons["planner.options"].tap()
            app.descendants(matching: .any)["planner.layer.\(layer)"].firstMatch.tap()
        }

        app.tabBars.buttons["Tools"].tap()
        expectVisible(app.buttons["Milky Way"].firstMatch)
        snap(app, "tools")
        app.buttons["Milky Way"].firstMatch.tap()
        expectVisible(app, "Core visible")
        snap(app, "milkyway-night-newyork")
        app.swipeUp()
        snap(app, "milkyway-night-newyork-hourly")
        scrollToTop(app)
        app.segmentedControls.buttons["Year"].tap()
        expectVisible(app, "First core night")
        snap(app, "milkyway-year-newyork")
        app.swipeUp()
        snap(app, "milkyway-year-newyork-best-nights")
        let bestNight = app.buttons["milkyway.bestNight"].firstMatch
        if bestNight.waitForExistence(timeout: 5) {
            bestNight.tap()
            Thread.sleep(forTimeInterval: 1)
            scrollToTop(app)
            expectVisible(app, "Core visible")
            snap(app, "milkyway-best-night")
        }
        scrollToTop(app)

        // Sydney: southern winter is the best season, the core passes high overhead.
        app.buttons["pill.location"].firstMatch.tap()
        pickPlace(app, "Sydney")
        app.segmentedControls.buttons["Night"].tap()
        expectVisible(app, "Core visible")
        snap(app, "milkyway-night-sydney")
        app.segmentedControls.buttons["Year"].tap()
        expectVisible(app, "First core night")
        snap(app, "milkyway-year-sydney")

        // Warsaw at 52°N: no astronomical night around midsummer, so a gap in the season.
        app.buttons["pill.location"].firstMatch.tap()
        pickPlace(app, "Warsaw")
        expectVisible(app, "First core night")
        snap(app, "milkyway-year-warsaw-summer-gap")
        app.segmentedControls.buttons["Night"].tap()
        expectVisible(app, "Core visible")
        snap(app, "milkyway-night-warsaw-no-dark")
    }

    /// Phase 5: photography calculators and the camera catalogue.
    func testPhase5Optics() throws {
        continueAfterFailure = false
        phase = 5
        let app = launch(date: "2026-07-15T03:30:00Z", place: "New York", camera: "sony-a7r-iv")
        app.tabBars.buttons["Tools"].tap()
        expectVisible(app.buttons["Exposure"].firstMatch)
        snap(app, "tools-photography")

        openTool(app, "Exposure", expecting: "Exposure value")
        snap(app, "exposure-equivalent-nd")
        app.segmentedControls.buttons["Aperture"].tap()
        snap(app, "exposure-solve-aperture")
        app.segmentedControls.buttons["Shutter"].tap()
        app.swipeUp()
        let timer = app.buttons["exposure.timer"].firstMatch
        if timer.waitForExistence(timeout: 5) && timer.isEnabled {
            timer.tap()
            Thread.sleep(forTimeInterval: 0.4)
        }
        snap(app, "exposure-long-exposure-timer")
        goBack(app)

        openTool(app, "Depth of field", expecting: "Near limit")
        snap(app, "dof-classic-a7riv-24mm")
        app.segmentedControls.buttons["Advanced"].tap()
        expectVisible(app, "Print size")
        snap(app, "dof-advanced-print")
        app.swipeUp()
        snap(app, "dof-advanced-diffraction")
        scrollToTop(app)
        app.segmentedControls.buttons["Table"].tap()
        snap(app, "dof-table")
        scrollToTop(app)
        app.segmentedControls.buttons["Hyperfocal"].tap()
        snap(app, "dof-hyperfocal-table")
        goBack(app)

        openTool(app, "Field of view", expecting: "Focal length")
        snap(app, "fov-forward")
        app.segmentedControls.buttons["Find focal"].tap()
        snap(app, "fov-find-focal-length")
        goBack(app)

        openTool(app, "Spot stars", expecting: "Declination")
        snap(app, "spot-stars-npf")
        goBack(app)

        openTool(app, "Star trails", expecting: "Total exposure")
        snap(app, "star-trails-length")
        app.swipeUp()
        snap(app, "star-trails-sketch")
        scrollToTop(app)
        app.segmentedControls.buttons["Exposure time"].tap()
        snap(app, "star-trails-exposure-for-length")
        goBack(app)

        openTool(app, "Time lapse", expecting: "Event duration")
        snap(app, "timelapse-clip")
        app.segmentedControls.buttons["Interval"].tap()
        snap(app, "timelapse-solve-interval")
        app.swipeUp()
        snap(app, "timelapse-presets")
        goBack(app)

        // Camera catalogue: search, the default camera, a custom camera form.
        openTool(app, "Cameras", expecting: "Add a camera")
        snap(app, "cameras-catalogue")
        let search = app.searchFields.firstMatch
        if !search.exists { app.swipeDown() }
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("canon r5")
            expectVisible(app.buttons["camera.canon-eos-r5"].firstMatch, in: app)
            snap(app, "cameras-search")
            app.buttons["Cancel"].firstMatch.tap()
        }
        app.buttons["camera.add"].firstMatch.tap()
        expectVisible(app, "Brand")
        snap(app, "cameras-custom-form")
        app.buttons["Cancel"].firstMatch.tap()
    }

    /// Phase 6: target pin, geodetics and obstacle panels, Find, field and depth of field on the map.
    func testPhase6Geodetics() throws {
        continueAfterFailure = false
        phase = 6
        // 29 May 2026, 19:30 EDT in Lower Manhattan; the target is a 60 m tower 4 km away
        // in Jersey City along the Manhattanhenge azimuth (299.1°).
        let app = launch(date: "2026-05-29T23:30:00Z", place: "New York", camera: "sony-a7r-iv",
                         extra: ["-target", "40.73029,-74.04748", "-objectHeight", "60"])
        app.tabBars.buttons["Planner"].tap()
        waitFor(app, id: "planner.panel.pin")
        app.buttons["planner.panelTab.geodetics"].tap()
        waitFor(app, id: "planner.panel.geodetics")
        expectVisible(app, "Distance")
        settleMap(seconds: 4)
        snap(app, "planner-geodetics-panel")
        app.buttons["planner.panelTab.obstacle"].tap()
        expectVisible(app, "Angle to top")
        snap(app, "planner-obstacle-panel")

        // Find: the Sun on the target's bearing with its disc on the horizon.
        app.buttons["planner.find"].tap()
        expectVisible(app.buttons["find.search"].firstMatch, in: app)
        snap(app, "find-form-target-bearing")
        // The Find button sits under the home indicator until the form scrolls.
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        app.buttons["find.search"].firstMatch.tap()
        let result = app.buttons["find.result"].firstMatch
        expectVisible(result, in: app)
        snap(app, "find-results-manhattanhenge")
        result.tap()
        settleMap()
        snap(app, "planner-find-result-sun-on-target-line")

        // Field and depth of field drawn along the target's bearing.
        app.buttons["planner.options"].tap()
        app.descendants(matching: .any)["planner.targetOptions"].firstMatch.tap()
        let fov = app.switches["planner.optics.fov"].firstMatch
        expectVisible(fov, in: app)
        turnOn(fov, in: app)
        turnOn(app.switches["planner.optics.dof"].firstMatch, in: app)
        snap(app, "planner-target-optics-sheet")
        app.buttons["Done"].firstMatch.tap()
        settleMap()
        snap(app, "planner-fov-dof-on-map")
        app.buttons["planner.panelTab.geodetics"].tap()
        settleMap(seconds: 1)
        snap(app, "planner-fov-dof-geodetics")
    }

    func testPhase7Plans() throws {
        continueAfterFailure = false
        phase = 7
        // Three example plans and two places are seeded into an in-memory store.
        let app = launch(date: "2026-06-21T16:00:00Z", place: "Warsaw", camera: "sony-a7r-iv", extra: ["-seedPlans"])
        app.tabBars.buttons["My Stuff"].tap()
        let manhattan = app.buttons.matching(NSPredicate(format: "identifier == 'plan.row' AND label BEGINSWITH 'Manhattanhenge'"))
            .firstMatch
        expectVisible(manhattan, in: app)
        settleMap(seconds: 4)
        snap(app, "my-stuff-plans")

        // Share and export from the context menu.
        manhattan.press(forDuration: 1.2)
        expectVisible(app, "Share as text")
        snap(app, "plan-context-menu")
        // Tap the blurred background below the menu to close it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        Thread.sleep(forTimeInterval: 1)

        // Swipe to duplicate.
        manhattan.swipeLeft()
        expectVisible(app.buttons["Duplicate"].firstMatch, in: app)
        snap(app, "plan-swipe-actions")
        app.buttons["Duplicate"].firstMatch.tap()
        expectVisible(app, "Manhattanhenge copy")
        snap(app, "plan-duplicated")

        // Open a plan: the Planner jumps to its place, time, target pin and panel.
        manhattan.tap()
        waitFor(app, id: "planner.panel.obstacle")
        settleMap(seconds: 4)
        snap(app, "plan-opened-in-planner")

        // Save the Planner's state as a new plan.
        app.buttons["planner.savePlan"].tap()
        expectVisible(app.buttons["plan.save"].firstMatch, in: app)
        snap(app, "save-plan-sheet")
        app.buttons["plan.save"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 3)
        app.tabBars.buttons["My Stuff"].tap()
        expectVisible(app, "New York plan")
        settleMap(seconds: 2)
        snap(app, "my-stuff-after-save")

        app.buttons["Places"].firstMatch.tap()
        expectVisible(app, "Tromsø")
        snap(app, "my-stuff-places")
        app.buttons["Cameras"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)
        snap(app, "my-stuff-cameras")

        app.tabBars.buttons["Settings"].tap()
        expectVisible(app, "Default camera")
        snap(app, "settings-default-camera")

        // Export every plan as one JSON file through the share sheet.
        app.tabBars.buttons["My Stuff"].tap()
        app.buttons["Plans"].firstMatch.tap()
        expectVisible(manhattan, in: app)
        app.buttons["plans.export"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 3)
        snap(app, "export-all-share-sheet")
    }

    // MARK: Helpers

    /// Taps a place in the location sheet, scrolling the list first when the row sits under
    /// the home indicator.
    private func pickPlace(_ app: XCUIApplication, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = app.buttons["place.\(name)"].firstMatch
        expectVisible(row, in: app, file: file, line: line)
        let screen = app.windows.firstMatch.frame
        for _ in 0..<4 where row.frame.maxY > screen.maxY - 90 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
        }
        row.tap()
        // The sheet must close; a missed tap leaves it up.
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: row)
        if XCTWaiter.wait(for: [closed], timeout: 5) != .completed && row.exists {
            row.tap()
        }
    }

    /// Taps a jump button, first dragging the jump row sideways while the button is off
    /// screen (XCUITest cannot even ask an off-screen SwiftUI button whether it is hittable).
    private func tapJump(_ app: XCUIApplication, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons["planner.jump.\(name)"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "No jump \(name)", file: file, line: line)
        let screen = app.windows.firstMatch.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<6 {
            let frame = button.frame
            if frame.minX >= screen.minX && frame.maxX <= screen.maxX { break }
            let y = frame.midY
            let (from, to) = frame.midX > screen.midX ? (0.8, 0.2) : (0.2, 0.8)
            origin.withOffset(CGVector(dx: screen.width * from, dy: y))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: screen.width * to, dy: y)))
            Thread.sleep(forTimeInterval: 0.5)
        }
        button.tap()
    }

    private func waitFor(_ app: XCUIApplication, id: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = app.descendants(matching: .any)[id].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 15), "Nothing with identifier \(id)", file: file, line: line)
    }

    /// Opens a Tools entry, scrolling the list until the row is reachable.
    private func openTool(_ app: XCUIApplication, _ name: String, expecting label: String,
                          file: StaticString = #filePath, line: UInt = #line) {
        let row = app.buttons[name].firstMatch
        expectVisible(row, in: app, file: file, line: line)
        let screen = app.windows.firstMatch.frame
        for _ in 0..<4 where row.frame.maxY > screen.maxY - 100 { app.swipeUp(); Thread.sleep(forTimeInterval: 0.5) }
        row.tap()
        expectVisible(app, label, file: file, line: line)
    }

    /// Lists drop rows that scroll off screen, so segmented pickers at the top must be
    /// scrolled back into view before tapping them.
    private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<3 { app.swipeDown() }
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Scrolls a toggle clear of the home indicator, then flips it until it reads on.
    private func turnOn(_ toggle: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let screen = app.windows.firstMatch.frame
        for _ in 0..<4 where toggle.frame.maxY > screen.maxY - 90 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
        }
        for _ in 0..<3 where toggle.value as? String != "1" {
            flip(toggle)
        }
        XCTAssertEqual(toggle.value as? String, "1", "Toggle did not turn on", file: file, line: line)
    }

    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 0.4)
    }

    private func goBack(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Gives map tiles and overlays time to draw.
    private func settleMap(seconds: Double = 2.5) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func launch(date: String, place: String, camera: String? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-fixedDate", date, "-place", place]
        if let camera { app.launchArguments += ["-camera", camera] }
        app.launchArguments += extra
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
        let fileName = String(format: "p%d-%02d-%@", phase, counter, name)
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
