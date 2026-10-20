// Packages/AstroCore/Sources/AstroCore/RiseSet.swift
//
// Rise, set, altitude-crossing and transit searches. Ports of Astronomy Engine
// `altitude_diff`, `FindAscent`, `MaxAltitudeSlope`, `InternalSearchAltitude`,
// `Astronomy_Atmosphere`, `HorizonDipAngle`, `Astronomy_SearchRiseSetEx`,
// `Astronomy_SearchAltitude`, `Astronomy_SearchHourAngleEx` and `Astronomy_HourAngle`.

import Foundation

/// Rising (+1) or setting (−1).
public enum RiseSetDirection: Int, Sendable {
    case rise = 1
    case set = -1
}

/// Result of an hour-angle search (e.g. upper or lower culmination).
public struct HourAngleEvent: Sendable, Hashable {
    public let time: AstroTime
    /// Refracted horizontal coordinates of the body at `time`.
    public let horizontal: Horizontal
}

/// Atmospheric properties at a given elevation (U.S. Standard Atmosphere 1976).
public struct Atmosphere: Sendable, Hashable {
    /// Pressure in pascals.
    public let pressure: Double
    /// Temperature in kelvins.
    public let temperature: Double
    /// Density relative to sea level.
    public let density: Double

    /// Port of `Astronomy_Atmosphere`. Valid from −500 m to 100 km; clamped outside that range.
    public init(elevation meters: Double) {
        let h = min(max(meters, -500), 100_000)
        let p0 = 101_325.0, t0 = 288.15, t1 = 216.65
        let temp: Double, pres: Double
        if h <= 11000 {
            temp = t0 - 0.0065 * h
            pres = p0 * pow(t0 / temp, -5.25577)
        } else if h <= 20000 {
            temp = t1
            pres = 22632.0 * exp(-0.00015768832 * (h - 11000))
        } else {
            temp = t1 + 0.001 * (h - 20000)
            pres = 5474.87 * pow(t1 / temp, 34.16319)
        }
        pressure = pres
        temperature = temp
        density = (pres / temp) / (p0 / t0)
    }
}

public enum RiseSet {
    /// 10.08 hours: Nyquist-safe step for the ~22-hour minimum apparent day of any body.
    static let stepDays = 0.42

    // MARK: Public searches

    /// Finds the next (or previous, for negative `limitDays`) rise or set of the body's upper limb,
    /// using the USNO conventions: 34' refraction scaled by air density, topocentric parallax,
    /// and the body's apparent radius. Port of `Astronomy_SearchRiseSetEx`.
    ///
    /// - Parameter metersAboveGround: observer height above the local terrain, which dips the horizon.
    /// - Returns: nil if no event happens within `limitDays` (e.g. polar day or night).
    public static func search(
        _ body: Body, observer: Observer, direction: RiseSetDirection,
        start: AstroTime, limitDays: Double, metersAboveGround: Double = 0
    ) -> AstroTime? {
        guard metersAboveGround.isFinite, metersAboveGround >= 0 else { return nil }
        let radius: Double = body == .sun ? AstroConstants.sunRadiusAU : AstroConstants.moonEquatorialRadiusAU
        let atmos = Atmosphere(elevation: observer.height - metersAboveGround)
        let dip = horizonDipAngle(observer, metersAboveGround: metersAboveGround)
        let altitude = dip - AstroConstants.refractionNearHorizon * atmos.density
        return searchAltitude(body, observer, direction, start, limitDays, radius, altitude)
    }

    /// Finds when the body's *centre* crosses a geometric (airless) altitude, e.g. −6° for civil
    /// twilight. Port of `Astronomy_SearchAltitude`.
    public static func searchAltitude(
        _ body: Body, observer: Observer, direction: RiseSetDirection,
        start: AstroTime, limitDays: Double, altitude: Double
    ) -> AstroTime? {
        searchAltitude(body, observer, direction, start, limitDays, 0, altitude)
    }

