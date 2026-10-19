// Packages/PlannerKit/Sources/PlannerKit/Planner/PlannerSnapshot.swift
//
// Everything the Planner shows for one pin and one instant. Split in two levels so the time
// scrubber stays cheap: `PlannerDay` holds the searches for the pin's local day (rise/set,
// twilights, daily paths, light bands for the time bar) and is cached per (place, day);
// `PlannerSnapshot` adds the Sun and Moon at the instant, which costs a few microseconds.

import AstroCore
import Foundation

/// The Sun or Moon at one instant.
public struct BodyNow: Sendable, Hashable {
    /// Degrees east of true north.
    public let azimuth: Double
    /// Refracted elevation in degrees.
    public let altitude: Double
    public let distanceKm: Double

    public var isUp: Bool { altitude > 0 }
}

/// Moon details at the instant.
public struct MoonNow: Sendable, Hashable {
    public let position: BodyNow
    public let illumination: Double
    /// Moon–Sun ecliptic longitude difference [0, 360).
    public let elongation: Double
    public let phaseName: MoonPhaseName
    public let ageDays: Double
    public let angularDiameter: Double
    /// Size class at the nearest new or full moon within two days, else nil.
    public let size: MoonSize?
}

/// A stretch of the time bar with one kind of light.
public struct LightBand: Sendable, Hashable {
    public let start: Date
    public let end: Date
    public let phase: LightPhase
}

public struct PlannerDay: Sendable, Hashable {
    public let location: PillLocation
    public let day: LocalDay
    public let sunRises: [SkyEvent]
    public let sunSets: [SkyEvent]
    public let solarNoon: SkyEvent?
    public let sunState: PolarState
    public let daylightSeconds: Double
    public let moonRises: [SkyEvent]
    public let moonSets: [SkyEvent]
    public let moonTransit: SkyEvent?
    public let moonState: PolarState
    public let twilight: TwilightReport
    /// Sun and Moon every 10 minutes from local midnight to the next.
    public let sunPath: SkyPath
    public let moonPath: SkyPath
    /// Light phases from 12 h before the day to 12 h after it, for the time bar.
    public let lightBands: [LightBand]
    /// New and full moons from three days before the day to three days after, with size.
    public let principalPhases: [LunarPhaseEvent]
    /// Milky Way core windows from noon the day before to noon the day after, so both the
    /// night ending this morning and the night starting this evening are covered.
    public let milkyWay: MilkyWayWindows

    /// The night (local noon to noon) that `instant` belongs to.
    public func night(containing instant: Date) -> DateInterval {
        let startDay = instant < day.noon ? day.adding(days: -1) : day
        return DateInterval(start: startDay.noon, end: startDay.adding(days: 1).noon)
    }

    /// Milky Way spans of `kind` within the night containing `instant`.
    public func milkyWaySpans(_ kind: KeyPath<MilkyWayWindows, [TimeSpan]>, night: DateInterval) -> [DateInterval] {
        milkyWay[keyPath: kind]
            .filter { $0.start.date < night.end && $0.end.date > night.start }
            .map { DateInterval(start: max($0.start.date, night.start), end: min($0.end.date, night.end)) }
    }

    public static func compute(location: PillLocation, day: LocalDay, thresholds: SolarThresholds = .standard,
                               rule: SupermoonRule = .standard) -> PlannerDay {
        let observer = location.observer
        let (start, end) = day.astroWindow
        let sunEvents = Almanac.riseSetEvents(.sun, observer: observer, from: start, to: end)
        let moonEvents = Almanac.riseSetEvents(.moon, observer: observer, from: start, to: end)
        func events(_ list: [CrossingEvent], _ direction: RiseSetDirection, _ body: Body) -> [SkyEvent] {
            list.filter { $0.direction == direction }.map { SkyEvent.at($0.time, body, observer) }
        }
        func transit(_ body: Body) -> SkyEvent? {
            Almanac.transit(body, observer: observer, from: start, to: end).map {
                SkyEvent(time: $0.time.date, azimuth: $0.horizontal.azimuth, altitude: $0.horizontal.altitude)
            }
        }
        return PlannerDay(
            location: location,
            day: day,
            sunRises: events(sunEvents, .rise, .sun),
            sunSets: events(sunEvents, .set, .sun),
            solarNoon: transit(.sun),
            sunState: polarState(.sun, observer: observer, events: sunEvents, start: start, end: end),
            daylightSeconds: daylightDays(observer: observer, events: sunEvents, start: start, end: end) * 86_400,
            moonRises: events(moonEvents, .rise, .moon),
            moonSets: events(moonEvents, .set, .moon),
            moonTransit: transit(.moon),
            moonState: polarState(.moon, observer: observer, events: moonEvents, start: start, end: end),
            twilight: TwilightReport.compute(location: location, day: day, thresholds: thresholds),
            sunPath: SkyPath.compute(.sun, location: location, day: day, stepMinutes: 10),
            moonPath: SkyPath.compute(.moon, location: location, day: day, stepMinutes: 10),
            lightBands: lightBands(observer: observer, from: day.start.addingTimeInterval(-12 * 3600),
                                   to: day.end.addingTimeInterval(12 * 3600), thresholds: thresholds),
            principalPhases: Lunar.quarters(from: start.addingDays(-3), to: end.addingDays(3))
                .filter { $0.quarter == .new || $0.quarter == .full }
                .map { q in
                    let distance = Lunar.distanceKm(at: q.time)
                    return LunarPhaseEvent(quarter: q.quarter, time: q.time.date, distanceKm: distance,
                                           size: MoonSize.classify(distanceKm: distance, rule: rule),
                                           isMonthlyBlueMoon: false, isSeasonalBlueMoon: false)
                },
            milkyWay: MilkyWay.windows(observer: observer, from: AstroTime(day.adding(days: -1).noon),
                                       to: AstroTime(day.adding(days: 1).noon))
        )
    }

