// Packages/PlannerKit/Tests/PlannerKitTests/ReferenceSitesTests.swift
//
// Phase 2 acceptance: the Sun and Moon pill reports against published reference data for
// six places (five required), including polar day and polar night.
//
// Sources, all retrieved 2026-10-19:
// - U.S. Naval Observatory, "Sun and Moon Data for One Day" API
//   https://aa.usno.navy.mil/api/rstt/oneday?date=…&coords=…&tz=… . Times are local at the
//   given fixed UTC offset, rounded to the minute; USNO assumes a sea-level observer, so the
//   test observers have elevation 0.
// - USNO "Phases of the Moon" API https://aa.usno.navy.mil/api/moon/phases/year?year=2026 (UT).
// - timeanddate.com supermoon page (super = < 360,000 km, next super new/full moon)
//   https://www.timeanddate.com/astronomy/moon/super-full-moon.html
// - timeanddate.com blue moon page (seasonal blue moon 2019-05-18)
//   https://www.timeanddate.com/astronomy/moon/blue-moon.html

import AstroCore
import Foundation
import Testing
@testable import PlannerKit

struct ReferenceSitesTests {
    struct Case: CustomStringConvertible {
        let name: String
        let latitude: Double
        let longitude: Double
        let zone: String
        let date: (Int, Int, Int)
        /// UTC offset (hours) the USNO times are given in.
        let usnoOffset: Int
        let civilDawn: String?
        let sunrise: String?
        let solarNoon: String?
        let sunset: String?
        let civilDusk: String?
        let moonrise: String?
        let moonTransit: String?
        let moonset: String?
        let sunState: PolarState
        let moonState: PolarState
        /// USNO "fracillum", percent.
        let illuminationPercent: Double
        var description: String { name }
    }

    static let cases: [Case] = [
        // USNO oneday 2026-03-29, 52.2297,21.0122, tz=2 (the day Europe switches to summer time).
        Case(name: "Warsaw", latitude: 52.2297, longitude: 21.0122, zone: "Europe/Warsaw", date: (2026, 3, 29),
             usnoOffset: 2, civilDawn: "05:44", sunrise: "06:18", solarNoon: "12:41", sunset: "19:05",
             civilDusk: "19:39", moonrise: "14:51", moonTransit: "22:18", moonset: "05:11",
             sunState: .normal, moonState: .normal, illuminationPercent: 86),
        // USNO oneday 2026-07-04, 40.7128,-74.0060, tz=-4.
        Case(name: "New York", latitude: 40.7128, longitude: -74.0060, zone: "America/New_York", date: (2026, 7, 4),
             usnoOffset: -4, civilDawn: "04:57", sunrise: "05:30", solarNoon: "13:01", sunset: "20:30",
             civilDusk: "21:04", moonrise: "23:15", moonTransit: "04:18", moonset: "09:53",
             sunState: .normal, moonState: .normal, illuminationPercent: 81),
        // USNO oneday 2026-01-15, -33.8688,151.2093, tz=11.
        Case(name: "Sydney", latitude: -33.8688, longitude: 151.2093, zone: "Australia/Sydney", date: (2026, 1, 15),
             usnoOffset: 11, civilDawn: "05:31", sunrise: "05:59", solarNoon: "13:04", sunset: "20:09",
             civilDusk: "20:37", moonrise: "02:21", moonTransit: "09:54", moonset: "17:32",
             sunState: .normal, moonState: .normal, illuminationPercent: 13),
        // USNO oneday 2026-09-23, -0.1807,-78.4678, tz=-5.
        Case(name: "Quito", latitude: -0.1807, longitude: -78.4678, zone: "America/Guayaquil", date: (2026, 9, 23),
             usnoOffset: -5, civilDawn: "05:42", sunrise: "06:03", solarNoon: "12:06", sunset: "18:09",
             civilDusk: "18:30", moonrise: "15:59", moonTransit: "22:10", moonset: "03:36",
             sunState: .normal, moonState: .normal, illuminationPercent: 90),
        // USNO oneday 2026-06-10, 69.6492,18.9553, tz=2: Sun continuously above the horizon.
        Case(name: "Tromsø midnight sun", latitude: 69.6492, longitude: 18.9553, zone: "Europe/Oslo", date: (2026, 6, 10),
             usnoOffset: 2, civilDawn: nil, sunrise: nil, solarNoon: "12:44", sunset: nil,
             civilDusk: nil, moonrise: "00:53", moonTransit: "08:10", moonset: "16:15",
             sunState: .alwaysAbove, moonState: .normal, illuminationPercent: 29),
        // USNO oneday 2026-12-10, 69.6492,18.9553, tz=1: Sun and Moon continuously below the horizon;
        // civil twilight 09:15–13:59.
        Case(name: "Tromsø polar night", latitude: 69.6492, longitude: 18.9553, zone: "Europe/Oslo", date: (2026, 12, 10),
             usnoOffset: 1, civilDawn: "09:15", sunrise: nil, solarNoon: nil, sunset: nil,
             civilDusk: "13:59", moonrise: nil, moonTransit: nil, moonset: nil,
             sunState: .alwaysBelow, moonState: .alwaysBelow, illuminationPercent: 2),
        // USNO oneday 2026-06-21, -33.9249,18.4241, tz=2: no moonset that day.
        Case(name: "Cape Town", latitude: -33.9249, longitude: 18.4241, zone: "Africa/Johannesburg", date: (2026, 6, 21),
             usnoOffset: 2, civilDawn: "07:24", sunrise: "07:51", solarNoon: "12:48", sunset: "17:45",
             civilDusk: "18:13", moonrise: "12:26", moonTransit: "18:35", moonset: nil,
             sunState: .normal, moonState: .normal, illuminationPercent: 45),
    ]

