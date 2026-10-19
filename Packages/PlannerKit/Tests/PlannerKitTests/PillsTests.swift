// Packages/PlannerKit/Tests/PlannerKitTests/PillsTests.swift
//
// Behaviour of the Phase 2 pill models: coordinate parsing, the shared session, month
// tables, seasons, phase calendar and sky paths. Reference-site accuracy is in
// ReferenceSitesTests.swift.

import AstroCore
import Foundation
import Testing
@testable import PlannerKit

struct CoordinateParserTests {
    @Test(arguments: [
        ("52.2297, 21.0122", 52.2297, 21.0122),
        ("-33.8688 151.2093", -33.8688, 151.2093),
        ("52.2297N 21.0122E", 52.2297, 21.0122),
        ("33.8688 S, 151.2093 E", -33.8688, 151.2093),
        ("N 52.2297 W 21.0122", 52.2297, -21.0122),
        ("21.0122E 52.2297N", 52.2297, 21.0122),
        ("52°13'46.9\"N 21°00'43.9\"E", 52.229694, 21.012194),
        ("52 13 46.9 N, 21 0 43.9 E", 52.229694, 21.012194),
        ("0°10'50.5\"S 78°28'4.1\"W", -0.180694, -78.467806),
        ("-0 10.842, -78 28.068", -0.1807, -78.4678),
    ])
    func parses(text: String, latitude: Double, longitude: Double) throws {
        let result = try #require(CoordinateParser.parse(text))
        #expect(abs(result.latitude - latitude) < 1e-5)
        #expect(abs(result.longitude - longitude) < 1e-5)
    }

    @Test(arguments: ["", "Warsaw", "52.2", "91, 10", "10, 181", "52 61 0 N 21 0 0 E", "52N 21N", "1 2 3"])
    func rejects(text: String) {
        #expect(CoordinateParser.parse(text) == nil)
    }

    @Test func nauticalZoneFallback() {
        #expect(PillLocation.nauticalTimeZone(longitude: 21).secondsFromGMT() == 3600)
        #expect(PillLocation.nauticalTimeZone(longitude: -74).secondsFromGMT() == -5 * 3600)
        #expect(PillLocation.nauticalTimeZone(longitude: 179.9).secondsFromGMT() == 12 * 3600)
        let unknown = PillLocation(name: "Sea", latitude: 0, longitude: -150, timeZoneIdentifier: "Not/AZone")
        #expect(unknown.timeZone.secondsFromGMT() == -10 * 3600)
    }
}

@MainActor
struct PillSessionTests {
    static let warsaw = PillLocation.samples[0]
    static let sydney = PillLocation.samples[2]

    @Test func shiftingDaysKeepsWallTimeAcrossDST() {
        // 2026-03-28 21:00 CET; Europe springs forward early on 29 March.
        let start = Date(timeIntervalSince1970: 1_774_728_000)
        let session = PillSession(defaults: nil, fallback: Self.warsaw) { start }
        session.shift(days: 1)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.warsaw.timeZone
        let c = cal.dateComponents([.day, .hour], from: session.instant)
        #expect(c.day == 29 && c.hour == 21)
        #expect(session.instant.timeIntervalSince(start) == 23 * 3600)
        #expect(!session.isToday)
        session.resetToNow()
        #expect(session.isToday)
    }

    @Test func selectingAPlaceKeepsTheLocalDateAndRemembersIt() throws {
        let suite = "PillSessionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // 2026-06-21 10:00 CEST.
        let start = Date(timeIntervalSince1970: 1_782_028_800)
        let session = PillSession(defaults: defaults, fallback: Self.warsaw) { start }
        session.select(Self.sydney)
        #expect(session.day == LocalDay(year: 2026, month: 6, day: 21, timeZone: Self.sydney.timeZone))
        session.select(Self.warsaw)
        session.select(Self.sydney)
        #expect(session.recents.map(\.name) == ["Sydney", "Warsaw"])

        let restored = PillSession(defaults: defaults) { start }
        #expect(restored.location == Self.sydney)
        #expect(restored.recents.count == 2)
    }
}

