// Packages/AstroCore/Sources/AstroCore/Almanac.swift
//
// Day-level summaries built on the ported searches: every rise/set, twilight and
// golden/blue-hour boundary in a time window (normally one local calendar day).
// Original to this project; no Astronomy Engine equivalent.

import Foundation

/// A rise/set or altitude crossing.
public struct CrossingEvent: Sendable, Hashable {
    public let time: AstroTime
    public let direction: RiseSetDirection
}

/// A half-open time interval [start, end) in AstroTime.
public struct TimeSpan: Sendable, Hashable {
    public let start: AstroTime
    public let end: AstroTime
    public var durationDays: Double { end.ut - start.ut }
}

/// Altitude thresholds (degrees, geometric centre of the Sun). All configurable.
public struct SolarThresholds: Sendable, Hashable, Codable {
    public var civil = -6.0
    public var nautical = -12.0
    public var astronomical = -18.0
    /// Golden hour: Sun between `goldenLower` and `goldenUpper`.
    public var goldenLower = -4.0
    public var goldenUpper = 6.0
    /// Blue hour: Sun between `blueLower` and `blueUpper`.
    public var blueLower = -6.0
    public var blueUpper = -4.0

    public init() {}
    public static let standard = SolarThresholds()
}

/// What the Sun (or Moon) does across a window with no rise/set.
public enum PolarState: String, Sendable, Hashable, Codable {
    /// At least one rise or set happens.
    case normal
    /// Above the horizon for the whole window (midnight sun / circumpolar).
    case alwaysAbove
    /// Below the horizon for the whole window (polar night / never rises).
    case alwaysBelow
}

public struct TwilightEvents: Sendable, Hashable {
    /// Times the Sun rises through the threshold (morning).
    public let dawn: [AstroTime]
    /// Times the Sun sets through the threshold (evening).
    public let dusk: [AstroTime]
}

public struct SunDay: Sendable, Hashable {
    public let rises: [AstroTime]
    public let sets: [AstroTime]
    /// Solar noon (upper culmination) within the window, if any.
    public let transit: HourAngleEvent?
    public let civil: TwilightEvents
    public let nautical: TwilightEvents
    public let astronomical: TwilightEvents
    public let goldenHours: [TimeSpan]
    public let blueHours: [TimeSpan]
    public let state: PolarState
    /// Total time above the rise/set horizon in the window, in days.
    public let daylightDays: Double
}

public struct MoonDay: Sendable, Hashable {
    public let rises: [AstroTime]
    public let sets: [AstroTime]
    public let transit: HourAngleEvent?
    public let state: PolarState
}

public enum Almanac {
    /// All rises and sets of the body's upper limb (USNO convention) in [start, end).
    public static func riseSetEvents(
        _ body: Body, observer: Observer, from start: AstroTime, to end: AstroTime, metersAboveGround: Double = 0
    ) -> [CrossingEvent] {
        collect(from: start, to: end) { direction, cursor, limit in
            RiseSet.search(body, observer: observer, direction: direction, start: cursor,
                           limitDays: limit, metersAboveGround: metersAboveGround)
        }
    }

    /// All crossings of the body's centre through a geometric altitude in [start, end).
    public static func altitudeCrossings(
        _ body: Body, observer: Observer, altitude: Double, from start: AstroTime, to end: AstroTime
    ) -> [CrossingEvent] {
        collect(from: start, to: end) { direction, cursor, limit in
            RiseSet.searchAltitude(body, observer: observer, direction: direction, start: cursor,
                                   limitDays: limit, altitude: altitude)
        }
    }

    /// Upper culmination within [start, end), if any.
    public static func transit(_ body: Body, observer: Observer, from start: AstroTime, to end: AstroTime) -> HourAngleEvent? {
        let event = RiseSet.searchHourAngle(body, observer: observer, hourAngle: 0, start: start)
        return event.time < end ? event : nil
    }