    /// USNO local clock time on the case's date at its fixed offset → UTC instant.
    static func usno(_ hhmm: String, _ c: Case) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: c.usnoOffset * 3600)!
        return cal.date(from: DateComponents(year: c.date.0, month: c.date.1, day: c.date.2,
                                             hour: parts[0], minute: parts[1]))!
    }

    static func check(_ actual: [Date], _ expected: String?, _ label: String, _ c: Case, _ stats: inout ErrorStats) {
        guard let expected else {
            #expect(actual.isEmpty, "\(c.name) \(label): expected none, got \(actual)")
            return
        }
        guard actual.count == 1, let value = actual.first else {
            Issue.record("\(c.name) \(label): expected one event at \(expected), got \(actual)")
            return
        }
        let error = value.timeIntervalSince(usno(expected, c))
        stats.add(abs(error), "\(c.name) \(label)")
        // USNO rounds to the minute; target is ±1 min.
        #expect(abs(error) <= 60, "\(c.name) \(label) off by \(Int(error)) s")
    }

    @Test func sunAndMoonPillsMatchUSNO() {
        var sunStats = ErrorStats("Sun pill vs USNO, 6 places", unit: "s")
        var moonStats = ErrorStats("Moon pill vs USNO, 6 places", unit: "s")
        var illumStats = ErrorStats("Moon illumination vs USNO", unit: "%")
        for c in Self.cases {
            let location = PillLocation(name: c.name, latitude: c.latitude, longitude: c.longitude,
                                        elevation: 0, timeZoneIdentifier: c.zone)
            let day = LocalDay(year: c.date.0, month: c.date.1, day: c.date.2, timeZone: location.timeZone)
            let sun = SunDayReport.compute(location: location, day: day, instant: day.noon)
            let twilight = TwilightReport.compute(location: location, day: day)
            let moon = MoonDayReport.compute(location: location, day: day, instant: day.noon)

            #expect(sun.state == c.sunState, "\(c.name) sun state \(sun.state)")
            #expect(moon.state == c.moonState, "\(c.name) moon state \(moon.state)")
            Self.check(sun.rises.map(\.time), c.sunrise, "sunrise", c, &sunStats)
            Self.check(sun.sets.map(\.time), c.sunset, "sunset", c, &sunStats)
            Self.check(twilight.rows.first { $0.kind == .civil }!.morning, c.civilDawn, "civil dawn", c, &sunStats)
            Self.check(twilight.rows.first { $0.kind == .civil }!.evening, c.civilDusk, "civil dusk", c, &sunStats)
            if let noon = c.solarNoon {
                Self.check(sun.noon.map { [$0.time] } ?? [], noon, "solar noon", c, &sunStats)
            }
            Self.check(moon.rises.map(\.time), c.moonrise, "moonrise", c, &moonStats)
            Self.check(moon.sets.map(\.time), c.moonset, "moonset", c, &moonStats)
            if let transit = c.moonTransit {
                Self.check(moon.transit.map { [$0.time] } ?? [], transit, "moon transit", c, &moonStats)
            }
            // USNO's fracillum is a whole percent; allow rounding plus the ±1% target.
            let percent = moon.illumination * 100
            illumStats.add(abs(percent - c.illuminationPercent), c.name)
            #expect(abs(percent - c.illuminationPercent) <= 1.5, "\(c.name) illumination \(percent)%")
        }
        Report.line(sunStats)
        Report.line(moonStats)
        Report.line(illumStats)
        #expect(sunStats.count == 28)
        #expect(moonStats.count == 17)
    }

    /// The UI states for "no rise/set" come from the same reports.
    @Test func polarDaysExplainThemselves() {
        let tromso = PillLocation(name: "Tromsø", latitude: 69.6492, longitude: 18.9553, timeZoneIdentifier: "Europe/Oslo")
        let june = LocalDay(year: 2026, month: 6, day: 10, timeZone: tromso.timeZone)
        let summer = TwilightReport.compute(location: tromso, day: june)
        #expect(summer.darkness == .midnightSun)
        #expect(SunDayReport.compute(location: tromso, day: june, instant: june.noon).daylightSeconds == 86_400)

        let december = LocalDay(year: 2026, month: 12, day: 10, timeZone: tromso.timeZone)
        let winter = TwilightReport.compute(location: tromso, day: december)
        #expect(winter.darkness == .fullNight)
        #expect(winter.rows.first { $0.kind == .horizon }!.morning.isEmpty)
        #expect(!winter.isDarkAllDay)

        // Late May at 69.6° N: the Sun never gets below −6°, so nautical/astronomical rows are empty.
        let may = LocalDay(year: 2026, month: 5, day: 10, timeZone: tromso.timeZone)
        let white = TwilightReport.compute(location: tromso, day: may)
        #expect(white.darkness == .civilTwilightAllNight || white.darkness == .nauticalTwilightAllNight)
        #expect(white.rows.first { $0.kind == .astronomical }!.morning.isEmpty)
    }

    @Test func moonPhasesMatchUSNO2026() {
        // USNO phases API, 2026, UT to the minute: new and full moons only.
        let expected: [(MoonQuarter, String)] = [
            (.full, "2026-01-03 10:03"), (.new, "2026-01-18 19:52"), (.full, "2026-02-01 22:09"),
            (.new, "2026-02-17 12:01"), (.full, "2026-03-03 11:38"), (.new, "2026-03-19 01:23"),
            (.full, "2026-04-02 02:12"), (.new, "2026-04-17 11:52"), (.full, "2026-05-01 17:23"),
            (.new, "2026-05-16 20:01"), (.full, "2026-05-31 08:45"), (.new, "2026-06-15 02:54"),
            (.full, "2026-06-29 23:56"), (.new, "2026-07-14 09:43"), (.full, "2026-07-29 14:36"),
            (.new, "2026-08-12 17:37"), (.full, "2026-08-28 04:18"), (.new, "2026-09-11 03:27"),
            (.full, "2026-09-26 16:49"), (.new, "2026-10-10 15:50"), (.full, "2026-10-26 04:12"),
            (.new, "2026-11-09 07:02"), (.full, "2026-11-24 14:53"), (.new, "2026-12-09 00:52"),
            (.full, "2026-12-24 01:28"),
        ]
        let utc = PillLocation(name: "UTC", latitude: 0, longitude: 0, timeZoneIdentifier: "UTC")
        let year = LunarYear.compute(location: utc, year: 2026)
        let principal = year.phases.filter { $0.quarter == .new || $0.quarter == .full }
        #expect(principal.count == expected.count)
        var stats = ErrorStats("New/full moons 2026 vs USNO", unit: "s")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        for (event, (quarter, text)) in zip(principal, expected) {
            #expect(event.quarter == quarter)
            let error = event.time.timeIntervalSince(formatter.date(from: text)!)
            stats.add(abs(error), text)
            #expect(abs(error) <= 90, "\(text) off by \(Int(error)) s")
        }
        Report.line(stats)

        // timeanddate.com (page as of December 2025): "The next Super Full Moon is on December 24,
        // 2026 (UTC)" and "The next Super New Moon is on May 16, 2026 (UTC)".
        let supers = year.supermoons
        #expect(supers.first { $0.quarter == .full }.map { formatter.string(from: $0.time).prefix(10) } == "2026-12-24")
        #expect(supers.first { $0.quarter == .new }.map { formatter.string(from: $0.time).prefix(10) } == "2026-05-16")
    }

    @Test func blueMoons() {
        // 2026: full moons on 1 May and 31 May (USNO), so 31 May is a monthly blue moon in Warsaw…
        let warsaw = PillLocation.samples[0]
        let year = LunarYear.compute(location: warsaw, year: 2026)
        let monthly = year.phases.filter(\.isMonthlyBlueMoon)
        #expect(monthly.count == 1)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = warsaw.timeZone
        #expect(monthly.first.map { cal.component(.month, from: $0.time) } == 5)

        // …and in Kiritimati (UTC+14), where they fall on 2 May and 31 May local: still two in May.
        let kiritimati = PillLocation(name: "Kiritimati", latitude: 1.87, longitude: -157.4,
                                      timeZoneIdentifier: "Pacific/Kiritimati")
        #expect(LunarYear.compute(location: kiritimati, year: 2026).phases.filter(\.isMonthlyBlueMoon).count == 1)

        // timeanddate.com: 18 May 2019 was a seasonal blue moon (third of four full moons in spring).
        let seasonal = LunarYear.compute(location: warsaw, year: 2019).phases.filter(\.isSeasonalBlueMoon)
        #expect(seasonal.count == 1)
        cal.timeZone = TimeZone(identifier: "UTC")!
        #expect(seasonal.first.map { cal.dateComponents([.month, .day], from: $0.time) } == DateComponents(month: 5, day: 18))
    }
}
