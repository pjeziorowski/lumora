// Packages/PlannerKit/Sources/PlannerKit/SunReports.swift
//
// Data behind the Sun pill: day summary, twilights, month table and seasons. Everything is
// computed for the pin's local calendar day (LocalDay) and returned as plain values; views
// only format them. All `compute` functions are synchronous and pure, so callers run them
// off the main actor.

import AstroCore
import Foundation

/// A body crossing the horizon or culminating, with where it is at that moment.
public struct SkyEvent: Sendable, Hashable {
    public let time: Date
    /// Degrees east of true north.
    public let azimuth: Double
    /// Refracted elevation in degrees.
    public let altitude: Double

    public init(time: Date, azimuth: Double, altitude: Double) {
        self.time = time
        self.azimuth = azimuth
        self.altitude = altitude
    }

    static func at(_ time: AstroTime, _ body: Body, _ observer: Observer) -> SkyEvent {
        let h = Ephemeris.horizontal(body, at: time, observer: observer)
        return SkyEvent(time: time.date, azimuth: h.azimuth, altitude: h.altitude)
    }
}

/// Where a body is at one instant.
public struct SkyPosition: Sendable, Hashable {
    public let time: Date
    public let azimuth: Double
    /// Refracted elevation in degrees.
    public let altitude: Double
    public let distanceKm: Double
}

/// The light at a given Sun elevation, for labelling "now" and colouring graphs.
public enum LightPhase: String, Sendable, CaseIterable, Codable {
    case night, astronomicalTwilight, nauticalTwilight, blueHour, goldenHour, day

    /// Classifies the Sun's geometric-centre elevation using the configured thresholds.
    public static func of(sunAltitude alt: Double, thresholds t: SolarThresholds = .standard) -> LightPhase {
        if alt >= t.goldenUpper { return .day }
        if alt >= t.goldenLower { return .goldenHour }
        if alt >= t.blueLower { return .blueHour }
        if alt >= t.nautical { return .nauticalTwilight }
        if alt >= t.astronomical { return .astronomicalTwilight }
        return .night
    }
}

// MARK: - Day summary

public struct SunDayReport: Sendable, Hashable {
    public let location: PillLocation
    public let day: LocalDay
    public let rises: [SkyEvent]
    public let sets: [SkyEvent]
    /// Solar noon (upper culmination) with the Sun's elevation then.
    public let noon: SkyEvent?
    public let state: PolarState
    public let daylightSeconds: Double
    /// Daylight change against the previous local day (positive = longer).
    public let daylightChangeSeconds: Double
    /// The Sun at the selected instant.
    public let position: SkyPosition
    /// Light phase at the selected instant (from the airless elevation, as thresholds are defined).
    public let lightPhase: LightPhase

    /// Shadow length per unit of object height at the selected instant; nil when the Sun is down.
    public var shadowRatio: Double? {
        position.altitude > 0 ? 1 / tan(position.altitude * .pi / 180) : nil
    }

    public static func compute(
        location: PillLocation, day: LocalDay, instant: Date, thresholds: SolarThresholds = .standard
    ) -> SunDayReport {
        let observer = location.observer
        let (start, end) = day.astroWindow
        let events = Almanac.riseSetEvents(.sun, observer: observer, from: start, to: end)
        let daylight = daylightDays(observer: observer, events: events, start: start, end: end)

        let previous = day.adding(days: -1)
        let (pStart, pEnd) = previous.astroWindow
        let pEvents = Almanac.riseSetEvents(.sun, observer: observer, from: pStart, to: pEnd)
        let previousDaylight = daylightDays(observer: observer, events: pEvents, start: pStart, end: pEnd)

        let t = AstroTime(instant)
        let now = Ephemeris.horizontal(.sun, at: t, observer: observer)
        let airless = Ephemeris.horizontal(.sun, at: t, observer: observer, refraction: .none)
        let distance = Ephemeris.geoVector(.sun, at: t).length * AstroConstants.kmPerAU

        return SunDayReport(
            location: location,
            day: day,
            rises: events.filter { $0.direction == .rise }.map { SkyEvent.at($0.time, .sun, observer) },
            sets: events.filter { $0.direction == .set }.map { SkyEvent.at($0.time, .sun, observer) },
            noon: Almanac.transit(.sun, observer: observer, from: start, to: end).map {
                SkyEvent(time: $0.time.date, azimuth: $0.horizontal.azimuth, altitude: $0.horizontal.altitude)
            },
            state: polarState(.sun, observer: observer, events: events, start: start, end: end),
            daylightSeconds: daylight * 86_400,
            daylightChangeSeconds: (daylight - previousDaylight) * 86_400,
            position: SkyPosition(time: instant, azimuth: now.azimuth, altitude: now.altitude, distanceKm: distance),
            lightPhase: LightPhase.of(sunAltitude: airless.altitude, thresholds: thresholds)
        )
    }
}

