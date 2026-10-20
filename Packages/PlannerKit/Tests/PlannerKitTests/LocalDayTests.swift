// Packages/PlannerKit/Tests/PlannerKitTests/LocalDayTests.swift

import AstroCore
import Foundation
import Testing
@testable import PlannerKit

struct LocalDayTests {
    @Test func dstDaysAre23And25Hours() {
        let warsaw = TimeZone(identifier: "Europe/Warsaw")!
        #expect(LocalDay(year: 2025, month: 3, day: 30, timeZone: warsaw).lengthHours == 23)
        #expect(LocalDay(year: 2025, month: 10, day: 26, timeZone: warsaw).lengthHours == 25)
        #expect(LocalDay(year: 2025, month: 6, day: 21, timeZone: warsaw).lengthHours == 24)
        // Southern hemisphere: Sydney springs forward on the first Sunday of October.
        let sydney = TimeZone(identifier: "Australia/Sydney")!
        #expect(LocalDay(year: 2025, month: 10, day: 5, timeZone: sydney).lengthHours == 23)
        #expect(LocalDay(year: 2025, month: 4, day: 6, timeZone: sydney).lengthHours == 25)
    }

    // Kiritimati (UTC+14) and Pago Pago (UTC-11) share wall-clock time but are a day apart.
    @Test func datelineZones() {
        let kiritimati = TimeZone(identifier: "Pacific/Kiritimati")!
        let pagoPago = TimeZone(identifier: "Pacific/Pago_Pago")!
        let instant = Date(timeIntervalSince1970: 1_750_500_000)  // 2025-06-21T10:00:00Z
        let a = LocalDay(containing: instant, timeZone: kiritimati)
        let b = LocalDay(containing: instant, timeZone: pagoPago)
        #expect(a.day == 22)
        #expect(b.day == 20)
        // Kiritimati 2025-06-22 00:00 (+14) = 06-21 10:00Z; Pago Pago 06-20 00:00 (-11) = 06-20 11:00Z.
        #expect(a.start.timeIntervalSince(b.start) == 23 * 3600)
    }

    @Test func astroWindowFeedsTheAlmanac() {
        let warsaw = TimeZone(identifier: "Europe/Warsaw")!
        let day = LocalDay(year: 2025, month: 3, day: 30, timeZone: warsaw)
        let (start, end) = day.astroWindow
        let sun = Almanac.sunDay(observer: Observer(latitude: 52.2297, longitude: 21.0122), from: start, to: end)
        #expect(sun.rises.count == 1 && sun.sets.count == 1)
        // Spot check sunrise is shown in local time after the 02:00→03:00 jump.
        let label = Formatting.clockTime(sun.rises[0].date, timeZone: warsaw, style: .twentyFourHour)
        #expect(label.hasPrefix("05:") || label.hasPrefix("06:"))
    }
}
