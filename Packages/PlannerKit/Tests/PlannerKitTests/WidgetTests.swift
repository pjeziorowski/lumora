// Packages/PlannerKit/Tests/PlannerKitTests/WidgetTests.swift
//
// Phase 10: widget snapshots give the right next events and round-trip through the shared
// store. Times are checked against the Sun and Moon reports the pills use, so a widget never
// disagrees with the app.

import Foundation
import Testing
@testable import PlannerKit

struct WidgetTests {
    let warsaw = PillLocation.samples.first { $0.name == "Warsaw" }!
    let sydney = PillLocation.samples.first { $0.name == "Sydney" }!
    let longyearbyen = PillLocation.samples.first { $0.name == "Longyearbyen" }!
    func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test func sunEventsAfterTheInstant() throws {
        // 21 June 2026, 20:30 Warsaw: golden hour under way, sunset next, then the blue hour ends.
        let instant = utc("2026-06-21T18:30:00Z")
        let sun = SunWidgetSnapshot.compute(location: warsaw, instant: instant)
        #expect(sun.lightPhase == .goldenHour && sun.current != nil)
        let next = try #require(sun.next)
        let report = SunDayReport.compute(location: warsaw, day: LocalDay(containing: instant, timeZone: warsaw.timeZone),
                                          instant: instant)
        #expect(next.kind == .sunset && next.time == report.sets.first?.time)
        #expect(sun.upcoming.map(\.time) == sun.upcoming.map(\.time).sorted())
        #expect(sun.upcoming.allSatisfy { $0.time > instant })
        #expect(sun.upcoming.contains { $0.kind == .blueHourEnd })
    }

    @Test func midnightSunHasNoSunset() {
        let sun = SunWidgetSnapshot.compute(location: longyearbyen, instant: utc("2026-06-21T12:00:00Z"))
        #expect(!sun.upcoming.contains { $0.kind == .sunset || $0.kind == .sunrise })
    }

    @Test func moonPhaseAndRiseSet() {
        // 12 Aug 2026 is a new Moon (the day of the solar eclipse).
        let moon = MoonWidgetSnapshot.compute(location: warsaw, instant: utc("2026-08-12T10:00:00Z"))
        #expect(moon.illumination < 0.02 && moon.phaseName == .new)
        #expect(moon.upcoming.first.map { $0.kind == .moonset || $0.kind == .moonrise } == true)
        let south = MoonWidgetSnapshot.compute(location: sydney, instant: utc("2026-08-12T10:00:00Z"))
        #expect(south.isSouthern && !moon.isSouthern)
    }

    @Test func milkyWayTonightOrNext() throws {
        // New York, 14 July 2026 at 23:30 EDT: the core is up now.
        let newYork = PillLocation.samples.first { $0.name == "New York" }!
        let summer = MilkyWayWidgetSnapshot.compute(location: newYork, instant: utc("2026-07-15T03:30:00Z"))
        #expect(summer.isTonight)
        let window = try #require(summer.window)
        #expect(window.end > utc("2026-07-15T03:30:00Z"))
        // In December the core is lost in the twilight at New York's latitude: no window
        // within the search, so the widget says so instead of naming a night.
        let winter = MilkyWayWidgetSnapshot.compute(location: newYork, instant: utc("2026-12-15T03:00:00Z"), searchNights: 7)
        #expect(winter.window == nil && !winter.isTonight)
        // The timeline computes the window again only once the shown one has ended.
        #expect(!summer.isStale(at: summer.instant) && summer.isStale(at: window.end))
        #expect(!winter.isStale(at: utc("2027-01-01T00:00:00Z")))
    }

    @Test func timelineHasAnEntryAfterEachEvent() throws {
        // 21 June 2026, 20:30 Warsaw: sunset 21:01, then the blue hour and twilight within 6 h.
        let start = utc("2026-06-21T18:30:00Z")
        let events = WidgetTimeline.sunEvents(location: warsaw, from: start)
        let sunset = try #require(SunWidgetSnapshot.compute(location: warsaw, instant: start).next)
        #expect(sunset.kind == .sunset && events.first == sunset.time)
        #expect(events == events.sorted() && events.allSatisfy { $0 >= start && $0 < start.addingTimeInterval(6 * 3600) })
        // Past the snapshot's soonest four: the next morning's events follow within the span.
        let fromEvening = WidgetTimeline.sunEvents(location: warsaw, from: start, span: 12 * 3600)
        #expect(fromEvening.count > 4 && fromEvening.contains { $0 > utc("2026-06-22T00:00:00Z") })
        let dates = WidgetTimeline.dates(from: start, step: 1800, events: events)
        #expect(dates.first == start && dates.last == start.addingTimeInterval(6 * 3600))
        #expect(dates.count == 13 + events.count && dates == dates.sorted())
        #expect(dates.contains(sunset.time.addingTimeInterval(1)))
        // An event outside the span adds nothing; one on a step adds a separate entry after it.
        #expect(WidgetTimeline.dates(from: start, step: 1800, events: [start.addingTimeInterval(7 * 3600)]).count == 13)
        #expect(WidgetTimeline.dates(from: start, step: 300, events: [start.addingTimeInterval(600)]).count == 74)
    }

    @Test func storeRoundTripsAndPicksTheNextPlan() throws {
        let defaults = try #require(UserDefaults(suiteName: "WidgetTests-\(UUID().uuidString)"))
        let now = utc("2026-06-21T12:00:00Z")
        let past = Plan(name: "Done", location: warsaw, instant: utc("2026-06-20T19:00:00Z"))
        let soon = Plan(name: "Sunset over the Vistula", location: warsaw, instant: utc("2026-06-21T19:00:00Z"))
        let later = Plan(name: "Harbour bridge", location: sydney, instant: utc("2026-07-01T08:00:00Z"))
        WidgetStore.save(plans: [later, past, soon].map(WidgetPlan.init), now: now, to: defaults)
        WidgetStore.save(location: sydney, clock: .twelveHour, to: defaults)
        let plans = WidgetStore.plans(in: defaults)
        #expect(plans.map(\.name) == ["Sunset over the Vistula", "Harbour bridge"])
        #expect(WidgetPlan.next(plans, after: now)?.name == "Sunset over the Vistula")
        #expect(plans[0].light == "Golden hour" && plans[1].timeZone.identifier == "Australia/Sydney")
        #expect(WidgetStore.location(in: defaults) == sydney && WidgetStore.clock(in: defaults) == .twelveHour)
        #expect(WidgetStore.plans(in: nil).isEmpty && WidgetStore.location(in: nil) == nil)
    }
}