// MARK: - Twilights

public enum TwilightKind: String, Sendable, CaseIterable, Codable {
    case astronomical, nautical, civil, horizon
}

/// Morning and evening crossings of one threshold.
public struct TwilightRow: Sendable, Hashable, Identifiable {
    public let kind: TwilightKind
    /// Elevation threshold in degrees (geometric centre; the horizon row uses the USNO upper-limb rule).
    public let threshold: Double
    /// Times the Sun climbs through the threshold.
    public let morning: [Date]
    /// Times the Sun sinks through the threshold.
    public let evening: [Date]
    public var id: TwilightKind { kind }
}

/// How dark the night gets, used to explain empty twilight rows at high latitudes.
public enum NightDarkness: String, Sendable, Codable {
    /// Sun drops below the astronomical threshold.
    case fullNight
    /// Lowest point between −18° and −12°: no astronomical night.
    case astronomicalTwilightAllNight
    /// Lowest point between −12° and −6°: nautical twilight all night ("white nights").
    case nauticalTwilightAllNight
    /// Lowest point between −6° and the horizon: civil twilight all night.
    case civilTwilightAllNight
    /// Sun never sets.
    case midnightSun
}

public struct TwilightReport: Sendable, Hashable {
    public let rows: [TwilightRow]
    public let goldenHours: [DateInterval]
    public let blueHours: [DateInterval]
    /// Solar noon (or the middle of the local day if there is none), which splits the
    /// golden/blue spans into morning and evening.
    public let split: Date
    public let darkness: NightDarkness
    /// Sun never climbs above the astronomical threshold (deep polar night).
    public let isDarkAllDay: Bool
    public let thresholds: SolarThresholds

    public var morningGoldenHours: [DateInterval] { goldenHours.filter(isMorning) }
    public var eveningGoldenHours: [DateInterval] { goldenHours.filter { !isMorning($0) } }
    public var morningBlueHours: [DateInterval] { blueHours.filter(isMorning) }
    public var eveningBlueHours: [DateInterval] { blueHours.filter { !isMorning($0) } }

    private func isMorning(_ span: DateInterval) -> Bool {
        span.start.addingTimeInterval(span.duration / 2) < split
    }