struct SunPillTests {
    @Test func warsawJuneMonthTable() {
        let table = SunMonthTable.compute(location: PillLocation.samples[0], year: 2026, month: 6)
        #expect(table.rows.count == 30)
        #expect(table.rows.allSatisfy { $0.rises.count == 1 && $0.sets.count == 1 && $0.state == .normal })
        // Solstice is 21 June 2026 08:24 UT (USNO); the longest day is within a day of it
        // (daylight changes by < 1 s/day there, so neighbours can tie to the second).
        #expect((20...22).contains(table.longestDay ?? 0))
        #expect(table.shortestDay == 1 || table.shortestDay == 30)
    }

    @Test func tromsoMonthTableShowsPolarDays() {
        let table = SunMonthTable.compute(location: PillLocation.samples[4], year: 2026, month: 11)
        #expect(table.rows.count == 30)
        let dark = table.rows.filter { $0.state == .alwaysBelow }.map(\.day.day)
        #expect(dark.contains(30))
        #expect(!dark.contains(1))
        #expect(table.rows.first { $0.day.day == 30 }?.daylightSeconds == 0)
        #expect(table.rows.first { $0.day.day == 1 }.map { $0.rises.count == 1 && $0.sets.count == 1 } == true)
    }

    @Test func seasonsFlipInTheSouth() throws {
        let north = try #require(SeasonsReport.compute(location: PillLocation.samples[0], year: 2026))
        let south = try #require(SeasonsReport.compute(location: PillLocation.samples[2], year: 2026))
        #expect(north.events.map(\.begins) == [.spring, .summer, .autumn, .winter])
        #expect(south.events.map(\.begins) == [.autumn, .winter, .spring, .summer])
        // USNO Earth's Seasons 2026: June solstice 21 June 08:24 UT.
        let june = north.events[1].time
        #expect(abs(june.timeIntervalSince(Date(timeIntervalSince1970: 1_782_030_240))) < 90)
        // Longer daylight in the summer hemisphere.
        #expect(north.events[1].daylightSeconds > 16 * 3600)
        #expect(south.events[1].daylightSeconds < 10 * 3600)
        #expect(north.midnightSun == nil && south.polarNight == nil)
    }

    @Test func tromsoPolarPeriods() throws {
        let report = try #require(SeasonsReport.compute(location: PillLocation.samples[4], year: 2026))
        let sun = try #require(report.midnightSun)
        let night = try #require(report.polarNight)
        // Sanity range for 69.6° N (upper-limb rule, 34' refraction): mid/late May to late July,
        // late November to mid January.
        #expect(sun.first.month == 5 && (15...25).contains(sun.first.day))
        #expect(sun.last.month == 7 && (20...30).contains(sun.last.day))
        #expect(night.first.month == 11 && (24...30).contains(night.first.day))
        #expect(night.last.year == 2027 && night.last.month == 1 && (10...18).contains(night.last.day))
        #expect(sun.days > 60 && night.days > 40)
    }

    @Test func goldenAndBlueHoursSplitIntoMorningAndEvening() {
        let warsaw = PillLocation.samples[0]
        let day = LocalDay(year: 2026, month: 10, day: 19, timeZone: warsaw.timeZone)
        let report = TwilightReport.compute(location: warsaw, day: day)
        #expect(report.morningGoldenHours.count == 1 && report.eveningGoldenHours.count == 1)
        #expect(report.morningBlueHours.count == 1 && report.eveningBlueHours.count == 1)
        #expect(report.darkness == .fullNight)
        // Blue hour ends where golden hour begins (−4°).
        if let blue = report.morningBlueHours.first, let golden = report.morningGoldenHours.first {
            #expect(abs(blue.end.timeIntervalSince(golden.start)) < 1)
        }
    }

    @Test func lightPhases() {
        #expect(LightPhase.of(sunAltitude: 30) == .day)
        #expect(LightPhase.of(sunAltitude: 2) == .goldenHour)
        #expect(LightPhase.of(sunAltitude: -5) == .blueHour)
        #expect(LightPhase.of(sunAltitude: -10) == .nauticalTwilight)
        #expect(LightPhase.of(sunAltitude: -15) == .astronomicalTwilight)
        #expect(LightPhase.of(sunAltitude: -40) == .night)
    }

