// Packages/AstroCore/Tests/AstroCoreTests/MeteorShowerTests.swift
//
// Phase 9: solar longitude (J2000) and shower peak dates. The 2026 peak dates are from the
// IMO Meteor Shower Calendar 2026 (Quadrantids Jan 3, Lyrids Apr 22, Eta Aquariids May 6,
// Perseids Aug 12–13, Orionids Oct 21, Leonids Nov 17, Geminids Dec 14).

import Foundation
import Testing
@testable import AstroCore

struct MeteorShowerTests {
    @Test func solarLongitudeIsJ2000() throws {
        // At the March equinox the Sun is at 0° of the equinox of date; on the J2000 ecliptic
        // that is 26.2 years × 50.29″/yr of precession short of 360°: 359.634°.
        let seasons = try #require(Seasons.of(year: 2026))
        let lambda = SolarLongitude.j2000(at: seasons.marchEquinox)
        #expect(abs(lambda - 359.634) < 0.01)
        let back = try #require(SolarLongitude.search(lambda, after: seasons.marchEquinox.addingDays(-5)))
        #expect(abs(back.ut - seasons.marchEquinox.ut) * 86_400 < 2)
    }

    @Test func peakDates2026() throws {
        let expected = ["QUA": (1, 3), "LYR": (4, 22), "ETA": (5, 6), "PER": (8, 12), "ORI": (10, 21), "LEO": (11, 17),
                        "GEM": (12, 14)]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        for (code, (month, day)) in expected {
            let shower = try #require(MeteorShowers.shower(code: code))
            let peak = try #require(SolarLongitude.search(shower.peakSolarLongitude, after: AstroTime(year: 2026, month: 1, day: 1)))
            let parts = calendar.dateComponents([.month, .day, .hour], from: peak.date)
            // The IMO calendar names the night of the peak; allow the UT date either side of midnight.
            let target = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
            #expect(abs(peak.date.timeIntervalSince(target)) < 30 * 3600, "\(code) peak \(parts)")
        }
    }

    @Test func radiantDrifts() throws {
        let perseids = try #require(MeteorShowers.shower(code: "PER"))
        let atPeak = perseids.radiant(atSolarLongitude: 140)
        #expect(abs(atPeak.ra * 15 - 48) < 1e-9 && abs(atPeak.dec - 58) < 1e-9)
        // Ten days before the peak the radiant is 13.5° of RA further west.
        let earlier = perseids.radiant(atSolarLongitude: 130)
        #expect(abs(earlier.ra * 15 - 34.5) < 1e-9)
        // Quadrantids straddle the year end: λ☉ 280 is three days before the peak.
        let qua = try #require(MeteorShowers.shower(code: "QUA"))
        #expect(abs(qua.radiant(atSolarLongitude: 280.15).ra * 15 - (230 - 2.4)) < 1e-9)
    }
}
