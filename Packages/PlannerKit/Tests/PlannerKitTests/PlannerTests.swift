// Packages/PlannerKit/Tests/PlannerKitTests/PlannerTests.swift
//
// Phase 3 acceptance: the Planner's snapshot and map overlays agree with the Sun and Moon
// tools; pins on the antimeridian and in polar regions compute without NaNs or jumps;
// scrubbing is memoized and cheap enough for 60 fps.

import AstroCore
import Foundation
import GeoCore
import Testing
@testable import PlannerKit

struct PlannerTests {
    static let warsaw = PillLocation.samples[0]
    static let taveuni = PillLocation.samples.first { $0.name == "Taveuni" }!
    static let longyearbyen = PillLocation.samples.first { $0.name == "Longyearbyen" }!

    static func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    static func snapshot(_ location: PillLocation, _ iso: String) -> PlannerSnapshot {
        let date = instant(iso)
        let day = PlannerDay.compute(location: location, day: LocalDay(containing: date, timeZone: location.timeZone))
        return PlannerSnapshot.compute(location: location, instant: date, day: day)
    }

    // MARK: Agreement with the Sun and Moon tools

    @Test(arguments: PillLocation.samples)
    func snapshotMatchesPills(location: PillLocation) {
        for iso in ["2026-03-20T12:00:00Z", "2026-06-21T12:00:00Z", "2026-12-21T12:00:00Z"] {
            let date = Self.instant(iso)
            let day = LocalDay(containing: date, timeZone: location.timeZone)
            let planner = PlannerDay.compute(location: location, day: day)
            let snap = PlannerSnapshot.compute(location: location, instant: date, day: planner)
            let sun = SunDayReport.compute(location: location, day: day, instant: date)
            let moon = MoonDayReport.compute(location: location, day: day, instant: date)

            #expect(planner.sunRises == sun.rises)
            #expect(planner.sunSets == sun.sets)
            #expect(planner.solarNoon == sun.noon)
            #expect(planner.sunState == sun.state)
            #expect(abs(planner.daylightSeconds - sun.daylightSeconds) < 1e-6)
            #expect(planner.moonRises == moon.rises)
            #expect(planner.moonSets == moon.sets)
            #expect(abs(snap.sun.azimuth - sun.position.azimuth) < 1e-9)
            #expect(abs(snap.sun.altitude - sun.position.altitude) < 1e-9)
            #expect(snap.lightPhase == sun.lightPhase)
            #expect(abs(snap.moon.position.azimuth - moon.position.azimuth) < 1e-9)
            #expect(abs(snap.moon.illumination - moon.illumination) < 1e-12)
            #expect(snap.moon.phaseName == moon.phaseName)
        }
    }

