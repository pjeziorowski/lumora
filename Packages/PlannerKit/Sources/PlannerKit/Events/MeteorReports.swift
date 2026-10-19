// Packages/PlannerKit/Sources/PlannerKit/Events/MeteorReports.swift
//
// Meteor showers for a place: the year's showers with their peak night and how good it is
// there, and the night of a shower hour by hour (radiant height, darkness, Moon, expected
// rate). Catalogue and positions come from AstroCore.
//
// Expected hourly rate (IMO): HR = ZHR × sin(radiant elevation) / r^(6.5 − LM), counted
// only while the Sun is below −12°. The limiting magnitude LM starts at 6.5 under a dark sky
// and is reduced by twilight (to 4.0 at −12°) and by a Moon above the horizon (up to 2
// magnitudes for a full Moon high in the sky). The sky-brightness terms are a planning
// heuristic, not an IMO formula.

import AstroCore
import Foundation

public enum MeteorConditions {
    public static func limitingMagnitude(sunAltitude: Double, moonAltitude: Double, moonIllumination: Double) -> Double {
        var lm = 6.5
        if sunAltitude > -18 { lm -= 2.5 * min(1, (sunAltitude + 18) / 6) }
        if moonAltitude > 0 { lm -= 2 * moonIllumination * min(1, sin(moonAltitude * .pi / 180) * 2) }
        return max(0, lm)
    }

    public static func hourlyRate(zhr: Double, populationIndex r: Double, radiantAltitude: Double, limitingMagnitude lm: Double) -> Double {
        guard radiantAltitude > 0 else { return 0 }
        return zhr * sin(radiantAltitude * .pi / 180) / pow(r, 6.5 - lm)
    }
}

public enum MeteorRating: String, Sendable, Hashable, Codable, Comparable {
    case poor, fair, good, excellent

    public var label: String {
        switch self {
        case .poor: "Poor"
        case .fair: "Fair"
        case .good: "Good"
        case .excellent: "Excellent"
        }
    }

    static func of(rate: Double) -> MeteorRating {
        switch rate {
        case 40...: .excellent
        case 15..<40: .good
        case 5..<15: .fair
        default: .poor
        }
    }

    private var order: Int { [.poor, .fair, .good, .excellent].firstIndex(of: self) ?? 0 }
    public static func < (a: MeteorRating, b: MeteorRating) -> Bool { a.order < b.order }
}

public struct MeteorSample: Sendable, Hashable, Identifiable {
    public let time: Date
    public let radiantAzimuth: Double
    public let radiantAltitude: Double
    public let sunAltitude: Double
    public let moonAltitude: Double
    public let limitingMagnitude: Double
    /// Expected meteors per hour for one observer.
    public let rate: Double
    public var id: Date { time }
}

public struct MeteorNightReport: Sendable, Hashable {
    public let shower: MeteorShower
    public let location: PillLocation
    /// The local date the night starts on.
    public let day: LocalDay
    /// Every 15 minutes from local noon to the next noon.
    public let samples: [MeteorSample]
    public let moonIllumination: Double

    public var best: MeteorSample? { samples.filter { $0.rate > 0 }.max { $0.rate < $1.rate } }
    public var rating: MeteorRating { MeteorRating.of(rate: best?.rate ?? 0) }
    /// When the radiant is above the horizon while the sky is dark (Sun below −12°).
    public var usefulHours: Double { Double(samples.filter { $0.rate > 0 }.count) / 4 }