    public static func compute(location: PillLocation, day: LocalDay, thresholds: SolarThresholds = .standard) -> TwilightReport {
        let observer = location.observer
        let (start, end) = day.astroWindow
        let sun = Almanac.sunDay(observer: observer, from: start, to: end, thresholds: thresholds)

        // Lowest and highest geometric elevation across the day decide the darkness label:
        // 15-minute samples refined by the lower culmination (solar midnight) when it falls inside.
        func airless(_ t: AstroTime) -> Double {
            Ephemeris.horizontal(.sun, at: t, observer: observer, refraction: .none).altitude
        }
        let samples = stride(from: 0.0, through: 1.0, by: 1.0 / 96).map { airless(AstroTime(ut: start.ut + $0 * (end.ut - start.ut))) }
        var minAlt = samples.min() ?? 0
        let midnight = RiseSet.searchHourAngle(.sun, observer: observer, hourAngle: 12, start: start)
        if midnight.time < end { minAlt = min(minAlt, airless(midnight.time)) }
        let maxAlt = samples.max() ?? 0
        let darkness: NightDarkness
        if sun.state == .alwaysAbove {
            darkness = .midnightSun
        } else if minAlt < thresholds.astronomical {
            darkness = .fullNight
        } else if minAlt < thresholds.nautical {
            darkness = .astronomicalTwilightAllNight
        } else if minAlt < thresholds.civil {
            darkness = .nauticalTwilightAllNight
        } else {
            darkness = .civilTwilightAllNight
        }

        func dates(_ list: [AstroTime]) -> [Date] { list.map(\.date) }
        func spans(_ list: [TimeSpan]) -> [DateInterval] {
            list.map { DateInterval(start: $0.start.date, end: $0.end.date) }
        }
        return TwilightReport(
            rows: [
                TwilightRow(kind: .astronomical, threshold: thresholds.astronomical,
                            morning: dates(sun.astronomical.dawn), evening: dates(sun.astronomical.dusk)),
                TwilightRow(kind: .nautical, threshold: thresholds.nautical,
                            morning: dates(sun.nautical.dawn), evening: dates(sun.nautical.dusk)),
                TwilightRow(kind: .civil, threshold: thresholds.civil,
                            morning: dates(sun.civil.dawn), evening: dates(sun.civil.dusk)),
                TwilightRow(kind: .horizon, threshold: -0.833, morning: dates(sun.rises), evening: dates(sun.sets)),
            ],
            goldenHours: spans(sun.goldenHours),
            blueHours: spans(sun.blueHours),
            split: sun.transit?.time.date ?? day.start.addingTimeInterval(day.end.timeIntervalSince(day.start) / 2),
            darkness: darkness,
            isDarkAllDay: maxAlt < thresholds.astronomical,
            thresholds: thresholds
        )
    }
}

// MARK: - Month table

public struct SunMonthRow: Sendable, Hashable, Identifiable {
    public let day: LocalDay
    public let rises: [SkyEvent]
    public let sets: [SkyEvent]
    public let noon: SkyEvent?
    public let state: PolarState
    public let daylightSeconds: Double
    public var id: Int { day.day }
}

public struct SunMonthTable: Sendable, Hashable {
    public let year: Int
    public let month: Int
    public let rows: [SunMonthRow]

    /// Day of month with the most / least daylight (first one on ties).
    public var longestDay: Int? { rows.max { $0.daylightSeconds < $1.daylightSeconds }?.day.day }
    public var shortestDay: Int? { rows.min { $0.daylightSeconds < $1.daylightSeconds }?.day.day }

    public static func compute(location: PillLocation, year: Int, month: Int) -> SunMonthTable {
        let observer = location.observer
        let rows = LocalDay.days(inYear: year, month: month, timeZone: location.timeZone).map { day -> SunMonthRow in
            let (start, end) = day.astroWindow
            let events = Almanac.riseSetEvents(.sun, observer: observer, from: start, to: end)
            return SunMonthRow(
                day: day,
                rises: events.filter { $0.direction == .rise }.map { SkyEvent.at($0.time, .sun, observer) },
                sets: events.filter { $0.direction == .set }.map { SkyEvent.at($0.time, .sun, observer) },
                noon: Almanac.transit(.sun, observer: observer, from: start, to: end).map {
                    SkyEvent(time: $0.time.date, azimuth: $0.horizontal.azimuth, altitude: $0.horizontal.altitude)
                },
                state: polarState(.sun, observer: observer, events: events, start: start, end: end),
                daylightSeconds: daylightDays(observer: observer, events: events, start: start, end: end) * 86_400
            )
        }
        return SunMonthTable(year: year, month: month, rows: rows)
    }
}

// MARK: - Seasons

public enum SeasonMarker: String, Sendable, CaseIterable, Codable {
    case marchEquinox, juneSolstice, septemberEquinox, decemberSolstice
}

public enum Season: String, Sendable, CaseIterable, Codable {
    case spring, summer, autumn, winter
}

public struct SeasonEvent: Sendable, Hashable, Identifiable {
    public let marker: SeasonMarker
    public let time: Date
    /// The astronomical season that starts here at the pin's hemisphere.
    public let begins: Season
    /// Daylight on the local day containing the event.
    public let daylightSeconds: Double
    public var id: SeasonMarker { marker }
}

