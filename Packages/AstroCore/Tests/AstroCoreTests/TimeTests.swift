// Packages/AstroCore/Tests/AstroCoreTests/TimeTests.swift

import Foundation
import Testing
@testable import AstroCore

struct TimeTests {
    @Test func j2000Epoch() {
        let t = AstroTime(year: 2000, month: 1, day: 1, hour: 12)
        #expect(abs(t.ut) < 1e-12)
        #expect(abs(t.julianDay - 2_451_545.0) < 1e-9)
        #expect(abs(t.date.timeIntervalSince1970 - 946_728_000) < 1e-3)
    }

    // Golden: Meeus, Astronomical Algorithms 2nd ed., Example 7.a — 1957 Oct 4.81 = JD 2436116.31.
    @Test func meeusExample7a() {
        let t = AstroTime(year: 1957, month: 10, day: 4, hour: 19, minute: 26, second: 24)
        #expect(abs(t.julianDay - 2_436_116.31) < 1e-6)
    }

    // Golden: Meeus Example 7.b: 333 Jan 27.5 (Julian calendar) is JD 1842713.0. The proleptic
    // Gregorian date is 333 Jan 28 (the calendars differ by 1 day in 300-500 AD). AstroCore is
    // proleptic Gregorian, like Astronomy Engine.
    @Test func prolepticGregorian() {
        let t = AstroTime(year: 333, month: 1, day: 28, hour: 12)
        #expect(abs(t.julianDay - 1_842_713.0) < 1e-6)
    }

    @Test func dateRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_760_000_000.25)
        let back = AstroTime(date).date
        #expect(abs(back.timeIntervalSince(date)) < 1e-4)
    }

    @Test func terrestrialTimeInverse() {
        for ut in [-36525.0, -10_000, 0, 9_500, 36525] {
            let t = AstroTime(ut: ut)
            let u = AstroTime(tt: t.tt)
            #expect(abs(u.ut - ut) < 1e-10)
        }
    }

    // Golden: ΔT from IERS/USNO observed values: 1900.0 ≈ −2.8 s, 2000.0 = 63.8 s, 2020.0 = 69.4 s
    // (https://maia.usno.navy.mil/ser7/deltat.data). Espenak–Meeus is a fit; after 2005 it is an
    // extrapolation that runs ~2 s high by 2020 (and ~5 s by 2025). A 5 s ΔT error moves the Moon
    // by ~2.5" and does not affect rise/set times, which depend on UT.
    @Test func deltaTMatchesObserved() {
        #expect(abs(AstroTime(year: 1900, month: 1, day: 1).deltaT - -2.8) < 1.5)
        #expect(abs(AstroTime(year: 2000, month: 1, day: 1).deltaT - 63.8) < 1.5)
        #expect(abs(AstroTime(year: 2020, month: 1, day: 1).deltaT - 69.4) < 3.0)
        // 2100 is extrapolated (≈ 203 s in the Espenak–Meeus model); just check it is sane.
        let dt2100 = AstroTime(year: 2100, month: 1, day: 1).deltaT
        #expect(dt2100 > 150 && dt2100 < 260)
    }

    // Golden: Meeus Example 12.a — 1987 Apr 10 0h UT: mean sidereal time 13h10m46.3668s,
    // apparent 13h10m46.1351s.
    @Test func siderealTimeMeeus12a() {
        let t = AstroTime(year: 1987, month: 4, day: 10)
        let gast = SiderealTime.greenwichApparent(t)
        let expected = 13.0 + 10.0 / 60 + 46.1351 / 3600
        #expect(abs(gast - expected) * 3600 < 0.1)
    }
}