    public static func compute(shower: MeteorShower, location: PillLocation, day: LocalDay) -> MeteorNightReport {
        let observer = location.observer
        var samples: [MeteorSample] = []
        let start = day.noon
        let end = day.adding(days: 1).noon
        var t = start
        let middle = AstroTime(start.addingTimeInterval(end.timeIntervalSince(start) / 2))
        let illumination = Lunar.illumination(at: middle).fraction
        while t <= end {
            let time = AstroTime(t)
            let radiant = FixedSky.horizontal(shower.radiant(atSolarLongitude: SolarLongitude.j2000(at: time)), at: time,
                                              observer: observer)
            let sun = Ephemeris.horizontal(.sun, at: time, observer: observer).altitude
            let moon = Ephemeris.horizontal(.moon, at: time, observer: observer).altitude
            let lm = MeteorConditions.limitingMagnitude(sunAltitude: sun, moonAltitude: moon, moonIllumination: illumination)
            let rate = sun < -12
                ? MeteorConditions.hourlyRate(zhr: shower.zhr, populationIndex: shower.populationIndex,
                                              radiantAltitude: radiant.altitude, limitingMagnitude: lm)
                : 0
            samples.append(MeteorSample(time: t, radiantAzimuth: radiant.azimuth, radiantAltitude: radiant.altitude,
                                        sunAltitude: sun, moonAltitude: moon, limitingMagnitude: lm, rate: rate))
            t = t.addingTimeInterval(900)
        }
        return MeteorNightReport(shower: shower, location: location, day: day, samples: samples, moonIllumination: illumination)
    }
}

public struct MeteorShowerSummary: Sendable, Hashable, Identifiable {
    public let shower: MeteorShower
    public let peak: Date
    public let active: DateInterval
    /// The night around the peak at this place.
    public let peakNight: MeteorNightReport
    public var id: String { shower.code }
}

public enum MeteorShowerCalendar {
    /// The night (local date it starts on) that contains `instant`.
    public static func night(containing instant: Date, timeZone: TimeZone) -> LocalDay {
        let day = LocalDay(containing: instant, timeZone: timeZone)
        return instant < day.noon ? day.adding(days: -1) : day
    }

    /// Activity window of a shower around the peak that falls in `year`.
    static func activeWindow(_ shower: MeteorShower, peak: Date, timeZone: TimeZone) -> DateInterval {
        let peakDay = LocalDay(containing: peak, timeZone: timeZone)
        // The window wraps the year end when it begins in a later month than it ends.
        let wraps = shower.begins.month > shower.ends.month
        let beginYear = wraps && peakDay.month <= shower.ends.month ? peakDay.year - 1 : peakDay.year
        let endYear = wraps && peakDay.month >= shower.begins.month ? peakDay.year + 1 : peakDay.year
        let begin = LocalDay(year: beginYear, month: shower.begins.month, day: shower.begins.day, timeZone: timeZone)
        let end = LocalDay(year: endYear, month: shower.ends.month, day: shower.ends.day, timeZone: timeZone)
        return DateInterval(start: begin.start, end: max(begin.start, end.end))
    }

    /// Every catalogued shower peaking in `year`, in date order, rated for `location`.
    public static func year(_ year: Int, location: PillLocation) -> [MeteorShowerSummary] {
        let zone = location.timeZone
        let start = AstroTime(LocalDay(year: year, month: 1, day: 1, timeZone: zone).start)
        return MeteorShowers.all.compactMap { shower -> MeteorShowerSummary? in
            guard let peak = SolarLongitude.search(shower.peakSolarLongitude, after: start, limitDays: 366)?.date,
                  LocalDay(containing: peak, timeZone: zone).year == year else { return nil }
            let night = MeteorNightReport.compute(shower: shower, location: location,
                                                  day: night(containing: peak, timeZone: zone))
            return MeteorShowerSummary(shower: shower, peak: peak, active: activeWindow(shower, peak: peak, timeZone: zone),
                                       peakNight: night)
        }
        .sorted { $0.peak < $1.peak }
    }

    /// Showers active at `instant`, strongest first.
    public static func active(at instant: Date, timeZone: TimeZone) -> [(shower: MeteorShower, peak: Date)] {
        let time = AstroTime(instant)
        return MeteorShowers.all.compactMap { shower -> (MeteorShower, Date)? in
            // The peak nearest to the instant: search from half a year before.
            guard let peak = SolarLongitude.search(shower.peakSolarLongitude, after: time.addingDays(-183), limitDays: 366)?.date
            else { return nil }
            return activeWindow(shower, peak: peak, timeZone: timeZone).contains(instant) ? (shower, peak) : nil
        }
        .sorted { $0.0.zhr > $1.0.zhr }
    }
}