/// A run of consecutive local days with no sunrise or no sunset.
public struct PolarPeriod: Sendable, Hashable {
    /// First and last local day of the run.
    public let first: LocalDay
    public let last: LocalDay
    public var days: Int { first.daysUntil(last) + 1 }
}

public struct SeasonsReport: Sendable, Hashable {
    public let year: Int
    public let events: [SeasonEvent]
    /// Midnight sun around the summer solstice, if the pin is far enough poleward.
    public let midnightSun: PolarPeriod?
    /// Polar night around the winter solstice.
    public let polarNight: PolarPeriod?

    public static func compute(location: PillLocation, year: Int) -> SeasonsReport? {
        guard let info = Seasons.of(year: year) else { return nil }
        let observer = location.observer
        let zone = location.timeZone
        let southern = location.isSouthern
        let marks: [(SeasonMarker, AstroTime, Season)] = [
            (.marchEquinox, info.marchEquinox, southern ? .autumn : .spring),
            (.juneSolstice, info.juneSolstice, southern ? .winter : .summer),
            (.septemberEquinox, info.septemberEquinox, southern ? .spring : .autumn),
            (.decemberSolstice, info.decemberSolstice, southern ? .summer : .winter),
        ]
        func dayInfo(_ day: LocalDay) -> (state: PolarState, daylight: Double) {
            let (start, end) = day.astroWindow
            let events = Almanac.riseSetEvents(.sun, observer: observer, from: start, to: end)
            return (polarState(.sun, observer: observer, events: events, start: start, end: end),
                    daylightDays(observer: observer, events: events, start: start, end: end) * 86_400)
        }
        let events = marks.map { marker, time, season in
            SeasonEvent(marker: marker, time: time.date, begins: season,
                        daylightSeconds: dayInfo(LocalDay(containing: time.date, timeZone: zone)).daylight)
        }
        // Walk outward from a solstice while the polar state holds (≤ 6 months each way).
        func period(around time: AstroTime, state: PolarState) -> PolarPeriod? {
            let center = LocalDay(containing: time.date, timeZone: zone)
            guard dayInfo(center).state == state else { return nil }
            var first = center, last = center
            while center.daysUntil(first) > -183, dayInfo(first.adding(days: -1)).state == state { first = first.adding(days: -1) }
            while center.daysUntil(last) < 183, dayInfo(last.adding(days: 1)).state == state { last = last.adding(days: 1) }
            return PolarPeriod(first: first, last: last)
        }
        let summer = southern ? info.decemberSolstice : info.juneSolstice
        let winter = southern ? info.juneSolstice : info.decemberSolstice
        return SeasonsReport(
            year: year,
            events: events,
            midnightSun: period(around: summer, state: .alwaysAbove),
            polarNight: period(around: winter, state: .alwaysBelow)
        )
    }
}

// MARK: - Shared helpers

/// Polar state with a noon-and-midnight check, so a day whose midpoint is up but which has no
/// events is always "above" (and vice versa). Mirrors `Almanac`'s private helper.
func polarState(_ body: Body, observer: Observer, events: [CrossingEvent], start: AstroTime, end: AstroTime) -> PolarState {
    guard events.isEmpty else { return .normal }
    let mid = AstroTime(ut: (start.ut + end.ut) / 2)
    return Ephemeris.horizontal(body, at: mid, observer: observer).altitude > 0 ? .alwaysAbove : .alwaysBelow
}

/// Time above the rise/set horizon in [start, end), in days.
func daylightDays(observer: Observer, events: [CrossingEvent], start: AstroTime, end: AstroTime) -> Double {
    if events.isEmpty {
        return polarState(.sun, observer: observer, events: events, start: start, end: end) == .alwaysAbove
            ? end.ut - start.ut : 0
    }
    var up = events.first?.direction == .set
    var last = start
    var total = 0.0
    for e in events {
        if up { total += e.time.ut - last.ut }
        up = e.direction == .rise
        last = e.time
    }
    if up { total += end.ut - last.ut }
    return total
}