    /// Finds when the body reaches the given local hour angle (0 = upper culmination,
    /// 12 = lower culmination). Port of `Astronomy_SearchHourAngleEx`.
    public static func searchHourAngle(
        _ body: Body, observer: Observer, hourAngle: Double, start: AstroTime, forward: Bool = true
    ) -> HourAngleEvent {
        var time = start
        var iteration = 0
        while true {
            iteration += 1
            let tilt = EarthTilt(time)
            let gast = SiderealTime.greenwichApparent(time, tilt)
            let ofdate = Ephemeris.equator(body, time, observer, true, true, tilt)
            var deltaSiderealHours = fmod((hourAngle + ofdate.ra - observer.longitude / 15) - gast, 24.0)
            if iteration == 1 {
                if forward {
                    if deltaSiderealHours < 0 { deltaSiderealHours += 24 }
                } else {
                    if deltaSiderealHours > 0 { deltaSiderealHours -= 24 }
                }
            } else {
                if deltaSiderealHours < -12 {
                    deltaSiderealHours += 24
                } else if deltaSiderealHours > 12 {
                    deltaSiderealHours -= 24
                }
            }
            if abs(deltaSiderealHours) * 3600.0 < 0.1 || iteration > 20 {
                let hor = Ephemeris.horizon(time, observer, ofdate.ra, ofdate.dec, .normal, gast)
                return HourAngleEvent(time: time, horizontal: hor)
            }
            time = time.addingDays((deltaSiderealHours / 24.0) * AstroConstants.solarDaysPerSiderealDay)
        }
    }

    /// Local hour angle of the body in sidereal hours [0, 24). Port of `Astronomy_HourAngle`.
    public static func hourAngle(_ body: Body, at time: AstroTime, observer: Observer) -> Double {
        let tilt = EarthTilt(time)
        let gast = SiderealTime.greenwichApparent(time, tilt)
        let ofdate = Ephemeris.equator(body, time, observer, true, true, tilt)
        var value = fmod(observer.longitude / 15 + gast - ofdate.ra, 24.0)
        if value < 0 { value += 24 }
        return value
    }

    // MARK: Internals

    /// Port of `altitude_diff`: signed distance of the body's limb (or centre) from the target altitude.
    static func altitudeDiff(
        _ body: Body, _ observer: Observer, _ direction: RiseSetDirection,
        _ bodyRadiusAU: Double, _ targetAltitude: Double, _ time: AstroTime
    ) -> Double {
        let tilt = EarthTilt(time)
        let ofdate = Ephemeris.equator(body, time, observer, true, true, tilt)
        let hor = Ephemeris.horizon(time, observer, ofdate.ra, ofdate.dec, .none,
                                    SiderealTime.greenwichApparent(time, tilt))
        let altitude = hor.altitude + AstroConstants.rad2deg * asin(bodyRadiusAU / ofdate.distance)
        return Double(direction.rawValue) * (altitude - targetAltitude)
    }

    /// Port of `MaxAltitudeSlope`: the maximum rate (deg/day) the body's altitude can change.
    static func maxAltitudeSlope(_ body: Body, latitude: Double) -> Double {
        let derivRa: Double, derivDec: Double
        switch body {
        case .moon: derivRa = 4.5; derivDec = 8.2
        case .sun: derivRa = 0.8; derivDec = 0.5
        }
        let latrad = AstroConstants.deg2rad * latitude
        return abs(((360.0 / AstroConstants.solarDaysPerSiderealDay) - derivRa) * cos(latrad))
            + abs(derivDec * sin(latrad))
    }

