// Packages/PlannerKit/Sources/PlannerKit/Planner/PlannerJump.swift
//
// The Planner's jump buttons. Each one moves the time to the next matching event of the
// pin's local day after the current instant, wrapping round to the day's first one, so
// tapping a button repeatedly cycles through e.g. both golden hours.

import Foundation

public enum PlannerJump: String, Sendable, Hashable, CaseIterable, Identifiable {
    case now, sunrise, sunset, goldenHour, blueHour, moonrise, moonset, milkyWayStart, milkyWayEnd
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .now: "Now"
        case .sunrise: "Sunrise"
        case .sunset: "Sunset"
        case .goldenHour: "Golden hour"
        case .blueHour: "Blue hour"
        case .moonrise: "Moonrise"
        case .moonset: "Moonset"
        case .milkyWayStart: "Milky Way from"
        case .milkyWayEnd: "Milky Way until"
        }
    }

    /// Candidate instants in the day, in time order. Golden and blue hours use span starts.
    public func candidates(in day: PlannerDay) -> [Date] {
        let list: [Date]
        switch self {
        case .now: list = []
        case .sunrise: list = day.sunRises.map(\.time)
        case .sunset: list = day.sunSets.map(\.time)
        case .goldenHour: list = day.twilight.goldenHours.map(\.start)
        case .blueHour: list = day.twilight.blueHours.map(\.start)
        case .moonrise: list = day.moonRises.map(\.time)
        case .moonset: list = day.moonSets.map(\.time)
        // Core windows that start or end inside this local day.
        case .milkyWayStart: list = day.milkyWay.visible.map(\.start.date).filter { $0 >= day.day.start && $0 < day.day.end }
        case .milkyWayEnd: list = day.milkyWay.visible.map(\.end.date).filter { $0 >= day.day.start && $0 < day.day.end }
        }
        return list.sorted()
    }

    /// The instant to jump to from `instant`, or nil when the day has no such event.
    /// `now` returns the clock's time.
    public func target(from instant: Date, day: PlannerDay, now: Date) -> Date? {
        if self == .now { return now }
        let list = candidates(in: day)
        // Ignore an event within 30 s of the current instant so a second tap moves on.
        return list.first { $0.timeIntervalSince(instant) > 30 } ?? list.first
    }
}
