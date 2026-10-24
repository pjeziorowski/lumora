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
    /// Replaces "p<phase>" at the start of file names for captures that belong to no phase.
    private var prefix: String?

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
            tapPanelTab(app, panel)
            waitFor(app, id: "planner.panel.\(panel)")
            snap(app, "planner-warsaw-\(panel)")
        }

        tapPanelTab(app, "sun")
        tapJump(app, "sunrise")
        settleMap()
        snap(app, "planner-jump-sunrise")
        tapJump(app, "moonrise")
        tapPanelTab(app, "moon")
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

        tapPanelTab(app, "pin")
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
        tapPanelTab(app, "sun")
        settleMap(seconds: 4)
        snap(app, "planner-taveuni-antimeridian")

        // Longyearbyen in June: midnight sun, no sunrise or sunset lines.
        app.buttons["planner.search"].firstMatch.tap()
        pickPlace(app, "Longyearbyen")
        settleMap(seconds: 4)
        snap(app, "planner-longyearbyen-midnight-sun")
        tapPanelTab(app, "twilights")
        snap(app, "planner-longyearbyen-twilights")

        // Sydney: southern hemisphere, the Sun's path arcs through the north.
        app.buttons["planner.search"].firstMatch.tap()
        pickPlace(app, "Sydney")
        tapPanelTab(app, "sun")
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
        tapPanelTab(app, "milkyWay")
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
        tapPanelTab(app, "geodetics")
        waitFor(app, id: "planner.panel.geodetics")
        expectVisible(app, "Distance")
        settleMap(seconds: 4)
        snap(app, "planner-geodetics-panel")
        tapPanelTab(app, "obstacle")
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
        tapPanelTab(app, "geodetics")
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

    func testPhase8AR() throws {
        continueAfterFailure = false
        phase = 8
        // Warsaw at 20:30 on the June solstice, looking toward the sunset. The simulator has
        // no camera or motion sensors, so the view direction comes from -arView and a drawn
        // sky stands in for the camera.
        var app = launch(date: "2026-06-21T18:30:00Z", place: "Warsaw", extra: ["-arView", "300,8,0"])
        app.tabBars.buttons["Planner"].tap()
        waitFor(app, id: "planner.panel.pin")
        app.buttons["planner.ar"].tap()
        expectVisible(app, "Az ")
        Thread.sleep(forTimeInterval: 1.5)
        snap(app, "planner-ar-sun-moon-sunset-warsaw")
        let slider = app.sliders["ar.timeSlider"].firstMatch
        slider.adjust(toNormalizedSliderPosition: 0.535)
        Thread.sleep(forTimeInterval: 1.5)
        snap(app, "ar-time-scrubbed-to-sunset")
        app.buttons["ar.calibrate"].tap()
        expectVisible(app, "Compass")
        snap(app, "ar-calibration-sheet")
        app.buttons["ar.calibration.align"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)
        snap(app, "ar-aligned-on-moon")
        app.buttons["Close"].firstMatch.tap()
        app.terminate()

        // New York at 23:30 in mid-July: the core over the southern horizon.
        app = launch(date: "2026-07-15T03:30:00Z", place: "New York", extra: ["-arView", "165,18,0"])
        app.tabBars.buttons["Tools"].tap()
        openTool(app, "Milky Way AR", expecting: "Az ")
        Thread.sleep(forTimeInterval: 1.5)
        snap(app, "ar-milkyway-core-newyork")
        app.buttons["Night"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)
        snap(app, "ar-night-south-newyork")
        app.terminate()

        app = launch(date: "2026-07-15T03:30:00Z", place: "New York", extra: ["-arView", "0,30,0"])
        app.tabBars.buttons["Tools"].tap()
        openTool(app, "Night AR", expecting: "Az ")
        Thread.sleep(forTimeInterval: 1.5)
        snap(app, "ar-night-north-polaris-newyork")
        app.terminate()

        // Southern sky: the south celestial pole from Cape Town, no Polaris.
        app = launch(date: "2026-07-15T19:00:00Z", place: "Cape Town", extra: ["-arView", "180,30,0"])
        app.tabBars.buttons["Tools"].tap()
        openTool(app, "Night AR", expecting: "Az ")
        Thread.sleep(forTimeInterval: 1.5)
        snap(app, "ar-night-south-pole-capetown")
        app.terminate()

        // Frame AR: a 50 mm frame on a Sony α7R IV, focused at 5 m, with the near limit, focus
        // and far limit drawn on the ground.
        app = launch(date: "2026-06-21T10:00:00Z", place: "Warsaw", camera: "sony-a7r-iv", extra: ["-arView", "200,-4,0"])
        app.tabBars.buttons["Tools"].tap()
        openTool(app, "Frame AR", expecting: "Az ")
        Thread.sleep(forTimeInterval: 1.5)
        snap(app, "ar-frame-50mm-dof")
    }

    func testPhase9Events() throws {
        continueAfterFailure = false
        phase = 9
        // Midnight on 12–13 August 2026 in Warsaw: the Perseid peak under a new Moon, hours
        // after the total solar eclipse over Spain (partial from Warsaw before sunset).
        var app = launch(date: "2026-08-12T22:00:00Z", place: "Warsaw")
        app.tabBars.buttons["Planner"].tap()
        waitFor(app, id: "planner.panel.pin")
        tapPanelTab(app, "meteors")
        waitFor(app, id: "planner.panel.meteors")
        expectVisible(app, "Shower")
        settleMap(seconds: 3)
        snap(app, "planner-meteors-perseids-radiant")
        tapPanelTab(app, "eclipse")
        expectVisible(app, "Next here")
        snap(app, "planner-eclipse-panel")
        // Zoom out to the continent to see the eclipse centre line.
        let map = app.descendants(matching: .any)["planner.map"].firstMatch
        for _ in 0..<4 {
            map.pinch(withScale: 0.12, velocity: -3)
            Thread.sleep(forTimeInterval: 0.6)
        }
        settleMap(seconds: 4)
        snap(app, "planner-eclipse-path-on-map")

        app.tabBars.buttons["Tools"].tap()
        openTool(app, "Meteor showers", expecting: "Showers in")
        snap(app, "meteor-showers-year-warsaw")
        openRow(app, app.buttons["meteors.PER"].firstMatch)
        expectVisible(app, "Best time")
        snap(app, "meteor-perseids-night-warsaw")
        app.terminate()

        // The eclipse list starts at the session day, so open it on the morning of the eclipse.
        app = launch(date: "2026-08-12T10:00:00Z", place: "Warsaw")
        app.tabBars.buttons["Tools"].tap()
        openTool(app, "Eclipses", expecting: "Next eclipses")
        snap(app, "eclipses-list-warsaw")
        let rows = app.buttons.matching(identifier: "eclipse.row")
        openRow(app, rows.element(boundBy: 0))
        expectVisible(app, "Magnitude")
        snap(app, "eclipse-solar-2026-08-12-contacts")
        app.swipeUp()
        settleMap(seconds: 4)
        snap(app, "eclipse-solar-path-map")
        goBack(app)
        openRow(app, rows.element(boundBy: 1))
        expectVisible(app, "From Warsaw")
        snap(app, "eclipse-lunar-2026-08-28")
        app.terminate()

        // Southern hemisphere: the Eta Aquariids from Cape Town, a southern shower whose
        // radiant climbs high before dawn.
        app = launch(date: "2026-05-06T00:00:00Z", place: "Cape Town")
        app.tabBars.buttons["Tools"].tap()
        openTool(app, "Meteor showers", expecting: "Showers in")
        openRow(app, app.buttons["meteors.ETA"].firstMatch)
        expectVisible(app, "Best time")
        snap(app, "meteor-eta-aquariids-capetown")
    }

    func testPhase10WidgetsAndPolish() throws {
        continueAfterFailure = false
        phase = 10
        // First launch: the introduction, page by page.
        var app = launch(date: "2026-06-21T18:30:00Z", place: "Warsaw", extra: ["-showOnboarding", "-seedPlans"])
        expectVisible(app, "Plan the light")
        snap(app, "onboarding-welcome")
        for name in ["place", "units", "plans"] {
            app.buttons["onboarding.next"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 0.8)
            snap(app, "onboarding-\(name)")
        }
        app.buttons["onboarding.start"].firstMatch.tap()

        // Widgets at Warsaw's golden hour on the solstice, with the seeded plans.
        app.tabBars.buttons["Settings"].tap()
        openRow(app, app.buttons["settings.widgets"].firstMatch)
        expectVisible(app.descendants(matching: .any)["widgets.small"].firstMatch, in: app)
        snap(app, "widgets-sun-home")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        snap(app, "widgets-sun-lock-screen")
        app.swipeDown()
        for (label, name) in [("Moon", "moon"), ("Next plan", "next-plan")] {
            app.segmentedControls["widgets.kind"].buttons[label].tap()
            Thread.sleep(forTimeInterval: 1)
            snap(app, "widgets-\(name)")
        }
        app.terminate()

        // Milky Way widget: New York in mid-July, the core up after midnight.
        app = launch(date: "2026-07-15T02:00:00Z", place: "New York")
        app.tabBars.buttons["Settings"].tap()
        openRow(app, app.buttons["settings.widgets"].firstMatch)
        app.segmentedControls["widgets.kind"].buttons["Milky Way"].tap()
        expectVisible(app.descendants(matching: .any)["widgets.small"].firstMatch, in: app)
        Thread.sleep(forTimeInterval: 1)
        snap(app, "widgets-milkyway")
        app.terminate()

        // Polish localization.
        app = launch(date: "2026-06-21T18:30:00Z", place: "Warsaw", extra: ["-showOnboarding", "-AppleLanguages", "(pl)",
                                                                            "-AppleLocale", "pl_PL"])
        expectVisible(app, "Zaplanuj")
        snap(app, "polish-onboarding")
        app.buttons["onboarding.skip"].firstMatch.tap()
        app.tabBars.buttons.element(boundBy: 1).tap()
        Thread.sleep(forTimeInterval: 1)
        snap(app, "polish-tools")
        app.tabBars.buttons.element(boundBy: 3).tap()
        Thread.sleep(forTimeInterval: 1)
        snap(app, "polish-settings")
        app.terminate()

        // Largest accessibility text size.
        app = launch(date: "2026-06-21T18:30:00Z", place: "Warsaw",
                     extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        app.tabBars.buttons["Tools"].tap()
        Thread.sleep(forTimeInterval: 1)
        snap(app, "dynamic-type-tools")
        openTool(app, "Sun", expecting: "Sunrise")
        snap(app, "dynamic-type-sun")
        // The time ruler's hour labels scale too, thinned out so they do not overlap.
        app.tabBars.buttons["Planner"].tap()
        waitFor(app, id: "planner.panel.pin")
        settleMap()
        snap(app, "dynamic-type-planner")
    }

    /// Accessibility pass: Xcode's accessibility audit on the main screens. Issues are written
    /// to p10-accessibility-audit.txt next to the screenshots, with a screenshot of each
    /// audited screen, instead of failing the run, so the list can be worked through.
    func testPhase10AccessibilityAudit() throws {
        phase = 10
        prefix = "audit"
        let app = launch(date: "2026-06-21T18:30:00Z", place: "Warsaw", extra: ["-seedPlans"])
        var report: [String] = []
        func audit(_ screen: String) {
            Thread.sleep(forTimeInterval: 1.5)
            snap(app, screen.lowercased().replacingOccurrences(of: " ", with: "-"))
            var count = 0
            func record(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
                count += 1
                report.append([screen, Self.auditTypeName(issue.auditType), issue.compactDescription,
                               Self.describe(issue.element), issue.detailedDescription].joined(separator: " | "))
                return true
            }
            do {
                try app.performAccessibilityAudit(for: .all) { record($0) }
            } catch {
                // The whole audit can run out of time on a busy screen (the Planner's map);
                // one type at a time fits.
                report.append("\(screen) | full audit failed (\(error.localizedDescription)); auditing one type at a time")
                for (type, _) in Self.auditTypes {
                    do {
                        try app.performAccessibilityAudit(for: type) { record($0) }
                    } catch {
                        report.append("\(screen) | \(Self.auditTypeName(type)) audit failed: \(error.localizedDescription)")
                    }
                }
            }
            report.append("\(screen) | \(count) issues")
        }
        app.tabBars.buttons["Planner"].tap()
        waitFor(app, id: "planner.panel.pin")
        settleMap()
        audit("Planner")
        app.tabBars.buttons["Tools"].tap()
        audit("Tools")
        openTool(app, "Sun", expecting: "Sunrise")
        audit("Sun")
        goBack(app)
        openTool(app, "Meteor showers", expecting: "Showers in")
        audit("Meteor showers")
        app.tabBars.buttons["My Stuff"].tap()
        audit("My Stuff")
        app.tabBars.buttons["Settings"].tap()
        audit("Settings")
        let text = report.joined(separator: "\n") + "\n"
        let attachment = XCTAttachment(string: text)
        attachment.name = "p10-accessibility-audit"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            try? text.write(to: URL(fileURLWithPath: dir).appendingPathComponent("p10-accessibility-audit.txt"),
                            atomically: true, encoding: .utf8)
        }
    }

    private static let auditTypes: [(XCUIAccessibilityAuditType, String)] = [
        (.contrast, "contrast"), (.elementDetection, "element detection"), (.hitRegion, "hit region"),
        (.sufficientElementDescription, "element description"), (.dynamicType, "dynamic type"),
        (.textClipped, "text clipped"), (.trait, "trait"),
    ]

    private static func auditTypeName(_ type: XCUIAccessibilityAuditType) -> String {
        auditTypes.first { $0.0 == type }?.1 ?? "type \(type.rawValue)"
    }

    /// "button 'Sun' id=planner.panelTab.sun at (45,120 44x44)", or "-" when the audit names no element.
    private static func describe(_ element: XCUIElement?) -> String {
        guard let element, element.exists else { return "-" }
        let f = element.frame
        return "\(element.elementType.rawValue) '\(element.label)' id=\(element.identifier) "
            + "at (\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)))"
    }

    /// Large text: the Planner's panels at the largest accessibility size (AX5) and at AX3,
    /// the panel buttons at the default size, and the screens whose audit issues were fixed.
    func testAccessibilityLargeText() throws {
        continueAfterFailure = false
        prefix = "a11y"
        var app = launch(date: "2026-06-21T18:30:00Z", place: "Warsaw",
                         extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.tabBars.buttons["Planner"].tap()
        waitFor(app, id: "planner.panel.pin")
        settleMap()
        snap(app, "planner-ax5-pin")
        for panel in ["sun", "moon", "twilights", "eclipse"] {
            tapPanelTab(app, panel)
            waitFor(app, id: "planner.panel.\(panel)")
            Thread.sleep(forTimeInterval: 0.8)
            snap(app, "planner-ax5-\(panel)")
        }
        // Rows scroll inside the panel; the last Sun row is reachable.
        tapPanelTab(app, "sun")
        waitFor(app, id: "planner.panel.sun")
        let panel = app.descendants(matching: .any)["planner.panel.sun"].firstMatch
        panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 2.2))
            .press(forDuration: 0.05, thenDragTo: panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        Thread.sleep(forTimeInterval: 0.8)
        snap(app, "planner-ax5-sun-scrolled")
        app.terminate()

        app = launch(date: "2026-06-21T18:30:00Z", place: "Warsaw",
                     extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        app.tabBars.buttons["Planner"].tap()
        waitFor(app, id: "planner.panel.pin")
        settleMap()
        snap(app, "planner-ax3-pin")
        tapPanelTab(app, "sun")
        waitFor(app, id: "planner.panel.sun")
        Thread.sleep(forTimeInterval: 0.8)
        snap(app, "planner-ax3-sun")
        app.terminate()

        // Default size: nine 44 pt panel buttons, high-contrast secondary text everywhere.
        app = launch(date: "2026-06-21T18:30:00Z", place: "Warsaw", extra: ["-seedPlans"])
        app.tabBars.buttons["Planner"].tap()
        waitFor(app, id: "planner.panel.pin")
        settleMap()
        let tab = app.buttons["planner.panelTab.eclipse"].firstMatch
        XCTAssertGreaterThanOrEqual(tab.frame.width, 44, "Panel buttons must be at least 44 pt wide")
        XCTAssertGreaterThanOrEqual(tab.frame.height, 44, "Panel buttons must be at least 44 pt tall")
        snap(app, "planner-default-tabs")
        app.tabBars.buttons["Tools"].tap()
        openTool(app, "Sun", expecting: "Sunrise")
        snap(app, "sun-contrast")
        goBack(app)
        openTool(app, "Meteor showers", expecting: "Showers in")
        snap(app, "meteors-contrast")
        app.tabBars.buttons["My Stuff"].tap()
        Thread.sleep(forTimeInterval: 1)
        snap(app, "mystuff-contrast")
        app.tabBars.buttons["Settings"].tap()
        Thread.sleep(forTimeInterval: 1)
        snap(app, "settings-pickers")
        let coordinates = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Coordinates")).firstMatch
        if coordinates.waitForExistence(timeout: 5) {
            coordinates.tap()
            Thread.sleep(forTimeInterval: 1)
            snap(app, "settings-coordinates-picker")
        }
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
        tapInScrollingRow(app, app.buttons["planner.jump.\(name)"].firstMatch, file: file, line: line)
    }

    /// Taps a Planner panel button; the row scrolls when the buttons do not all fit.
    private func tapPanelTab(_ app: XCUIApplication, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        tapInScrollingRow(app, app.buttons["planner.panelTab.\(name)"].firstMatch, file: file, line: line)
    }

    /// Drags a horizontally scrolling row until `button` lies fully on screen, then taps it.
    private func tapInScrollingRow(_ app: XCUIApplication, _ button: XCUIElement,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(button.waitForExistence(timeout: 10), "No \(button)", file: file, line: line)
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
        // Rows below the fold do not exist until the list scrolls to them.
        for _ in 0..<4 where !row.waitForExistence(timeout: 2) {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
        }
        expectVisible(row, in: app, file: file, line: line)
        let screen = app.windows.firstMatch.frame
        for _ in 0..<4 where row.frame.maxY > screen.maxY - 100 { app.swipeUp(); Thread.sleep(forTimeInterval: 0.5) }
        row.tap()
        expectVisible(app, label, file: file, line: line)
    }

    /// Taps a list row, scrolling until it exists and clears the home indicator.
    private func openRow(_ app: XCUIApplication, _ row: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<5 where !row.waitForExistence(timeout: 2) {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
        }
        expectVisible(row, in: app, file: file, line: line)
        let screen = app.windows.firstMatch.frame
        for _ in 0..<4 where row.frame.maxY > screen.maxY - 100 { app.swipeUp(); Thread.sleep(forTimeInterval: 0.5) }
        row.tap()
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

    /// Tapping a SwiftUI toggle's centre hits its label; tap the switch at the trailing edge.
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
        let fileName = String(format: "%@-%02d-%@", prefix ?? "p\(phase)", counter, name)
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
