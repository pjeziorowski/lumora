// Packages/PlannerKit/Sources/PlannerKit/MoonReports.swift
//
// Data behind the Moon pill: day summary, month phase calendar and the year's list of
// new/full moons with supermoon, micromoon and blue-moon flags. Pure values; run `compute`
// off the main actor.

import AstroCore
import Foundation

/// Distance thresholds for "supermoon" and "micromoon". There is no official definition;
/// the defaults follow timeanddate.com (centre-to-centre distance at the instant of the
/// new or full moon): super < 360,000 km, micro > 405,000 km.
/// Source: https://www.timeanddate.com/astronomy/moon/super-full-moon.html (retrieved 2026-10-19).
public struct SupermoonRule: Sendable, Hashable, Codable {
    public var superBelowKm = 360_000.0
    public var microAboveKm = 405_000.0
    public init() {}
    public static let standard = SupermoonRule()
}

public enum MoonSize: String, Sendable, Codable {
    case supermoon, micromoon, regular

    public static func classify(distanceKm: Double, rule: SupermoonRule = .standard) -> MoonSize {
        if distanceKm < rule.superBelowKm { return .supermoon }
        if distanceKm > rule.microAboveKm { return .micromoon }
        return .regular
    }
}

/// A principal phase (new, first quarter, full, last quarter) with display flags.
public struct LunarPhaseEvent: Sendable, Hashable, Identifiable {
    public let quarter: MoonQuarter
    public let time: Date
    /// Geocentric distance at the instant of the phase.
    public let distanceKm: Double
    /// Only meaningful for new and full moons; quarters are always `.regular`.
    public let size: MoonSize
    /// Second full moon in a calendar month (in the pin's time zone).
    public let isMonthlyBlueMoon: Bool
    /// Third full moon of an astronomical season that has four.
    public let isSeasonalBlueMoon: Bool
    public var id: Date { time }
}

// MARK: - Day summary

public struct MoonDayReport: Sendable, Hashable {
    public let location: PillLocation
    public let day: LocalDay
    public let rises: [SkyEvent]
    public let sets: [SkyEvent]
    /// Upper culmination with the Moon's elevation then.
    public let transit: SkyEvent?
    public let state: PolarState
    /// The Moon at the selected instant (geocentric distance).
    public let position: SkyPosition
    /// Apparent angular diameter in degrees at the selected instant (geocentric).
    public let angularDiameter: Double
    /// Illuminated fraction [0, 1].
    public let illumination: Double
    /// Moon–Sun ecliptic longitude difference [0, 360): 0 new, 90 first quarter, 180 full.
    public let elongation: Double
    public let phaseName: MoonPhaseName
    /// Days since the last new moon.
    public let ageDays: Double
    /// The next four principal phases after the selected instant.
    public let upcoming: [LunarPhaseEvent]

    public var nextFull: LunarPhaseEvent? { upcoming.first { $0.quarter == .full } }
    public var nextNew: LunarPhaseEvent? { upcoming.first { $0.quarter == .new } }

    public static func compute(
        location: PillLocation, day: LocalDay, instant: Date, rule: SupermoonRule = .standard
    ) -> MoonDayReport {
        let observer = location.observer
        let (start, end) = day.astroWindow
        let events = Almanac.riseSetEvents(.moon, observer: observer, from: start, to: end)
        let t = AstroTime(instant)
        let h = Ephemeris.horizontal(.moon, at: t, observer: observer)
        let illum = Lunar.illumination(at: t)
        let elongation = Lunar.phaseAngle(at: t)

        var upcoming: [LunarPhaseEvent] = []
        var cursor = t
        while upcoming.count < 4, let q = Lunar.nextQuarter(after: cursor) {
            let distance = Lunar.distanceKm(at: q.time)
            let principal = q.quarter == .new || q.quarter == .full
            upcoming.append(LunarPhaseEvent(
                quarter: q.quarter, time: q.time.date, distanceKm: distance,
                size: principal ? MoonSize.classify(distanceKm: distance, rule: rule) : .regular,
                isMonthlyBlueMoon: false, isSeasonalBlueMoon: false))
            cursor = q.time.addingDays(1)
        }

        return MoonDayReport(
            location: location,
            day: day,
            rises: events.filter { $0.direction == .rise }.map { SkyEvent.at($0.time, .moon, observer) },
            sets: events.filter { $0.direction == .set }.map { SkyEvent.at($0.time, .moon, observer) },
            transit: Almanac.transit(.moon, observer: observer, from: start, to: end).map {
                SkyEvent(time: $0.time.date, azimuth: $0.horizontal.azimuth, altitude: $0.horizontal.altitude)
            },
            state: polarState(.moon, observer: observer, events: events, start: start, end: end),
            position: SkyPosition(time: instant, azimuth: h.azimuth, altitude: h.altitude, distanceKm: illum.distanceKm),
            angularDiameter: 2 * asin(AstroConstants.moonMeanRadiusKm / illum.distanceKm) * 180 / .pi,
            illumination: illum.fraction,
            elongation: elongation,
            phaseName: Lunar.phaseName(forPhaseAngle: elongation),
            ageDays: Lunar.age(at: t),
            upcoming: upcoming
        )
    }
}