    /// Each rise/set/now line on the map points exactly along the azimuth the tools report.
    @Test(arguments: PillLocation.samples)
    func overlayBearingsMatchAzimuths(location: PillLocation) {
        let snap = Self.snapshot(location, "2026-06-21T18:30:00Z")
        let overlays = PlannerOverlays.build(snap, radius: 5000)
        let pin = location.geoPoint
        func bearing(_ line: OverlayLine) -> Double { Geodesy.inverse(pin, line.points[1]).initialBearing }
        func close(_ a: Double, _ b: Double) -> Bool { abs(((a - b + 540).truncatingRemainder(dividingBy: 360)) - 180) < 1e-6 }

        let sunRises = overlays.lines.filter { $0.body == .sun && $0.role == .rise }
        #expect(sunRises.count == snap.day.sunRises.count)
        for (line, event) in zip(sunRises, snap.day.sunRises) { #expect(close(bearing(line), event.azimuth)) }
        let moonSets = overlays.lines.filter { $0.body == .moon && $0.role == .set }
        for (line, event) in zip(moonSets, snap.day.moonSets) { #expect(close(bearing(line), event.azimuth)) }
        let sunNow = overlays.lines.first { $0.body == .sun && $0.role == .now }!
        #expect(close(bearing(sunNow), snap.sun.azimuth))
        #expect(sunNow.isAboveHorizon == snap.sun.isUp)
        #expect(abs(Geodesy.inverse(pin, sunNow.points[1]).distance - 5750) < 0.01)
    }

    @Test func pathProjectionPutsHorizonOnCircle() {
        let pin = Self.warsaw.geoPoint
        let horizon = PlannerOverlays.project(120, 0, pin: pin, radius: 1000)
        #expect(abs(Geodesy.inverse(pin, horizon).distance - 1000) < 1e-4)
        let thirty = PlannerOverlays.project(120, 30, pin: pin, radius: 1000)
        #expect(abs(Geodesy.inverse(pin, thirty).distance - 1000 * 60 / 90) < 1e-4)
        let below = PlannerOverlays.project(120, -10, pin: pin, radius: 1000)
        #expect(abs(Geodesy.inverse(pin, below).distance - 1000) < 1e-4)
    }

    /// Warsaw, 21 June: the Sun's path is one run below the horizon, one above, one below,
    /// and consecutive runs share their horizon crossing.
    @Test func pathSegmentsAlternateAndJoin() {
        let snap = Self.snapshot(Self.warsaw, "2026-06-21T12:00:00Z")
        let path = PlannerOverlays.build(snap, radius: 1000).lines
            .filter { $0.body == .sun && ($0.role == .pathUp || $0.role == .pathDown) }
        #expect(path.map(\.role) == [.pathDown, .pathUp, .pathDown])
        for (a, b) in zip(path, path.dropFirst()) {
            #expect(a.points.last == b.points.first)
        }
    }

    // MARK: Edge cases: antimeridian and poles

    @Test func datelineOverlaysAreContinuous() {
        for location in [Self.taveuni,
                         PillLocation(name: "East of 180", latitude: -16.8, longitude: -179.999, timeZoneIdentifier: "Pacific/Fiji")] {
            let snap = Self.snapshot(location, "2026-06-21T06:00:00Z")
            let overlays = PlannerOverlays.build(snap, radius: 50_000)
            for line in overlays.lines {
                for (a, b) in zip(line.points, line.points.dropFirst()) {
                    #expect(abs(a.longitude - b.longitude) < 5, "\(line.id) jumps across the map")
                }
                for p in line.points { #expect(abs(p.longitude - location.longitude) < 5) }
            }
        }
    }

    /// Sweeps a pin across the antimeridian and up to the pole on dates with midnight sun,
    /// polar night and equinox; everything stays finite.
    @Test func pinSweepAcrossDatelineAndPoles() {
        let dates = ["2026-06-21T00:00:00Z", "2026-12-21T12:00:00Z", "2026-03-20T06:00:00Z"]
        var cases = 0
        for lat in [-90.0, -89.9, -78.0, -66.6, 0, 66.6, 78.2, 85.1, 89.99, 90] {
            for lon in [179.9, 179.999, 180, -180, -179.999, -179.9, 0] {
                let location = PillLocation(name: "Sweep", latitude: lat, longitude: lon,
                                            timeZoneIdentifier: PlaceLookup.nauticalZone(longitude: lon).identifier)
                for iso in dates {
                    let snap = Self.snapshot(location, iso)
                    #expect(snap.sun.azimuth.isFinite && snap.sun.altitude.isFinite)
                    #expect(snap.moon.position.azimuth.isFinite && snap.moon.illumination.isFinite)
                    let overlays = PlannerOverlays.build(snap, radius: 20_000)
                    for line in overlays.lines {
                        for p in line.points {
                            #expect(p.latitude.isFinite && p.longitude.isFinite)
                            let safe = PlannerOverlays.mercatorSafe(p)
                            #expect(abs(safe.latitude) <= PlannerOverlays.mercatorLimit)
                        }
                    }
                    _ = PlannerPanels.all(snapshot: snap, instant: snap.instant, options: PlannerDisplayOptions())
                    cases += 1
                }
            }
        }
        #expect(cases == 210)
    }

    @Test func midnightSunPanels() {
        let snap = Self.snapshot(Self.longyearbyen, "2026-06-21T22:00:00Z")
        #expect(snap.day.sunState == .alwaysAbove)
        #expect(snap.day.sunRises.isEmpty && snap.day.sunSets.isEmpty)
        let sun = PlannerPanels.panel(.sun, snapshot: snap, instant: snap.instant, options: PlannerDisplayOptions())
        #expect(sun.rows.first { $0.label == "Sunrise" }?.value == "Sun up all day")
        #expect(sun.rows.first { $0.label == "Daylight" }?.value == "All day (midnight sun)")
        let twilight = PlannerPanels.panel(.twilights, snapshot: snap, instant: snap.instant, options: PlannerDisplayOptions())
        #expect(twilight.rows.last?.value == "Midnight sun")
        // No rise/set lines, but the path and the "now" line are drawn.
        let lines = PlannerOverlays.build(snap, radius: 1000).lines.filter { $0.body == .sun }
        #expect(!lines.contains { $0.role == .rise || $0.role == .set })
        #expect(lines.contains { $0.role == .pathUp } && lines.contains { $0.role == .now })
        #expect(!snap.day.lightBands.contains { $0.phase == .night })
    }

    // MARK: Light bands for the time bar

    @Test func lightBandsCoverWindowContiguously() {
        let snap = Self.snapshot(Self.warsaw, "2026-06-21T12:00:00Z")
        let bands = snap.day.lightBands
        #expect(bands.first?.start == snap.day.day.start.addingTimeInterval(-12 * 3600))
        #expect(bands.last?.end == snap.day.day.end.addingTimeInterval(12 * 3600))
        for (a, b) in zip(bands, bands.dropFirst()) {
            #expect(a.end == b.start)
            #expect(a.phase != b.phase)
        }
        // Evening golden hour starts within 5 minutes of the twilight report's.
        let golden = snap.day.twilight.eveningGoldenHours[0]
        let band = bands.first { $0.phase == .goldenHour && $0.start > snap.day.day.noon && $0.start < snap.day.day.end }!
        #expect(abs(band.start.timeIntervalSince(golden.start)) <= 150)
        // Warsaw in June: astronomical twilight all night, no true night.
        #expect(!bands.contains { $0.phase == .night && $0.start >= snap.day.day.start && $0.end <= snap.day.day.end })
    }

    // Warsaw DST days (EU rule, timeanddate.com): 29 Mar 2026 is 23 h, 25 Oct 2026 is 25 h.
    @Test(arguments: [("2026-03-29T10:00:00Z", 23.0), ("2026-10-25T10:00:00Z", 25.0)])
    func dstDaysKeepBandsAndJumpsContiguous(iso: String, hours: Double) {
        let snap = Self.snapshot(Self.warsaw, iso)
        let day = snap.day
        #expect(day.day.end.timeIntervalSince(day.day.start) == hours * 3600)
        let bands = day.lightBands
        #expect(bands.first?.start == day.day.start.addingTimeInterval(-12 * 3600))
        #expect(bands.last?.end == day.day.end.addingTimeInterval(12 * 3600))
        for (a, b) in zip(bands, bands.dropFirst()) { #expect(a.end == b.start) }
        #expect(day.sunRises.count == 1 && day.sunSets.count == 1)
        let rise = day.sunRises[0].time
        #expect(rise > day.day.start && rise < day.day.end)
    }

    // MARK: Jumps

    @Test func jumpsCycleThroughTheDay() {
        let snap = Self.snapshot(Self.warsaw, "2026-06-21T18:30:00Z")
        let day = snap.day
        let now = Self.instant("2026-06-21T18:30:00Z")
        // After the evening's sunrise has passed, "Sunrise" wraps to the morning one.
        #expect(PlannerJump.sunrise.target(from: now, day: day, now: now) == day.sunRises[0].time)
        #expect(PlannerJump.sunset.target(from: now, day: day, now: now) == day.sunSets[0].time)
        let goldens = day.twilight.goldenHours.map(\.start)
        #expect(goldens.count == 2)
        let first = PlannerJump.goldenHour.target(from: day.day.start, day: day, now: now)!
        #expect(first == goldens[0])
        #expect(PlannerJump.goldenHour.target(from: first, day: day, now: now) == goldens[1])
        #expect(PlannerJump.goldenHour.target(from: goldens[1], day: day, now: now) == goldens[0])
        #expect(PlannerJump.now.target(from: first, day: day, now: now) == now)
        // Midnight sun: nothing to jump to.
        let polar = Self.snapshot(Self.longyearbyen, "2026-06-21T12:00:00Z")
        #expect(PlannerJump.sunrise.target(from: now, day: polar.day, now: now) == nil)
    }

    // MARK: Panels

    @Test func pinPanelShowsZoneAndDeviceTime() {
        let snap = Self.snapshot(Self.warsaw, "2026-06-21T18:30:00Z")
        var options = PlannerDisplayOptions(deviceTimeZone: TimeZone(identifier: "America/New_York")!)
        let pin = PlannerPanels.panel(.pin, snapshot: snap, instant: snap.instant, options: options)
        #expect(pin.rows.first { $0.label == "Time zone" }?.value == "Europe/Warsaw (UTC+2)")
        #expect(pin.rows.first { $0.label == "Pin time" }?.value == "Sun 21 Jun 20:30")
        #expect(pin.rows.first { $0.label == "Device time" }?.value == "Sun 21 Jun 14:30 (UTC-4)")
        // Device-time toggle switches every other panel's clock.
        options.useDeviceTimeZone = true
        let sun = PlannerPanels.panel(.sun, snapshot: snap, instant: snap.instant, options: options)
        let pinSun = PlannerPanels.panel(.sun, snapshot: snap, instant: snap.instant, options: PlannerDisplayOptions())
        #expect(sun.rows.first { $0.label == "Sunset" }?.value != pinSun.rows.first { $0.label == "Sunset" }?.value)
        #expect(pinSun.rows.first { $0.label == "Sunset" }?.value.hasPrefix("21:0") == true)
    }

    @Test func supermoonFlagOnlyNearPrincipalPhase() {
        // USNO: full moon 24 Dec 2026 01:28 UT; timeanddate lists it as a supermoon.
        let near = Self.snapshot(Self.warsaw, "2026-12-23T12:00:00Z")
        #expect(near.moon.size == .supermoon)
        let quarter = Self.snapshot(Self.warsaw, "2026-12-17T12:00:00Z")
        #expect(quarter.moon.size == nil)
    }
}

// MARK: - Engine memoization and scrub cost

struct PlannerEngineTests {
    @Test func memoizesPerMinuteAndDay() async {
        let engine = PlannerEngine()
        let location = PillLocation.samples[0]
        let start = PlannerTests.instant("2026-06-21T08:00:00Z")
        _ = await engine.snapshot(location: location, instant: start)
        _ = await engine.snapshot(location: location, instant: start.addingTimeInterval(20))
        #expect(await engine.snapshotComputations == 1)
        for minute in 1...600 {
            _ = await engine.snapshot(location: location, instant: start.addingTimeInterval(Double(minute) * 60))
        }
        #expect(await engine.snapshotComputations == 601)
        #expect(await engine.dayComputations == 1)
        // Scrubbing back over the same minutes is free.
        for minute in stride(from: 600, through: 0, by: -1) {
            _ = await engine.snapshot(location: location, instant: start.addingTimeInterval(Double(minute) * 60))
        }
        #expect(await engine.snapshotComputations == 601)
    }

    /// Cost of one scrub step (new minute, day cached) and of a day change. The scrubber
    /// needs a step well under a 16.7 ms frame; a day change happens at most once per drag
    /// across midnight.
    @Test func scrubCost() async {
        let engine = PlannerEngine()
        let location = PillLocation.samples[0]
        let start = PlannerTests.instant("2026-06-21T00:00:00Z")
        let dayClock = ContinuousClock.now
        _ = await engine.snapshot(location: location, instant: start)
        let dayCost = ContinuousClock.now - dayClock
        let clock = ContinuousClock.now
        let steps = 1200
        for minute in 1...steps {
            _ = await engine.snapshot(location: location, instant: start.addingTimeInterval(Double(minute) * 60))
        }
        let elapsed = ContinuousClock.now - clock
        func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }
        let perStep = ms(elapsed) / Double(steps)
        Report.line(String(format: "Planner scrub step (debug build, Linux): %.3f ms per new minute; day change %.1f ms; frame 16.7 ms",
                           perStep, ms(dayCost)))
        #expect(perStep < 4)
    }
}

// MARK: - State

@MainActor
struct PlannerStateTests {
    static func session(_ iso: String, _ location: PillLocation = PillLocation.samples[0]) -> PillSession {
        let date = PlannerTests.instant(iso)
        return PillSession(defaults: nil, fallback: location) { date }
    }

    @Test func coalescesRapidScrubs() async {
        let engine = PlannerEngine()
        let state = PlannerState(session: Self.session("2026-06-21T12:00:00Z"), engine: engine)
        state.refresh()
        for _ in 0..<300 { state.scrub(minutes: 1) }
        await state.settle()
        #expect(state.snapshot?.instant == PlannerTests.instant("2026-06-21T17:00:00Z"))
        // At most the first request, one in flight and the latest: never all 300.
        #expect(await engine.snapshotComputations <= 3)
    }

    @Test func scrubBackDuringComputationKeepsLatestInstant() async {
        let state = PlannerState(session: Self.session("2026-06-21T12:00:00Z"))
        state.refresh()
        await state.settle()
        state.scrub(minutes: 1)
        await Task.yield()  // let the worker take the request and start computing
        state.scrub(minutes: -1)
        await state.settle()
        #expect(state.snapshot?.instant == PlannerTests.instant("2026-06-21T12:00:00Z"))
    }

    @Test func supersededLookupClearsTheResolvingBadge() async {
        let state = PlannerState(session: Self.session("2026-06-21T12:00:00Z"), lookup: { lat, _ in
            if lat > 50 { try? await Task.sleep(nanoseconds: 300_000_000) }
            return PlaceInfo(name: lat > 50 ? "Far" : "Near", timeZoneIdentifier: "Europe/Warsaw")
        })
        await state.movePin(latitude: 40, longitude: 20)  // resolved and cached
        let slow = Task { await state.movePin(latitude: 60, longitude: 20) }
        while !state.resolvingPin { await Task.yield() }
        await state.movePin(latitude: 40, longitude: 20)  // cache hit supersedes the slow lookup
        await slow.value
        #expect(!state.resolvingPin)
        #expect(state.session.location.name == "Near")
    }

    @Test func droppedPinResolvesNameAndZone() async {
        let state = PlannerState(session: Self.session("2026-06-21T12:00:00Z"), lookup: { lat, _ in
            lat < 0 ? PlaceInfo(name: "Taveuni", timeZoneIdentifier: "Pacific/Fiji") : nil
        })
        // Dragged past the antimeridian: longitude folds back into range.
        await state.movePin(latitude: -16.8, longitude: 180.2)
        await state.settle()
        #expect(state.session.location.name == "Taveuni")
        #expect(state.session.location.timeZoneIdentifier == "Pacific/Fiji")
        #expect(abs(state.session.location.longitude - -179.8) < 1e-9)
        #expect(state.session.recents.isEmpty)
        #expect(state.snapshot?.location == state.session.location)
        // Offline / over the sea: coordinates as the name, nautical zone.
        await state.movePin(latitude: 40, longitude: -140)
        #expect(state.session.location.name == "40.00000° N, 140.00000° W")
        #expect(state.session.timeZone.secondsFromGMT() == -9 * 3600)
    }

    @Test func pinMoveKeepsWallClock() async {
        let state = PlannerState(session: Self.session("2026-06-21T18:30:00Z"), lookup: { _, _ in
            PlaceInfo(name: "New York", timeZoneIdentifier: "America/New_York")
        })
        await state.movePin(latitude: 40.7, longitude: -74)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = state.session.timeZone
        let c = cal.dateComponents([.hour, .minute], from: state.session.instant)
        #expect(c.hour == 20 && c.minute == 30)
    }

    @Test func jumpUsesSnapshotDay() async {
        let state = PlannerState(session: Self.session("2026-06-21T18:30:00Z"))
        state.refresh()
        await state.settle()
        #expect(state.canJump(.sunset))
        #expect(state.jump(.sunset))
        await state.settle()
        let sunset = state.snapshot!.day.sunSets[0].time
        #expect(state.session.instant == sunset)
        let polar = PlannerState(session: Self.session("2026-06-21T12:00:00Z", PlannerTests.longyearbyen))
        polar.refresh()
        await polar.settle()
        #expect(!polar.canJump(.sunrise))
        #expect(!polar.jump(.sunrise))
    }
}