    /// Port of `FindAscent`: recursively bisects [t1, t2] looking for a sub-interval where
    /// the altitude difference rises through zero, pruning intervals the body cannot reach zero in.
    static func findAscent(
        depth: Int, maxDerivAlt: Double, _ t1: AstroTime, _ t2: AstroTime, _ a1: Double, _ a2: Double,
        _ f: (AstroTime) -> Double
    ) -> (AstroTime, AstroTime)? {
        if a1 < 0, a2 >= 0 { return (t1, t2) }
        if a1 >= 0, a2 < 0 { return nil }
        if depth > 17 { return nil }
        let dt = (t2.ut - t1.ut) / 2
        if dt * AstroConstants.secondsPerDay < 1.0 { return nil }
        let da = min(abs(a1), abs(a2))
        if da > maxDerivAlt * (dt / 2) { return nil }
        let tm = AstroTime(ut: (t1.ut + t2.ut) / 2)
        let am = f(tm)
        if let left = findAscent(depth: depth + 1, maxDerivAlt: maxDerivAlt, t1, tm, a1, am, f) {
            return left
        }
        return findAscent(depth: depth + 1, maxDerivAlt: maxDerivAlt, tm, t2, am, a2, f)
    }

    /// Port of `InternalSearchAltitude`.
    static func searchAltitude(
        _ body: Body, _ observer: Observer, _ direction: RiseSetDirection,
        _ start: AstroTime, _ limitDays: Double, _ bodyRadiusAU: Double, _ targetAltitude: Double
    ) -> AstroTime? {
        guard targetAltitude.isFinite, targetAltitude >= -90, targetAltitude <= 90 else { return nil }
        guard observer.latitude.isFinite, abs(observer.latitude) <= 90 else { return nil }
        let maxDerivAlt = maxAltitudeSlope(body, latitude: observer.latitude)
        let f: (AstroTime) -> Double = {
            altitudeDiff(body, observer, direction, bodyRadiusAU, targetAltitude, $0)
        }

        var t1 = start, t2 = start
        var a1 = f(start), a2 = a1
        while true {
            if limitDays < 0 {
                t1 = t2.addingDays(-stepDays)
                a1 = f(t1)
            } else {
                t2 = t1.addingDays(stepDays)
                a2 = f(t2)
            }

            if let (tx, ty) = findAscent(depth: 0, maxDerivAlt: maxDerivAlt, t1, t2, a1, a2, f) {
                guard let found = Search.ascendingRoot(tx, ty, toleranceSeconds: 0.1, f) else { return nil }
                if limitDays < 0 {
                    if found.ut < start.ut + limitDays { return nil }
                } else {
                    if found.ut > start.ut + limitDays { return nil }
                }
                return found
            }

            if limitDays < 0 {
                if t1.ut < start.ut + limitDays { return nil }
                t2 = t1
                a2 = a1
            } else {
                if t2.ut > start.ut + limitDays { return nil }
                t1 = t2
                a1 = a2
            }
        }
    }

    /// Port of `HorizonDipAngle`: how far the visible horizon dips below the astronomical one
    /// for an observer `metersAboveGround` above the terrain (Sweer 1938 refraction model).
    static func horizonDipAngle(_ observer: Observer, metersAboveGround: Double) -> Double {
        let phi = observer.latitude * AstroConstants.deg2rad
        let sinphi = sin(phi), cosphi = cos(phi)
        let c = 1.0 / hypot(cosphi, sinphi * AstroConstants.earthFlattening)
        let s = c * AstroConstants.earthFlatteningSquared
        let htKm = (observer.height - metersAboveGround) / 1000.0
        let ach = AstroConstants.earthEquatorialRadiusKm * c + htKm
        let ash = AstroConstants.earthEquatorialRadiusKm * s + htKm
        let radiusM = 1000.0 * hypot(ach * cosphi, ash * sinphi)
        let k = 0.175 * pow(1.0 - (6.5e-3 / 283.15) * (observer.height - (2.0 / 3.0) * metersAboveGround), 3.256)
        return AstroConstants.rad2deg * -((2 * (1 - k) * metersAboveGround / radiusM).squareRoot() / (1 - k))
    }
}
