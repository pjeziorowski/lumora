// Packages/PlannerKit/Sources/PlannerKit/MilkyWayReports.swift
//
// Data behind the Milky Way tool: the night of the selected date (core visibility windows,
// Moon interference, the core's path and arc orientation through the night) and the year
// at a glance (best nights and best months). A "night" runs from local noon on the date to
// local noon the next day, so one night's window is never split across two dates.

import AstroCore
import Foundation

/// The core at one moment of the night.
public struct GalacticCenterSample: Sendable, Hashable, Identifiable {
    public let time: Date
    public let azimuth: Double
    public let altitude: Double
    /// Angle of the band to the horizon at the core, degrees [0, 90].
    public let tilt: Double
    public var orientation: ArcOrientation { .of(tilt: tilt) }
    public var id: Date { time }
}

public struct MilkyWayNightReport: Sendable, Hashable {
    public let location: PillLocation
    /// The local date the night starts on.
    public let day: LocalDay
    public let start: Date
    public let end: Date
    public let windows: MilkyWayWindows
    /// Core every 15 minutes through the night.
    public let path: [GalacticCenterSample]
    /// Moon illumination at the middle of the night.
    public let moonIllumination: Double
    public let moonRises: [Date]
    public let moonSets: [Date]
    public let conditions: MilkyWayConditions

    public var visible: [DateInterval] { windows.visible.map(\.interval) }
    public var moonFree: [DateInterval] { windows.moonFree.map(\.interval) }
    public var dark: [DateInterval] { windows.dark.map(\.interval) }

    /// Highest point of the core while it is visible.
    public var bestMoment: GalacticCenterSample? {
        path.filter { s in visible.contains { $0.contains(s.time) } }.max { $0.altitude < $1.altitude }
    }

    /// Light-hearted rating for the night: share of the visible window free of the Moon.
    public var moonInterference: MoonInterference {
        let visibleSeconds = visible.reduce(0) { $0 + $1.duration }
        guard visibleSeconds > 0 else { return .notApplicable }
        let free = moonFree.reduce(0) { $0 + $1.duration } / visibleSeconds
        if free > 0.95 { return .none }
        if free > 0.5 { return .partial }
        return .severe
    }

    public static func compute(location: PillLocation, day: LocalDay, conditions: MilkyWayConditions = .standard) -> MilkyWayNightReport {
        let observer = location.observer
        let start = day.noon
        let end = day.adding(days: 1).noon
        let (t0, t1) = (AstroTime(start), AstroTime(end))
        let windows = MilkyWay.windows(observer: observer, from: t0, to: t1, conditions: conditions)
        var path: [GalacticCenterSample] = []
        var t = start
        while t <= end {
            let at = AstroTime(t)
            let h = MilkyWay.center(at: at, observer: observer)
            path.append(GalacticCenterSample(time: t, azimuth: h.azimuth, altitude: h.altitude,
                                             tilt: MilkyWay.arcTilt(at: at, observer: observer)))
            t = t.addingTimeInterval(900)
        }
        let moonEvents = Almanac.riseSetEvents(.moon, observer: observer, from: t0, to: t1)
        let mid = AstroTime(ut: (t0.ut + t1.ut) / 2)
        return MilkyWayNightReport(
            location: location, day: day, start: start, end: end, windows: windows, path: path,
            moonIllumination: Lunar.illumination(at: mid).fraction,
            moonRises: moonEvents.filter { $0.direction == .rise }.map(\.time.date),
            moonSets: moonEvents.filter { $0.direction == .set }.map(\.time.date),
            conditions: conditions)
    }
}

public enum MoonInterference: String, Sendable, Hashable, Codable {
    case none, partial, severe, notApplicable

    public var label: String {
        switch self {
        case .none: "No Moon"
        case .partial: "Moon part of the time"
        case .severe: "Moon most of the time"
        case .notApplicable: "Core not visible"
        }
    }
}

// MARK: - Year

