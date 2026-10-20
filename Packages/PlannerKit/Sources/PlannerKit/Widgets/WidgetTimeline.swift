// Packages/PlannerKit/Sources/PlannerKit/Widgets/WidgetTimeline.swift
//
// When widget timeline entries fall: a regular step, plus one entry just after each event the
// widget names, so "next sunset 21:01" or a plan's countdown is never shown once it has passed.

import Foundation

public enum WidgetTimeline {
    /// How long one timeline lasts before WidgetKit asks for the next.
    public static let span: TimeInterval = 6 * 3600
    /// Gap after an event before the entry that drops it.
    static let afterEvent: TimeInterval = 1

    /// `start`, then every `step` up to `start + span`, plus each event in that span; sorted,
    /// without duplicates.
    public static func dates(from start: Date, step: TimeInterval, events: [Date] = [], span: TimeInterval = span) -> [Date] {
        let end = start.addingTimeInterval(span)
        var dates = Set(stride(from: 0, through: span, by: step).map { start.addingTimeInterval($0) })
        for event in events where event >= start && event < end {
            dates.insert(event.addingTimeInterval(afterEvent))
        }
        return dates.sorted()
    }

    /// The Sun widget's event times within the span: each "next" event, found again after the
    /// previous one passes (a snapshot lists only the soonest four).
    public static func sunEvents(location: PillLocation, from start: Date, span: TimeInterval = span) -> [Date] {
        let end = start.addingTimeInterval(span)
        var events: [Date] = []
        var instant = start
        for _ in 0..<16 {
            let upcoming = SunWidgetSnapshot.compute(location: location, instant: instant).upcoming.map(\.time)
            let inSpan = upcoming.filter { $0 < end }
            events.append(contentsOf: inSpan)
            guard inSpan.count == upcoming.count, let last = upcoming.last else { break }
            instant = last.addingTimeInterval(afterEvent)
        }
        return Array(Set(events)).sorted()
    }
}

extension MilkyWayWidgetSnapshot {
    /// The shown window has ended by `date`, so the next night must be computed.
    public func isStale(at date: Date) -> Bool {
        guard let window else { return false }
        return window.end <= date
    }
}
