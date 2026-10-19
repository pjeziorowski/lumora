// Packages/AstroCore/Sources/AstroCore/MilkyWay.swift
//
// Milky Way geometry and visibility: the galactic centre and galactic plane in horizontal
// coordinates, the tilt of the arc above the horizon, and the windows when the core can be
// photographed:
//   dark      — Sun's geometric centre below the astronomical threshold (−18° by default);
//   centerUp  — galactic centre above `minimumCenterAltitude` (refracted, 0° by default);
//   visible   — dark ∩ centerUp;
//   moonFree  — visible and the Moon not interfering: below the horizon, or lit less
//               than `dimMoonIllumination` (10% by default). This is a heuristic; a thin
//               crescent near the horizon barely brightens the sky.
// Windows are found by sampling every `stepMinutes` and refining each edge by bisection to
// under 15 s, so windows shorter than the step can be missed (by design: they are not
// worth planning around).

import Foundation

public struct MilkyWayConditions: Sendable, Hashable, Codable {
    public var sunMaxAltitude = -18.0
    public var minimumCenterAltitude = 0.0
    public var dimMoonIllumination = 0.10

    public init() {}
    public static let standard = MilkyWayConditions()
}

public struct MilkyWayWindows: Sendable, Hashable {
    public let dark: [TimeSpan]
    public let centerUp: [TimeSpan]
    public let visible: [TimeSpan]
    public let moonFree: [TimeSpan]

    public var visibleDays: Double { visible.reduce(0) { $0 + $1.durationDays } }
    public var moonFreeDays: Double { moonFree.reduce(0) { $0 + $1.durationDays } }
}

/// How the band of the Milky Way crosses the sky around the core.
public enum ArcOrientation: String, Sendable, Hashable, Codable {
    /// Plane within 30° of the horizon at the core.
    case horizontal
    case diagonal
    /// Plane steeper than 60°.
    case vertical

    public static func of(tilt: Double) -> ArcOrientation {
        tilt < 30 ? .horizontal : (tilt > 60 ? .vertical : .diagonal)
    }
}

public struct GalacticPlanePoint: Sendable, Hashable {
    /// Galactic longitude, degrees.
    public let longitude: Double
    public let horizontal: Horizontal
}

public enum MilkyWay {
    // MARK: Geometry

    public static func center(at time: AstroTime, observer: Observer, refraction: Refraction = .normal) -> Horizontal {
        FixedSky.horizontal(FixedSky.galacticCenter, at: time, observer: observer, refraction: refraction)
    }

    /// The galactic equator (b = 0) every `step` degrees of galactic longitude, starting at the centre.
    public static func plane(at time: AstroTime, observer: Observer, step: Double = 5) -> [GalacticPlanePoint] {
        let frame = FixedSky.Frame(time)
        return stride(from: 0.0, to: 360.0, by: step).map { l in
            GalacticPlanePoint(longitude: l, horizontal: frame.horizontal(Galactic.toEquatorial(l: l, b: 0), observer: observer))
        }
    }

    /// Angle in degrees between the galactic plane and the horizon at the core, [0, 90]:
    /// 0 when the band lies along the horizon, 90 when it stands upright.
    public static func arcTilt(at time: AstroTime, observer: Observer) -> Double {
        let frame = FixedSky.Frame(time)
        let a = frame.horizontal(Galactic.toEquatorial(l: -1, b: 0), observer: observer, refraction: .none)
        let b = frame.horizontal(Galactic.toEquatorial(l: 1, b: 0), observer: observer, refraction: .none)
        let midAlt = (a.altitude + b.altitude) / 2 * AstroConstants.deg2rad
        let dAz = longitudeOffset(b.azimuth - a.azimuth) * cos(midAlt)
        let dAlt = b.altitude - a.altitude
        return atan2(abs(dAlt), abs(dAz)) * AstroConstants.rad2deg
    }

    // MARK: Visibility

    public static func windows(observer: Observer, from start: AstroTime, to end: AstroTime,
                               conditions: MilkyWayConditions = .standard, stepMinutes: Double = 10) -> MilkyWayWindows {
        func dark(_ t: AstroTime) -> Bool {
            Ephemeris.horizontal(.sun, at: t, observer: observer, refraction: .none).altitude < conditions.sunMaxAltitude
        }
        func centerUp(_ t: AstroTime) -> Bool {
            center(at: t, observer: observer).altitude > conditions.minimumCenterAltitude
        }
        func moonOK(_ t: AstroTime) -> Bool {
            Ephemeris.horizontal(.moon, at: t, observer: observer).altitude <= 0
                || Lunar.illumination(at: t).fraction < conditions.dimMoonIllumination
        }
        let step = stepMinutes / 1440
        return MilkyWayWindows(
            dark: intervals(from: start, to: end, step: step, where: dark),
            centerUp: intervals(from: start, to: end, step: step, where: centerUp),
            visible: intervals(from: start, to: end, step: step) { dark($0) && centerUp($0) },
            moonFree: intervals(from: start, to: end, step: step) { dark($0) && centerUp($0) && moonOK($0) }
        )
    }

    /// Spans of [start, end] where `predicate` holds, edges refined by bisection to < 15 s.
    /// Spans touching the ends of the range are clipped to it.
    public static func intervals(from start: AstroTime, to end: AstroTime, step: Double,
                                 where predicate: (AstroTime) -> Bool) -> [TimeSpan] {
        guard end.ut > start.ut, step > 0 else { return [] }
        func refine(_ a: Double, _ b: Double, _ valueAtA: Bool) -> Double {
            var lo = a, hi = b
            while hi - lo > 15.0 / 86_400 {
                let mid = (lo + hi) / 2
                if predicate(AstroTime(ut: mid)) == valueAtA { lo = mid } else { hi = mid }
            }
            return (lo + hi) / 2
        }
        var spans: [TimeSpan] = []
        var t = start.ut
        var inside = predicate(start)
        var spanStart: Double? = inside ? start.ut : nil
        while t < end.ut {
            let next = min(t + step, end.ut)
            let value = predicate(AstroTime(ut: next))
            if value != inside {
                let edge = refine(t, next, inside)
                if value {
                    spanStart = edge
                } else if let s = spanStart {
                    spans.append(TimeSpan(start: AstroTime(ut: s), end: AstroTime(ut: edge)))
                    spanStart = nil
                }
                inside = value
            }
            t = next
        }
        if let s = spanStart, end.ut > s {
            spans.append(TimeSpan(start: AstroTime(ut: s), end: end))
        }
        return spans
    }
}