public struct MilkyWayNightSummary: Sendable, Hashable, Identifiable {
    public let day: LocalDay
    /// Hours the core is up in a dark sky, and of those, hours free of the Moon.
    public let visibleHours: Double
    public let moonFreeHours: Double
    public let moonIllumination: Double
    public var id: String { "\(day.year)-\(day.month)-\(day.day)" }
}

public struct MilkyWayMonthSummary: Sendable, Hashable, Identifiable {
    public let month: Int
    public let moonFreeHours: Double
    public let visibleHours: Double
    /// Nights with at least one Moon-free hour.
    public let goodNights: Int
    public var id: Int { month }
}

public struct MilkyWayYearReport: Sendable, Hashable {
    public let year: Int
    public let nights: [MilkyWayNightSummary]

    /// Season: first and last night with any core visibility.
    public var seasonStart: LocalDay? { nights.first { $0.visibleHours > 0 }?.day }
    public var seasonEnd: LocalDay? { nights.last { $0.visibleHours > 0 }?.day }

    public var months: [MilkyWayMonthSummary] {
        (1...12).map { month in
            let list = nights.filter { $0.day.month == month }
            return MilkyWayMonthSummary(month: month,
                                        moonFreeHours: list.reduce(0) { $0 + $1.moonFreeHours },
                                        visibleHours: list.reduce(0) { $0 + $1.visibleHours },
                                        goodNights: list.filter { $0.moonFreeHours >= 1 }.count)
        }
    }

    /// Months ranked by Moon-free core hours, best first; months with none are left out.
    public var bestMonths: [MilkyWayMonthSummary] {
        months.filter { $0.moonFreeHours > 0 }.sorted { $0.moonFreeHours > $1.moonFreeHours }
    }

    /// The `count` nights with the most Moon-free core time, in date order.
    public func bestNights(_ count: Int = 10) -> [MilkyWayNightSummary] {
        let ranked = nights.filter { $0.moonFreeHours > 0 }.sorted { $0.moonFreeHours > $1.moonFreeHours }
        return ranked.prefix(count).sorted { $0.day.daysUntil($1.day) > 0 }
    }

    /// Scans every night of `year` on a 15-minute grid (durations are good to about ±15 min,
    /// enough to rank nights; the night view refines the edges).
    public static func compute(location: PillLocation, year: Int, conditions: MilkyWayConditions = .standard) -> MilkyWayYearReport {
        let observer = location.observer
        let zone = location.timeZone
        let step: TimeInterval = 900
        var nights: [MilkyWayNightSummary] = []
        for month in 1...12 {
            for day in LocalDay.days(inYear: year, month: month, timeZone: zone) {
                let start = day.noon, end = day.adding(days: 1).noon
                var visible = 0.0, moonFree = 0.0
                var t = start.addingTimeInterval(step / 2)
                while t < end {
                    let at = AstroTime(t)
                    let sun = Ephemeris.horizontal(.sun, at: at, observer: observer, refraction: .none).altitude
                    if sun < conditions.sunMaxAltitude,
                       MilkyWay.center(at: at, observer: observer).altitude > conditions.minimumCenterAltitude {
                        visible += step
                        let moonUp = Ephemeris.horizontal(.moon, at: at, observer: observer).altitude > 0
                        if !moonUp || Lunar.illumination(at: at).fraction < conditions.dimMoonIllumination {
                            moonFree += step
                        }
                    }
                    t = t.addingTimeInterval(step)
                }
                let mid = AstroTime(start.addingTimeInterval(end.timeIntervalSince(start) / 2))
                nights.append(MilkyWayNightSummary(day: day, visibleHours: visible / 3600, moonFreeHours: moonFree / 3600,
                                                   moonIllumination: Lunar.illumination(at: mid).fraction))
            }
        }
        return MilkyWayYearReport(year: year, nights: nights)
    }
}

extension ArcOrientation {
    public var label: String {
        switch self {
        case .horizontal: "Low arc along the horizon"
        case .diagonal: "Diagonal"
        case .vertical: "Upright"
        }
    }
}

extension TimeSpan {
    var interval: DateInterval { DateInterval(start: start.date, end: end.date) }
}
