// Packages/PlannerKit/Tests/PlannerKitTests/DaySummaryTests.swift

import AstroCore
import Foundation
import Testing
@testable import PlannerKit

struct DaySummaryTests {
    // Golden: Skyfield + DE421 (AstroCore Golden/cities.json): Warsaw 2025-06-21 sunrise
    // 02:14:25Z = 04:14 CEST, sunset 19:01:09Z = 21:01 CEST, daylight 16h 46m 44s.
    @Test func warsawSummerSolstice() async {
        let day = LocalDay(year: 2025, month: 6, day: 21, timeZone: TimeZone(identifier: "Europe/Warsaw")!)
        let summary = await DaySummary.make(observer: Observer(latitude: 52.2297, longitude: 21.0122),
                                            day: day, clock: .twentyFourHour,
                                            now: Date(timeIntervalSince1970: 1_750_500_000))
        let values = Dictionary(uniqueKeysWithValues: summary.rows.map { ($0.label, $0.value) })
        #expect(values["Sunrise"] == "04:14")
        #expect(values["Sunset"] == "21:01")
        #expect(values["Daylight"] == "16h 47m")
        #expect(summary.title == "2025-06-21 · UTC+2")
    }

    // Polar night in Tromsø: no sunrise row value, explicit label instead.
    @Test func tromsoPolarNight() {
        let day = LocalDay(year: 2025, month: 12, day: 21, timeZone: TimeZone(identifier: "Europe/Oslo")!)
        let summary = DaySummary.compute(observer: Observer(latitude: 69.6492, longitude: 18.9553),
                                         day: day, clock: .twentyFourHour,
                                         now: Date(timeIntervalSince1970: 1_766_318_400))
        let values = Dictionary(uniqueKeysWithValues: summary.rows.map { ($0.label, $0.value) })
        #expect(values["Sunrise"] == "Sun down all day")
        #expect(values["Daylight"] == "0s")
    }
}