// MARK: - Phase calendar

public struct MoonCalendarDay: Sendable, Hashable, Identifiable {
    public let day: LocalDay
    /// Elongation at local noon, for drawing the disc.
    public let elongation: Double
    /// Illuminated fraction at local noon.
    public let illumination: Double
    public let phaseName: MoonPhaseName
    /// A principal phase that happens during this local day, if any.
    public let phaseEvent: MoonQuarterEvent?
    public var id: Int { day.day }
}

public struct MoonCalendarMonth: Sendable, Hashable {
    public let year: Int
    public let month: Int
    public let days: [MoonCalendarDay]

    /// Empty cells before day 1 in a week grid starting on `firstWeekday` (1 = Sunday, 2 = Monday…).
    public func leadingBlanks(firstWeekday: Int) -> Int {
        guard let first = days.first else { return 0 }
        return (first.day.weekday - firstWeekday + 7) % 7
    }

    public static func compute(location: PillLocation, year: Int, month: Int) -> MoonCalendarMonth {
        let days = LocalDay.days(inYear: year, month: month, timeZone: location.timeZone)
        guard let first = days.first, let last = days.last else {
            return MoonCalendarMonth(year: year, month: month, days: [])
        }
        let quarters = Lunar.quarters(from: first.astroWindow.start, to: last.astroWindow.end)
        let entries = days.map { day -> MoonCalendarDay in
            let noon = AstroTime(day.noon)
            let elongation = Lunar.phaseAngle(at: noon)
            let (start, end) = day.astroWindow
            return MoonCalendarDay(
                day: day,
                elongation: elongation,
                illumination: Lunar.illumination(at: noon).fraction,
                phaseName: Lunar.phaseName(forPhaseAngle: elongation),
                phaseEvent: quarters.first { $0.time >= start && $0.time < end }
            )
        }
        return MoonCalendarMonth(year: year, month: month, days: entries)
    }
}

// MARK: - Year list

public struct LunarYear: Sendable, Hashable {
    public let year: Int
    /// Every principal phase whose local date falls in `year`, in time order.
    public let phases: [LunarPhaseEvent]
    /// Perigees and apogees in the year.
    public let apsides: [LunarApsis]

    public var fullMoons: [LunarPhaseEvent] { phases.filter { $0.quarter == .full } }
    public var newMoons: [LunarPhaseEvent] { phases.filter { $0.quarter == .new } }
    public var supermoons: [LunarPhaseEvent] { phases.filter { $0.size == .supermoon } }
    public var blueMoons: [LunarPhaseEvent] { phases.filter { $0.isMonthlyBlueMoon || $0.isSeasonalBlueMoon } }

    public static func compute(location: PillLocation, year: Int, rule: SupermoonRule = .standard) -> LunarYear {
        let zone = location.timeZone
        let start = AstroTime(LocalDay(year: year, month: 1, day: 1, timeZone: zone).start)
        let end = AstroTime(LocalDay(year: year + 1, month: 1, day: 1, timeZone: zone).start)
        let quarters = Lunar.quarters(from: start, to: end)

        // Monthly blue moons: count full moons per local calendar month.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        var fullsPerMonth: [Int: Int] = [:]
        var monthlyBlue: Set<Double> = []
        for q in quarters where q.quarter == .full {
            let month = cal.component(.month, from: q.time.date)
            fullsPerMonth[month, default: 0] += 1
            if fullsPerMonth[month] == 2 { monthlyBlue.insert(q.time.ut) }
        }

        let seasonalBlue = seasonalBlueMoons(aroundYear: year)

        let phases = quarters.map { q -> LunarPhaseEvent in
            let distance = Lunar.distanceKm(at: q.time)
            let principal = q.quarter == .new || q.quarter == .full
            return LunarPhaseEvent(
                quarter: q.quarter, time: q.time.date, distanceKm: distance,
                size: principal ? MoonSize.classify(distanceKm: distance, rule: rule) : .regular,
                isMonthlyBlueMoon: monthlyBlue.contains(q.time.ut),
                isSeasonalBlueMoon: q.quarter == .full && seasonalBlue.contains { abs($0.ut - q.time.ut) < 1e-6 })
        }
        return LunarYear(year: year, phases: phases, apsides: Lunar.apsides(from: start, to: end))
    }

    /// Third full moon of each season (equinox/solstice to the next) holding four,
    /// for every season overlapping `year`.
    static func seasonalBlueMoons(aroundYear year: Int) -> [AstroTime] {
        var boundaries: [AstroTime] = []
        for y in (year - 1)...(year + 1) {
            guard let s = Seasons.of(year: y) else { continue }
            boundaries += [s.marchEquinox, s.juneSolstice, s.septemberEquinox, s.decemberSolstice]
        }
        guard let first = boundaries.first, let last = boundaries.last else { return [] }
        let fulls = Lunar.quarters(from: first, to: last).filter { $0.quarter == .full }.map(\.time)
        var result: [AstroTime] = []
        for (a, b) in zip(boundaries, boundaries.dropFirst()) {
            let inSeason = fulls.filter { $0 >= a && $0 < b }
            if inSeason.count == 4 { result.append(inSeason[2]) }
        }
        return result
    }
}
