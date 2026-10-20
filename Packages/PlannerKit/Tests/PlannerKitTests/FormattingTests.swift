// Packages/PlannerKit/Tests/PlannerKitTests/FormattingTests.swift

import Foundation
import Testing
@testable import PlannerKit

struct FormattingTests {
    @Test func compassPoints() {
        #expect(Formatting.compassPoint(azimuth: 0) == "N")
        #expect(Formatting.compassPoint(azimuth: 11.24) == "N")
        #expect(Formatting.compassPoint(azimuth: 11.26) == "NNE")
        #expect(Formatting.compassPoint(azimuth: 135) == "SE")
        #expect(Formatting.compassPoint(azimuth: 359) == "N")
        #expect(Formatting.compassPoint(azimuth: -90) == "W")
        #expect(Formatting.azimuth(301.26) == "301.3° WNW")
    }

    // Golden: Warsaw Palace of Culture 52.231944° N, 21.006389° E = 52°13'55.0" N, 21°00'23.0" E.
    @Test func coordinates() {
        #expect(Formatting.coordinate(latitude: 52.2297, longitude: 21.0122, style: .decimal)
            == "52.22970° N, 21.01220° E")
        #expect(Formatting.coordinate(latitude: 52.231944, longitude: 21.006389, style: .degreesMinutesSeconds)
            == "52°13'55.0\" N, 021°00'23.0\" E")
        #expect(Formatting.coordinate(latitude: -33.8688, longitude: -0.0001, style: .decimal)
            == "33.86880° S, 0.00010° W")
        // 59.99" must carry, not print 60.0".
        #expect(Formatting.coordinate(latitude: 10.0 + 59.0 / 60 + 59.99 / 3600, longitude: 0,
                                      style: .degreesMinutesSeconds).hasPrefix("11°00'00.0\""))
    }

    @Test func distances() {
        #expect(Formatting.distance(meters: 350, units: .metric) == "350 m")
        #expect(Formatting.distance(meters: 1234, units: .metric) == "1.23 km")
        #expect(Formatting.distance(meters: 25_400, units: .metric) == "25.4 km")
        #expect(Formatting.distance(meters: 100, units: .imperial) == "328 ft")
        #expect(Formatting.distance(meters: 1609.344, units: .imperial) == "1.00 mi")
        #expect(Formatting.height(meters: 2850, units: .imperial) == "9350 ft")
    }

    @Test func durations() {
        #expect(Formatting.duration(seconds: 12 * 3600 + 7 * 60 + 20) == "12h 07m")
        #expect(Formatting.duration(seconds: 45 * 60 + 10) == "45m 10s")
        #expect(Formatting.duration(seconds: 8.4) == "8s")
        #expect(Formatting.duration(seconds: -90) == "-1m 30s")
        #expect(Formatting.duration(seconds: 16 * 3600 + 46 * 60 + 44) == "16h 47m")
        #expect(Formatting.duration(seconds: 3599.6) == "1h 00m")
    }

    @Test func clockTimesUseThePinTimeZone() {
        // 2025-06-21T02:14:25Z is Warsaw sunrise; 04:14 local (CEST, UTC+2).
        let sunrise = Date(timeIntervalSince1970: 1_750_472_065)
        let warsaw = TimeZone(identifier: "Europe/Warsaw")!
        let honolulu = TimeZone(identifier: "Pacific/Honolulu")!
        #expect(Formatting.clockTime(sunrise, timeZone: warsaw, style: .twentyFourHour) == "04:14")
        #expect(Formatting.clockTime(sunrise, timeZone: warsaw, style: .twelveHour) == "4:14 AM")
        #expect(Formatting.clockTime(sunrise, timeZone: honolulu, style: .twelveHour) == "4:14 PM")
        #expect(Formatting.utcOffset(warsaw, at: sunrise) == "UTC+2")
        #expect(Formatting.utcOffset(TimeZone(identifier: "Australia/Adelaide")!, at: sunrise) == "UTC+9:30")
        #expect(Formatting.utcOffset(honolulu, at: sunrise) == "UTC-10")
    }

    @Test func roundingToMinuteCarriesIntoHour() {
        let utc = TimeZone(identifier: "UTC")!
        let t = Date(timeIntervalSince1970: 3600 * 23 + 59 * 60 + 45)  // 23:59:45
        #expect(Formatting.clockTime(t, timeZone: utc, style: .twentyFourHour) == "00:00")
    }
}