    @Test func skyPathCoversTheLocalDay() {
        let warsaw = PillLocation.samples[0]
        let normal = SkyPath.compute(.sun, location: warsaw, day: LocalDay(year: 2026, month: 6, day: 21, timeZone: warsaw.timeZone))
        #expect(normal.samples.count == 289)
        // 29 March 2026 is 23 hours long in Warsaw.
        let dst = SkyPath.compute(.sun, location: warsaw, day: LocalDay(year: 2026, month: 3, day: 29, timeZone: warsaw.timeZone))
        #expect(dst.samples.count == 277)
        // Noon elevation on the solstice: 90 − 52.23 + 23.44 ≈ 61.2°.
        #expect(abs((normal.highest?.altitude ?? 0) - 61.2) < 0.2)
    }

    @Test func shadowRatio() {
        let warsaw = PillLocation.samples[0]
        let day = LocalDay(year: 2026, month: 6, day: 21, timeZone: warsaw.timeZone)
        let report = SunDayReport.compute(location: warsaw, day: day, instant: day.noon)
        #expect(report.shadowRatio != nil)
        let midnight = SunDayReport.compute(location: warsaw, day: day, instant: day.start)
        #expect(midnight.shadowRatio == nil)
        // At 52.2° N the solstice Sun only sinks to about −14.3°: astronomical twilight all night.
        #expect(midnight.lightPhase == .astronomicalTwilight)
        // Earth–Sun distance in late June is near aphelion: ~152.0 million km.
        #expect(abs(report.position.distanceKm - 152.0e6) < 0.2e6)
    }
}

struct MoonPillTests {
    @Test func february2026Calendar() {
        let warsaw = PillLocation.samples[0]
        let month = MoonCalendarMonth.compute(location: warsaw, year: 2026, month: 2)
        #expect(month.days.count == 28)
        // 1 Feb 2026 is a Sunday: no blanks for a Sunday-first week, six for Monday-first.
        #expect(month.leadingBlanks(firstWeekday: 1) == 0)
        #expect(month.leadingBlanks(firstWeekday: 2) == 6)
        // USNO 2026: full moon 1 Feb 22:09 UT (23:09 in Warsaw), new moon 17 Feb 12:01 UT,
        // last quarter 9 Feb, first quarter 24 Feb.
        let events = month.days.compactMap { day in day.phaseEvent.map { (day.day.day, $0.quarter) } }
        #expect(events.map(\.0) == [1, 9, 17, 24])
        #expect(events.map(\.1) == [.full, .lastQuarter, .new, .firstQuarter])
        #expect(month.days[0].illumination > 0.99)
        #expect(month.days[16].illumination < 0.01)
    }

    @Test func dayReportLooksAhead() {
        let warsaw = PillLocation.samples[0]
        let day = LocalDay(year: 2026, month: 12, day: 20, timeZone: warsaw.timeZone)
        let report = MoonDayReport.compute(location: warsaw, day: day, instant: day.noon)
        #expect(report.upcoming.count == 4)
        // USNO: full moon 24 Dec 2026 01:28 UT; timeanddate lists it as a supermoon.
        #expect(report.nextFull?.size == .supermoon)
        #expect(abs((report.nextFull?.time.timeIntervalSince1970 ?? 0) - 1_798_075_680) < 90)
        // Angular diameter between the apogee and perigee extremes (29.3′–34.1′).
        #expect((0.488...0.569).contains(report.angularDiameter))
        #expect(report.ageDays > 11 && report.ageDays < 12)
        #expect(report.phaseName == .waxingGibbous)
    }

    @Test func supermoonRule() {
        #expect(MoonSize.classify(distanceKm: 356_728) == .supermoon)
        #expect(MoonSize.classify(distanceKm: 360_753) == .regular)
        #expect(MoonSize.classify(distanceKm: 406_126) == .micromoon)
        var rule = SupermoonRule()
        rule.superBelowKm = 362_000
        #expect(MoonSize.classify(distanceKm: 360_753, rule: rule) == .supermoon)
    }
}
