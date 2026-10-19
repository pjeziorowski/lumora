// Packages/AstroCore/Sources/AstroCore/MoonPhase.swift
//
// Lunar phase, illumination, quarters and apsides. Ports of Astronomy Engine
// `Astronomy_PairLongitude`, `Astronomy_MoonPhase`, `Astronomy_SearchMoonPhase`,
// `Astronomy_SearchMoonQuarter`, `Astronomy_NextMoonQuarter`, `Astronomy_Illumination`
// (Moon branch), `MoonMagnitude`, `Astronomy_SearchLunarApsis` and `Astronomy_NextLunarApsis`.

import Foundation

public enum MoonQuarter: Int, Sendable, CaseIterable, Codable {
    case new = 0
    case firstQuarter = 1
    case full = 2
    case lastQuarter = 3
}

public struct MoonQuarterEvent: Sendable, Hashable {
    public let quarter: MoonQuarter
    public let time: AstroTime
}

/// Descriptive phase name for display.
public enum MoonPhaseName: String, Sendable, CaseIterable, Codable {
    case new, waxingCrescent, firstQuarter, waxingGibbous, full, waningGibbous, lastQuarter, waningCrescent
}

public struct MoonIllumination: Sendable, Hashable {
    /// Sun–Moon–Earth phase angle in degrees (0 = full, 180 = new).
    public let phaseAngle: Double
    /// Illuminated fraction of the disc [0, 1].
    public let fraction: Double
    /// Visual magnitude.
    public let magnitude: Double
    /// Geocentric distance in km.
    public let distanceKm: Double
}

public enum ApsisKind: Sendable, Hashable { case perigee, apogee }

public struct LunarApsis: Sendable, Hashable {
    public let kind: ApsisKind
    public let time: AstroTime
    public let distanceKm: Double
}

public enum Lunar {
    /// Ecliptic longitude of the Moon minus that of the Sun, degrees [0, 360):
    /// 0 new, 90 first quarter, 180 full, 270 last quarter. Port of `Astronomy_MoonPhase`.
    public static func phaseAngle(at time: AstroTime) -> Double {
        let moon = Ephemeris.ecliptic(Ephemeris.geoVector(.moon, at: time, aberration: false), at: time)
        let sun = Ephemeris.ecliptic(Ephemeris.geoVector(.sun, at: time, aberration: false), at: time)
        return normalizeLongitude(moon.longitude - sun.longitude)
    }

    /// Finds the next time (or previous, for negative `limitDays`) the phase angle equals `targetLon`.
    /// Port of `Astronomy_SearchMoonPhase`.
    public static func searchPhase(_ targetLon: Double, start: AstroTime, limitDays: Double) -> AstroTime? {
        let uncertainty = 1.5
        let offset: (AstroTime) -> Double = { longitudeOffset(phaseAngle(at: $0) - targetLon) }
        var ya = offset(start)
        let dt1: Double, dt2: Double
        if limitDays < 0 {
            if ya < 0 { ya += 360 }
            let est = -(AstroConstants.meanSynodicMonth * ya) / 360.0
            var lo = est - uncertainty
            let hi = est + uncertainty
            if hi < limitDays { return nil }
            if lo < limitDays { lo = limitDays }
            dt1 = lo; dt2 = hi
        } else {
            if ya > 0 { ya -= 360 }
            let est = -(AstroConstants.meanSynodicMonth * ya) / 360.0
            let lo = est - uncertainty
            var hi = est + uncertainty
            if lo > limitDays { return nil }
            if hi > limitDays { hi = limitDays }
            dt1 = lo; dt2 = hi
        }
        return Search.ascendingRoot(start.addingDays(dt1), start.addingDays(dt2), toleranceSeconds: 0.1, offset)
    }

    /// The first principal phase after `start`. Port of `Astronomy_SearchMoonQuarter`.
    public static func nextQuarter(after start: AstroTime) -> MoonQuarterEvent? {
        let angle = phaseAngle(at: start)
        let q = (1 + Int(floor(angle / 90.0))) % 4
        guard let quarter = MoonQuarter(rawValue: q),
              let time = searchPhase(90.0 * Double(q), start: start, limitDays: 10) else { return nil }
        return MoonQuarterEvent(quarter: quarter, time: time)
    }