    /// Spans in [start, end) during which the body's geometric centre altitude is in [lower, upper).
    public static func altitudeBands(
        _ body: Body, observer: Observer, lower: Double, upper: Double, from start: AstroTime, to end: AstroTime
    ) -> [TimeSpan] {
        let crossings = (altitudeCrossings(body, observer: observer, altitude: lower, from: start, to: end)
            + altitudeCrossings(body, observer: observer, altitude: upper, from: start, to: end))
            .sorted { $0.time < $1.time }
        func inside(_ t: AstroTime) -> Bool {
            let alt = Ephemeris.horizontal(body, at: t, observer: observer, refraction: .none).altitude
            return alt >= lower && alt < upper
        }
        var spans: [TimeSpan] = []
        var isInside = inside(start)
        var spanStart: AstroTime? = isInside ? start : nil
        for c in crossings {
            // Re-evaluate just after each crossing; robust to coincident boundary crossings.
            let now = inside(c.time.addingDays(1.0 / 86_400))
            if now == isInside { continue }
            if now {
                spanStart = c.time
            } else if let s = spanStart {
                spans.append(TimeSpan(start: s, end: c.time))
                spanStart = nil
            }
            isInside = now
        }
        if let s = spanStart { spans.append(TimeSpan(start: s, end: end)) }
        return spans
    }

    /// Full solar summary for [start, end). Pass the UTC instants of a local midnight pair
    /// to get a calendar day in the pin's time zone.
    public static func sunDay(
        observer: Observer, from start: AstroTime, to end: AstroTime, thresholds: SolarThresholds = .standard
    ) -> SunDay {
        let rs = riseSetEvents(.sun, observer: observer, from: start, to: end)
        func twilight(_ alt: Double) -> TwilightEvents {
            let c = altitudeCrossings(.sun, observer: observer, altitude: alt, from: start, to: end)
            return TwilightEvents(dawn: c.filter { $0.direction == .rise }.map(\.time),
                                  dusk: c.filter { $0.direction == .set }.map(\.time))
        }
        let state = polarState(.sun, observer: observer, events: rs, at: AstroTime(ut: (start.ut + end.ut) / 2))
        return SunDay(
            rises: rs.filter { $0.direction == .rise }.map(\.time),
            sets: rs.filter { $0.direction == .set }.map(\.time),
            transit: transit(.sun, observer: observer, from: start, to: end),
            civil: twilight(thresholds.civil),
            nautical: twilight(thresholds.nautical),
            astronomical: twilight(thresholds.astronomical),
            goldenHours: altitudeBands(.sun, observer: observer, lower: thresholds.goldenLower,
                                       upper: thresholds.goldenUpper, from: start, to: end),
            blueHours: altitudeBands(.sun, observer: observer, lower: thresholds.blueLower,
                                     upper: thresholds.blueUpper, from: start, to: end),
            state: state,
            daylightDays: aboveHorizonDays(.sun, observer: observer, events: rs, state: state, from: start, to: end)
        )
    }

    public static func moonDay(observer: Observer, from start: AstroTime, to end: AstroTime) -> MoonDay {
        let rs = riseSetEvents(.moon, observer: observer, from: start, to: end)
        return MoonDay(
            rises: rs.filter { $0.direction == .rise }.map(\.time),
            sets: rs.filter { $0.direction == .set }.map(\.time),
            transit: transit(.moon, observer: observer, from: start, to: end),
            state: polarState(.moon, observer: observer, events: rs, at: AstroTime(ut: (start.ut + end.ut) / 2))
        )
    }

    // MARK: Helpers

    private static func collect(
        from start: AstroTime, to end: AstroTime,
        _ search: (RiseSetDirection, AstroTime, Double) -> AstroTime?
    ) -> [CrossingEvent] {
        var events: [CrossingEvent] = []
        for direction in [RiseSetDirection.rise, .set] {
            var cursor = start
            while cursor < end, let t = search(direction, cursor, end.ut - cursor.ut), t < end {
                events.append(CrossingEvent(time: t, direction: direction))
                // Skip past the found event; same-direction crossings are ≥ ~1 s apart by construction.
                cursor = t.addingDays(1.0 / 86_400)
            }
        }
        return events.sorted { $0.time < $1.time }
    }

    private static func polarState(_ body: Body, observer: Observer, events: [CrossingEvent], at mid: AstroTime) -> PolarState {
        guard events.isEmpty else { return .normal }
        let hor = Ephemeris.horizontal(body, at: mid, observer: observer, refraction: .normal)
        return hor.altitude > 0 ? .alwaysAbove : .alwaysBelow
    }

    private static func aboveHorizonDays(
        _ body: Body, observer: Observer, events: [CrossingEvent], state: PolarState, from start: AstroTime, to end: AstroTime
    ) -> Double {
        switch state {
        case .alwaysAbove: return end.ut - start.ut
        case .alwaysBelow: return 0
        case .normal: break
        }
        // Up at the start if the first event is a set.
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
}