    /// Light phase bands between two instants, from the Sun's airless elevation sampled every
    /// 5 minutes; band edges are placed halfway between samples (±2.5 min).
    static func lightBands(observer: Observer, from start: Date, to end: Date, thresholds: SolarThresholds) -> [LightBand] {
        let step: TimeInterval = 300
        var bands: [LightBand] = []
        var bandStart = start
        var current: LightPhase?
        var t = start
        while t <= end {
            let alt = Ephemeris.horizontal(.sun, at: AstroTime(t), observer: observer, refraction: .none).altitude
            let phase = LightPhase.of(sunAltitude: alt, thresholds: thresholds)
            if let c = current, c != phase {
                let edge = t.addingTimeInterval(-step / 2)
                bands.append(LightBand(start: bandStart, end: edge, phase: c))
                bandStart = edge
            }
            current = phase
            t = t.addingTimeInterval(step)
        }
        if let c = current { bands.append(LightBand(start: bandStart, end: end, phase: c)) }
        return bands
    }
}

public struct PlannerSnapshot: Sendable, Hashable {
    public let location: PillLocation
    public let instant: Date
    public let day: PlannerDay
    public let sun: BodyNow
    /// Light at the instant (Sun's airless elevation, as thresholds are defined).
    public let lightPhase: LightPhase
    public let moon: MoonNow
    /// The galactic centre now (distance unused).
    public let galacticCenter: BodyNow
    /// Tilt of the Milky Way band at the core, degrees [0, 90].
    public let arcTilt: Double
    /// The galactic plane every 5° of galactic longitude, starting at the core.
    public let galacticPlane: [SkySample]

    /// Shadow length per unit of object height; nil when the Sun is down.
    public var shadowRatio: Double? {
        sun.altitude > 0 ? 1 / tan(sun.altitude * .pi / 180) : nil
    }

    public static func compute(location: PillLocation, instant: Date, day: PlannerDay,
                               thresholds: SolarThresholds = .standard) -> PlannerSnapshot {
        let observer = location.observer
        let t = AstroTime(instant)
        let sunH = Ephemeris.horizontal(.sun, at: t, observer: observer)
        let sunAirless = Ephemeris.horizontal(.sun, at: t, observer: observer, refraction: .none)
        let sunDistance = Ephemeris.geoVector(.sun, at: t).length * AstroConstants.kmPerAU
        let moonH = Ephemeris.horizontal(.moon, at: t, observer: observer)
        let illum = Lunar.illumination(at: t)
        let elongation = Lunar.phaseAngle(at: t)
        let plane = MilkyWay.plane(at: t, observer: observer, step: 5)

        // Supermoon flag: only within two days of a new or full moon.
        let size = day.principalPhases
            .filter { abs($0.time.timeIntervalSince(instant)) <= 2 * 86_400 }
            .min { abs($0.time.timeIntervalSince(instant)) < abs($1.time.timeIntervalSince(instant)) }?
            .size

        return PlannerSnapshot(
            location: location,
            instant: instant,
            day: day,
            sun: BodyNow(azimuth: sunH.azimuth, altitude: sunH.altitude, distanceKm: sunDistance),
            lightPhase: LightPhase.of(sunAltitude: sunAirless.altitude, thresholds: thresholds),
            moon: MoonNow(
                position: BodyNow(azimuth: moonH.azimuth, altitude: moonH.altitude, distanceKm: illum.distanceKm),
                illumination: illum.fraction,
                elongation: elongation,
                phaseName: Lunar.phaseName(forPhaseAngle: elongation),
                ageDays: Lunar.age(at: t),
                angularDiameter: 2 * asin(AstroConstants.moonMeanRadiusKm / illum.distanceKm) * 180 / .pi,
                size: size
            ),
            galacticCenter: BodyNow(azimuth: plane[0].horizontal.azimuth, altitude: plane[0].horizontal.altitude, distanceKm: 0),
            arcTilt: MilkyWay.arcTilt(at: t, observer: observer),
            galacticPlane: plane.map { SkySample(time: instant, azimuth: $0.horizontal.azimuth, altitude: $0.horizontal.altitude) }
        )
    }
}
