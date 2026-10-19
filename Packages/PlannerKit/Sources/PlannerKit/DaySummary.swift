// Packages/PlannerKit/Sources/PlannerKit/DaySummary.swift
//
// Ready-to-display Sun and Moon summary for one local day at a location. Used by the
// Phase 0 home placeholder and, later, by the Sun/Moon pills and Planner panels.

import AstroCore
import Foundation

public struct SummaryRow: Sendable, Hashable, Identifiable {
    public let label: String
    public let value: String
    public var id: String { label }
}

public struct DaySummary: Sendable, Hashable {
    public let title: String
    public let rows: [SummaryRow]

    public init(title: String, rows: [SummaryRow]) {
        self.title = title
        self.rows = rows
    }

    /// Builds the summary off the main actor; ephemeris searches take a few milliseconds.
    public static func make(
        observer: Observer, day: LocalDay, clock: ClockStyle, now: Date = Date()
    ) async -> DaySummary {
        await Task.detached(priority: .userInitiated) {
            compute(observer: observer, day: day, clock: clock, now: now)
        }.value
    }

    public static func compute(observer: Observer, day: LocalDay, clock: ClockStyle, now: Date) -> DaySummary {
        let (start, end) = day.astroWindow
        let sun = Almanac.sunDay(observer: observer, from: start, to: end)
        let moon = Almanac.moonDay(observer: observer, from: start, to: end)
        let zone = day.timeZone

        func times(_ list: [AstroTime], none: String) -> String {
            list.isEmpty ? none : list.map { Formatting.clockTime($0.date, timeZone: zone, style: clock) }
                .joined(separator: ", ")
        }
        func noneLabel(_ state: PolarState, body: String) -> String {
            switch state {
            case .alwaysAbove: return "\(body) up all day"
            case .alwaysBelow: return "\(body) down all day"
            case .normal: return "—"
            }
        }

        let nowTime = AstroTime(now)
        let sunNow = Ephemeris.horizontal(.sun, at: nowTime, observer: observer)
        let moonNow = Ephemeris.horizontal(.moon, at: nowTime, observer: observer)
        let illum = Lunar.illumination(at: nowTime)
        let phase = Lunar.phaseName(at: nowTime)

        var rows = [
            SummaryRow(label: "Sunrise", value: times(sun.rises, none: noneLabel(sun.state, body: "Sun"))),
            SummaryRow(label: "Sunset", value: times(sun.sets, none: noneLabel(sun.state, body: "Sun"))),
            SummaryRow(label: "Daylight", value: Formatting.duration(seconds: sun.daylightDays * 86_400)),
            SummaryRow(label: "Civil dawn", value: times(sun.civil.dawn, none: "—")),
            SummaryRow(label: "Civil dusk", value: times(sun.civil.dusk, none: "—")),
        ]
        if let noon = sun.transit {
            rows.append(SummaryRow(label: "Solar noon",
                                   value: Formatting.clockTime(noon.time.date, timeZone: zone, style: clock)))
        }
        rows += [
            SummaryRow(label: "Sun now", value: "\(Formatting.azimuth(sunNow.azimuth)), el \(Formatting.degrees(sunNow.altitude))"),
            SummaryRow(label: "Moonrise", value: times(moon.rises, none: noneLabel(moon.state, body: "Moon"))),
            SummaryRow(label: "Moonset", value: times(moon.sets, none: noneLabel(moon.state, body: "Moon"))),
            SummaryRow(label: "Moon now", value: "\(Formatting.azimuth(moonNow.azimuth)), el \(Formatting.degrees(moonNow.altitude))"),
            SummaryRow(label: "Moon phase",
                       value: "\(phase.displayName), \(Int((illum.fraction * 100).rounded()))% lit"),
        ]
        let title = String(format: "%04d-%02d-%02d · %@", day.year, day.month, day.day,
                           Formatting.utcOffset(zone, at: day.start))
        return DaySummary(title: title, rows: rows)
    }
}

extension MoonPhaseName {
    public var displayName: String {
        switch self {
        case .new: return "New Moon"
        case .waxingCrescent: return "Waxing crescent"
        case .firstQuarter: return "First quarter"
        case .waxingGibbous: return "Waxing gibbous"
        case .full: return "Full Moon"
        case .waningGibbous: return "Waning gibbous"
        case .lastQuarter: return "Last quarter"
        case .waningCrescent: return "Waning crescent"
        }
    }
}