    /// All principal phases in [start, end).
    public static func quarters(from start: AstroTime, to end: AstroTime) -> [MoonQuarterEvent] {
        var result: [MoonQuarterEvent] = []
        var cursor = start
        while let event = nextQuarter(after: cursor), event.time < end {
            result.append(event)
            // Quarters are ≥ 6.5 days apart (Astronomy Engine `Astronomy_NextMoonQuarter`).
            cursor = event.time.addingDays(6)
        }
        return result
    }

    /// Days since the most recent new moon.
    public static func age(at time: AstroTime) -> Double {
        guard let previousNew = searchPhase(0, start: time, limitDays: -32) else { return .nan }
        return time.ut - previousNew.ut
    }

    public static func phaseName(at time: AstroTime) -> MoonPhaseName {
        phaseName(forPhaseAngle: phaseAngle(at: time))
    }

    /// Principal phases get a ±6.1° window (about half a day either side), the rest are intermediate.
    public static func phaseName(forPhaseAngle angle: Double) -> MoonPhaseName {
        let window = 360.0 / AstroConstants.meanSynodicMonth / 2
        let a = normalizeLongitude(angle)
        if a < window || a >= 360 - window { return .new }
        if abs(a - 90) < window { return .firstQuarter }
        if abs(a - 180) < window { return .full }
        if abs(a - 270) < window { return .lastQuarter }
        if a < 90 { return .waxingCrescent }
        if a < 180 { return .waxingGibbous }
        if a < 270 { return .waningGibbous }
        return .waningCrescent
    }

    /// Geocentric illumination of the Moon. Port of the Moon branch of `Astronomy_Illumination`.
    public static func illumination(at time: AstroTime) -> MoonIllumination {
        let earth = VSOP87Earth.heliocentric(time)
        let gc = LunarTheory.geoMoon(time)
        let hc = earth + gc
        let phase = gc.angle(to: hc)
        let geoDist = gc.length, helioDist = hc.length
        let rad = phase * AstroConstants.deg2rad
        let rad2 = rad * rad
        var mag = -12.717 + 1.49 * abs(rad) + 0.0431 * rad2 * rad2
        let meanDistanceAU = 385_000.6 / AstroConstants.kmPerAU
        mag += 5 * log10(helioDist * (geoDist / meanDistanceAU))
        return MoonIllumination(
            phaseAngle: phase,
            fraction: (1.0 + cos(rad)) / 2.0,
            magnitude: mag,
            distanceKm: geoDist * AstroConstants.kmPerAU
        )
    }

    /// Geocentric distance in km.
    public static func distanceKm(at time: AstroTime) -> Double {
        LunarTheory.calc(time.tt / 36525.0).distance * AstroConstants.kmPerAU
    }

    /// Next perigee or apogee after `start`. Port of `Astronomy_SearchLunarApsis`.
    public static func nextApsis(after start: AstroTime) -> LunarApsis? {
        func slope(_ direction: Double, _ t: AstroTime) -> Double {
            let dt = 0.001
            let d1 = LunarTheory.calc(t.addingDays(-dt / 2).tt / 36525.0).distance
            let d2 = LunarTheory.calc(t.addingDays(+dt / 2).tt / 36525.0).distance
            return direction * (d2 - d1) / dt
        }
        let increment = 5.0
        var t1 = start
        var m1 = slope(+1, t1)
        var iter = 0
        while Double(iter) * increment < 2.0 * AstroConstants.meanSynodicMonth {
            let t2 = t1.addingDays(increment)
            let m2 = slope(+1, t2)
            if m1 * m2 <= 0 {
                let kind: ApsisKind
                let found: AstroTime?
                if m1 < 0 || m2 > 0 {
                    kind = .perigee
                    found = Search.ascendingRoot(t1, t2, toleranceSeconds: 1.0) { slope(+1, $0) }
                } else {
                    kind = .apogee
                    found = Search.ascendingRoot(t1, t2, toleranceSeconds: 1.0) { slope(-1, $0) }
                }
                guard let time = found else { return nil }
                return LunarApsis(kind: kind, time: time, distanceKm: distanceKm(at: time))
            }
            t1 = t2
            m1 = m2
            iter += 1
        }
        return nil
    }

    /// All perigees and apogees in [start, end).
    public static func apsides(from start: AstroTime, to end: AstroTime) -> [LunarApsis] {
        var result: [LunarApsis] = []
        var cursor = start
        while let apsis = nextApsis(after: cursor), apsis.time < end {
            result.append(apsis)
            cursor = apsis.time.addingDays(11)
        }
        return result
    }
}
