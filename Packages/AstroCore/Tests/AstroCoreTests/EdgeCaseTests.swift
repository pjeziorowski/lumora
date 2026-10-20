// Packages/AstroCore/Tests/AstroCoreTests/EdgeCaseTests.swift
//
// Edge cases called out in the brief: dateline, DST transitions, southern hemisphere,
// polar regions and the 1900–2100 validity range. Polar and southern-hemisphere rise/set
// accuracy is also covered by CityGoldenTests (Tromsø, Sydney, Quito) and USNOTests
// (USNO tables at 89° N, 88° S, 60° S, 45° S, 61° S).

import Foundation
import Testing
@testable import AstroCore

struct EdgeCaseTests {
    private func utcDay(_ y: Int, _ m: Int, _ d: Int) -> (AstroTime, AstroTime) {
        let start = AstroTime(year: y, month: m, day: d)
        return (start, start.addingDays(1))
    }

    private func localDay(_ zone: String, _ y: Int, _ m: Int, _ d: Int) -> (AstroTime, AstroTime) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        let start = cal.date(from: DateComponents(year: y, month: m, day: d))!
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return (AstroTime(start), AstroTime(end))
    }

    // Longitudes ±179.9999° are 22 m apart; events must agree to well under a second.
    @Test func datelineContinuity() {
        let (start, end) = utcDay(2025, 6, 21)
        let east = Observer(latitude: -16.5, longitude: 179.9999)
        let west = Observer(latitude: -16.5, longitude: -179.9999)
        for body in Body.allCases {
            let a = Almanac.riseSetEvents(body, observer: east, from: start, to: end)
            let b = Almanac.riseSetEvents(body, observer: west, from: start, to: end)
            #expect(a.count == b.count)
            for (x, y) in zip(a, b) {
                #expect(x.direction == y.direction)
                #expect(abs(x.time.ut - y.time.ut) * 86_400 < 1)
            }
        }
        let t = AstroTime(year: 2025, month: 6, day: 21, hour: 3)
        let he = Ephemeris.horizontal(.sun, at: t, observer: east)
        let hw = Ephemeris.horizontal(.sun, at: t, observer: west)
        #expect(angleDiff(he.azimuth, hw.azimuth) < 0.001)
        #expect(abs(he.altitude - hw.altitude) < 0.001)
    }

    // Warsaw's local day is 23 h on 2025-03-30 (CET→CEST) and 25 h on 2025-10-26.
    @Test func dstTransitionDays() {
        let warsaw = Observer(latitude: 52.2297, longitude: 21.0122)
        for (m, d, hours) in [(3, 30, 23.0), (10, 26, 25.0)] {
            let (start, end) = localDay("Europe/Warsaw", 2025, m, d)
            #expect(abs((end.ut - start.ut) * 24 - hours) < 1e-6)
            let day = Almanac.sunDay(observer: warsaw, from: start, to: end)
            #expect(day.rises.count == 1)
            #expect(day.sets.count == 1)
            #expect(day.goldenHours.count == 2)
            #expect(day.blueHours.count == 2)
        }
    }

    // Southern hemisphere: Sydney's longest day is in December, shortest in June.
    @Test func southernHemisphereSeasonsFlip() {
        let sydney = Observer(latitude: -33.8688, longitude: 151.2093)
        let (ds, de) = localDay("Australia/Sydney", 2025, 12, 21)
        let (js, je) = localDay("Australia/Sydney", 2025, 6, 21)
        let dec = Almanac.sunDay(observer: sydney, from: ds, to: de).daylightDays * 24
        let jun = Almanac.sunDay(observer: sydney, from: js, to: je).daylightDays * 24
        #expect(dec > 14.3 && dec < 14.6)
        #expect(jun > 9.8 && jun < 10.0)
        // Sun culminates due north from Sydney in June.
        let noon = Almanac.transit(.sun, observer: sydney, from: js, to: je)
        #expect(noon != nil)
        if let noon { #expect(angleDiff(noon.horizontal.azimuth, 0) < 1) }
    }

    // North Pole: Sun up all day at the June solstice, down in December, regardless of window.
    @Test func northPole() {
        let pole = Observer(latitude: 90, longitude: 0)
        let (js, je) = utcDay(2026, 6, 21)
        let (ds, de) = utcDay(2026, 12, 21)
        #expect(Almanac.sunDay(observer: pole, from: js, to: je).state == .alwaysAbove)
        #expect(Almanac.sunDay(observer: pole, from: ds, to: de).state == .alwaysBelow)
        #expect(RiseSet.search(.sun, observer: pole, direction: .rise, start: js, limitDays: 30) == nil)
    }

    // Golden hour spans in midnight-sun conditions wrap the window edges and stay inside it.
    @Test func goldenHourBandsAreClippedAndOrdered() {
        let tromso = Observer(latitude: 69.6492, longitude: 18.9553)
        let (start, end) = localDay("Europe/Oslo", 2025, 6, 21)
        let day = Almanac.sunDay(observer: tromso, from: start, to: end)
        for span in day.goldenHours + day.blueHours {
            #expect(span.start >= start && span.end <= end && span.start < span.end)
        }
        #expect(day.blueHours.isEmpty)  // Sun never goes below +3° that night
    }

    // Validity range: ephemeris and searches work at both ends of 1900–2100.
    @Test func validityRange1900to2100() {
        #expect(Seasons.of(year: 1900) != nil)
        #expect(Seasons.of(year: 2100) != nil)
        let warsaw = Observer(latitude: 52.2297, longitude: 21.0122)
        for (y, m, d) in [(1900, 1, 1), (2100, 12, 31)] {
            let (start, end) = utcDay(y, m, d)
            let day = Almanac.sunDay(observer: warsaw, from: start, to: end)
            #expect(day.rises.count == 1 && day.sets.count == 1)
            let moon = Almanac.moonDay(observer: warsaw, from: start.addingDays(-1), to: end.addingDays(1))
            #expect(moon.rises.count >= 2 && moon.sets.count >= 2)
            #expect(!Lunar.age(at: start).isNaN)
        }
    }

    // Golden: Golden/apsides.json (Skyfield + DE421). Apsis instants are ill-conditioned because
    // the distance curve is flat there, so time tolerance is 30 min. The truncated lunar series
    // is good to ~50 km in distance, so allow 75 km (supermoon thresholds are ~15,000 km wide).
    @Test func lunarApsides() throws {
        struct File: Decodable { let rows: [Row] }
        struct Row: Decodable { let kind: String; let utc: String; let distanceKm: Double }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: Golden.url("apsides", "json")))
        let found = Lunar.apsides(from: AstroTime(year: 2025, month: 1, day: 1), to: AstroTime(year: 2027, month: 1, day: 1))
        #expect(found.count == file.rows.count)
        var timeStats = ErrorStats("Lunar apsis time vs DE421", unit: "min")
        var distStats = ErrorStats("Lunar apsis distance vs DE421", unit: "km")
        for (row, apsis) in zip(file.rows, found) {
            #expect((row.kind == "perigee") == (apsis.kind == .perigee))
            let dt = abs(apsis.time.ut - Golden.time(row.utc).ut) * 1440
            let dd = abs(apsis.distanceKm - row.distanceKm)
            timeStats.add(dt, row.utc)
            distStats.add(dd, row.utc)
            #expect(dt < 30, "\(row.utc): apsis off by \(dt) min")
            #expect(dd < 75, "\(row.utc): distance off by \(dd) km")
        }
        Report.line(timeStats)
        Report.line(distStats)
    }

    @Test func moonPhaseNames() {
        #expect(Lunar.phaseName(forPhaseAngle: 0) == .new)
        #expect(Lunar.phaseName(forPhaseAngle: 45) == .waxingCrescent)
        #expect(Lunar.phaseName(forPhaseAngle: 90) == .firstQuarter)
        #expect(Lunar.phaseName(forPhaseAngle: 135) == .waxingGibbous)
        #expect(Lunar.phaseName(forPhaseAngle: 180) == .full)
        #expect(Lunar.phaseName(forPhaseAngle: 225) == .waningGibbous)
        #expect(Lunar.phaseName(forPhaseAngle: 270) == .lastQuarter)
        #expect(Lunar.phaseName(forPhaseAngle: 315) == .waningCrescent)
        #expect(Lunar.phaseName(forPhaseAngle: 359) == .new)
    }

    // Golden: Meeus, Astronomical Algorithms 2nd ed., eq. 16.4 (Saemundsson) gives 28.9' for a true
    // altitude of 0°, which corresponds to the classic 34' at an *apparent* altitude of 0° (eq. 16.3).
    // Rise/set does not use this formula; it uses the USNO fixed 34' (see RiseSet.search).
    @Test func refraction() {
        let r0 = Ephemeris.refractionAngle(.normal, altitude: 0) * 60
        #expect(abs(r0 - 28.9) < 0.2)
        let apparentZero = Ephemeris.inverseRefractionAngle(.normal, bentAltitude: 0) * 60
        #expect(abs(apparentZero + 34) < 1.5)
        #expect(Ephemeris.refractionAngle(.none, altitude: 0) == 0)
        for alt in [-0.5, 0.0, 5.0, 30.0, 80.0] {
            let bent = alt + Ephemeris.refractionAngle(.normal, altitude: alt)
            let back = bent + Ephemeris.inverseRefractionAngle(.normal, bentAltitude: bent)
            #expect(abs(back - alt) < 1e-9)
        }
    }
}
