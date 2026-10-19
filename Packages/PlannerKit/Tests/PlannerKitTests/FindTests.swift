// Packages/PlannerKit/Tests/PlannerKitTests/FindTests.swift
//
// Phase 6: Find reproduces a published alignment. Golden: American Museum of Natural
// History, "Manhattanhenge" (amnh.org/research/hayden-planetarium/manhattanhenge, 2026):
// the Sun sets along the street grid at azimuth 299.1° on
//   Thu 28 May 20:14 EDT (half sun on the grid), Fri 29 May 20:13 (full sun),
//   Sat 11 Jul 20:20 (full sun), Sun 12 Jul 20:21 (half sun).
// AMNH gives the altitude as "about half a degree"; at those four times the Sun stands
// between +0.35° and +0.92° (refracted), so the search uses 0.5° ± 0.5°: the disc on or
// just above the horizon while it shines down the street.

import AstroCore
import Foundation
import Testing
@testable import PlannerKit

struct FindTests {
    static let manhattan = PillLocation(name: "34th St", latitude: 40.7505, longitude: -73.9934, elevation: 0,
                                        timeZoneIdentifier: "America/New_York")

    static func edt(_ text: String) -> Date { PlannerTests.instant(text) }

    static func month(_ date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = manhattan.timeZone
        return cal.component(.month, from: date)
    }

    @Test func manhattanhenge() {
        let query = FindQuery(body: .sun, azimuth: 299.1, azimuthTolerance: 0.15, elevation: 0.5, elevationTolerance: 0.5,
                              start: Self.edt("2026-04-01T04:00:00Z"), end: Self.edt("2026-09-01T04:00:00Z"))
        let matches = BodyFinder.find(query, observer: Self.manhattan.observer)
        // Two windows of a few evenings each, one in late May and one in mid July.
        #expect(matches.allSatisfy { [5, 7].contains(Self.month($0.time)) })
        #expect((4...12).contains(matches.count), "\(matches.map(\.time))")
        for expected in ["2026-05-29T00:14:00Z", "2026-05-30T00:13:00Z", "2026-07-12T00:20:00Z", "2026-07-13T00:21:00Z"] {
            let target = Self.edt(expected)
            let found = matches.first { abs($0.time.timeIntervalSince(target)) < 6 * 3600 }
            #expect(found != nil, "no match near \(expected)")
            if let found {
                #expect(abs(found.time.timeIntervalSince(target)) < 120, "\(found.time) vs \(expected)")
                #expect(abs(found.azimuth - 299.1) < 0.15)
            }
        }
    }

    @Test func elevationOnlyAndMoon() {
        // The Sun at 10° in Warsaw: twice a day (morning and evening) for a week.
        let warsaw = PillLocation.samples[0]
        let start = Self.edt("2026-06-01T00:00:00Z")
        let q = FindQuery(body: .sun, azimuth: nil, elevation: 10, elevationTolerance: 0.1, start: start,
                          end: start.addingTimeInterval(7 * 86_400))
        let found = BodyFinder.find(q, observer: warsaw.observer)
        #expect(found.count == 14)
        for m in found { #expect(abs(m.elevation - 10) < 0.01) }
        // The Moon due east within a month: matches carry the illumination.
        let moon = BodyFinder.find(FindQuery(body: .moon, azimuth: 90, azimuthTolerance: 0.5, elevation: nil, start: start,
                                             end: start.addingTimeInterval(30 * 86_400)), observer: warsaw.observer)
        #expect(!moon.isEmpty)
        for m in moon { #expect(abs(BodyFinder.wrap(m.azimuth - 90)) < 0.01 && m.elevation > -0.8 && m.moonIllumination != nil) }
    }

    @Test func polarAndEmptyQueries() {
        let pole = PillLocation(name: "Pole", latitude: 89.99, longitude: 0, timeZoneIdentifier: "UTC")
        let start = Self.edt("2026-12-01T00:00:00Z")
        // Polar night: the Sun never reaches 5°.
        let none = BodyFinder.find(FindQuery(body: .sun, azimuth: nil, elevation: 5, elevationTolerance: 0.5, start: start,
                                             end: start.addingTimeInterval(10 * 86_400)), observer: pole.observer)
        #expect(none.isEmpty)
        #expect(BodyFinder.find(FindQuery(body: .sun, azimuth: nil, elevation: nil, start: start, end: start.addingTimeInterval(86_400)),
                                observer: pole.observer).isEmpty)
    }
}
