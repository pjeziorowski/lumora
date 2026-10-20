// Packages/PlannerKit/Sources/PlannerKit/LocalDay.swift
//
// The calendar day at the pin: [local midnight, next local midnight) in the pin's time zone,
// expressed as UTC instants for AstroCore. Handles 23 h / 25 h DST days and zones on either
// side of the dateline.

import AstroCore
import Foundation

public struct LocalDay: Sendable, Hashable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let timeZone: TimeZone

    public init(year: Int, month: Int, day: Int, timeZone: TimeZone) {
        self.year = year
        self.month = month
        self.day = day
        self.timeZone = timeZone
    }

    /// The local calendar day containing `date` in `timeZone`.
    public init(containing date: Date, timeZone: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 2000, month: c.month ?? 1, day: c.day ?? 1, timeZone: timeZone)
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    /// Local midnight at the start of the day. Where a DST jump skips midnight, the first
    /// instant of the day.
    public var start: Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!)
    }

    public var end: Date {
        calendar.date(byAdding: .day, value: 1, to: start)!
    }

    /// Length of the local day in hours: 24, or 23 / 25 on DST transition days.
    public var lengthHours: Double { end.timeIntervalSince(start) / 3600 }

    public var astroWindow: (start: AstroTime, end: AstroTime) {
        (AstroTime(start), AstroTime(end))
    }
}
