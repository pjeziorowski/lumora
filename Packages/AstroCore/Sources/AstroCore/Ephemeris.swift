// Packages/AstroCore/Sources/AstroCore/Ephemeris.swift
//
// Apparent positions of the Sun and Moon for an observer. Ports of Astronomy Engine
// `Astronomy_GeoVector`, `Astronomy_BackdatePosition`, `Astronomy_CorrectLightTravel`,
// `Astronomy_Equator`, `vector2radec`, `Astronomy_Horizon`, `Astronomy_Refraction`,
// `Astronomy_InverseRefraction`, `Astronomy_SunPosition`, `Astronomy_Ecliptic`
// and `RotateEquatorialToEcliptic`.

import Foundation

/// The bodies AstroCore computes ephemerides for.
public enum Body: String, Sendable, CaseIterable, Codable {
    case sun
    case moon
}

/// A geographic observer on the WGS84-like ellipsoid used by Astronomy Engine.
public struct Observer: Sendable, Hashable, Codable {
    /// Geodetic latitude in degrees, north positive.
    public var latitude: Double
    /// Longitude in degrees, east positive.
    public var longitude: Double
    /// Height above sea level in metres.
    public var height: Double

    public init(latitude: Double, longitude: Double, height: Double = 0) {
        self.latitude = latitude
        self.longitude = longitude
        self.height = height
    }
}

/// Atmospheric refraction model.
public enum Refraction: Sendable {
    /// Airless, geometric altitude.
    case none
    /// Saemundsson's formula (Meeus, Astronomical Algorithms ch. 16) for standard conditions,
    /// tapered to zero toward the nadir. Matches JPL Horizons' "refracted apparent" output.
    case normal
}

/// Equatorial coordinates.
public struct Equatorial: Sendable, Hashable {
    /// Right ascension in sidereal hours [0, 24).
    public let ra: Double
    /// Declination in degrees.
    public let dec: Double
    /// Distance in AU.
    public let distance: Double
    /// Cartesian vector in AU (same frame as `ra`/`dec`).
    public let vector: Vec3
}

/// Horizontal coordinates.
public struct Horizontal: Sendable, Hashable {
    /// Azimuth in degrees east of true north [0, 360).
    public let azimuth: Double
    /// Altitude (elevation) above the horizon in degrees.
    public let altitude: Double
    /// Right ascension after refraction, sidereal hours.
    public let ra: Double
    /// Declination after refraction, degrees.
    public let dec: Double
}

/// Ecliptic coordinates.
public struct Ecliptic: Sendable, Hashable {
    /// Ecliptic longitude in degrees [0, 360).
    public let longitude: Double
    /// Ecliptic latitude in degrees.
    public let latitude: Double
    public let vector: Vec3
}

public enum Ephemeris {
    // MARK: Geocentric vectors

    /// Geocentric position of a body in J2000 equatorial coordinates (AU).
    /// For the Sun, light-travel time is applied and, if `aberration` is true,
    /// the Earth's position is back-dated too (Astronomy Engine's first-order aberration).
    public static func geoVector(_ body: Body, at time: AstroTime, aberration: Bool = true) -> Vec3 {
        switch body {
        case .moon:
            // The Moon is so close, aberration and light travel time don't matter.
            return LunarTheory.geoMoon(time)
        case .sun:
            let earthNow = VSOP87Earth.heliocentric(time)
            var ltime = time
            for _ in 0..<10 {
                let observerPos = aberration ? VSOP87Earth.heliocentric(ltime) : earthNow
                let pos = -observerPos  // heliocentric Sun is the origin
                let distance = pos.length
                let ltime2 = time.addingDays(-distance / AstroConstants.cAUPerDay)
                if abs(ltime2.tt - ltime.tt) < 1.0e-9 { return pos }
                ltime = ltime2
            }
            return aberration ? -VSOP87Earth.heliocentric(ltime) : -earthNow
        }
    }

    // MARK: Equatorial

    /// Topocentric equatorial coordinates. Port of `Astronomy_Equator`.
    /// - Parameters:
    ///   - ofDate: true for the true equator and equinox of date (needed for horizontal coordinates),
    ///     false for J2000.
    public static func equator(
        _ body: Body, at time: AstroTime, observer: Observer, ofDate: Bool = true, aberration: Bool = true
    ) -> Equatorial {
        let tilt = EarthTilt(time)
        return equator(body, time, observer, ofDate, aberration, tilt)
    }

    static func equator(
        _ body: Body, _ time: AstroTime, _ observer: Observer, _ ofDate: Bool, _ aberration: Bool, _ tilt: EarthTilt
    ) -> Equatorial {
        let gcObserver = observerJ2000(time, observer, tilt)
        let gc = geoVector(body, at: time, aberration: aberration)
        let j2000 = gc - gcObserver
        return vectorToRaDec(ofDate ? j2000ToOfDate(j2000, time, tilt) : j2000)
    }

    /// Port of `vector2radec`.
    static func vectorToRaDec(_ pos: Vec3) -> Equatorial {
        let xyproj = pos.x * pos.x + pos.y * pos.y
        let dist = (xyproj + pos.z * pos.z).squareRoot()
        if xyproj == 0 {
            return Equatorial(ra: 0, dec: pos.z < 0 ? -90 : 90, distance: dist, vector: pos)
        }
        var ra = AstroConstants.rad2hour * atan2(pos.y, pos.x)
        if ra < 0 { ra += 24 }
        let dec = AstroConstants.rad2deg * atan2(pos.z, xyproj.squareRoot())
        return Equatorial(ra: ra, dec: dec, distance: dist, vector: pos)
    }

    // MARK: Horizontal

    /// Converts true-of-date RA/Dec into azimuth/altitude. Port of `Astronomy_Horizon`.
    public static func horizon(
        at time: AstroTime, observer: Observer, ra: Double, dec: Double, refraction: Refraction
    ) -> Horizontal {
        horizon(time, observer, ra, dec, refraction, SiderealTime.greenwichApparent(time))
    }

    static func horizon(
        _ time: AstroTime, _ observer: Observer, _ ra: Double, _ dec: Double, _ refraction: Refraction, _ gast: Double
    ) -> Horizontal {
        let d2r = AstroConstants.deg2rad
        let latrad = observer.latitude * d2r
        let lonrad = observer.longitude * d2r
        let decrad = dec * d2r
        let rarad = ra * AstroConstants.hour2rad

        let sinlat = sin(latrad), coslat = cos(latrad)
        let sinlon = sin(lonrad), coslon = cos(lonrad)
        let sindc = sin(decrad), cosdc = cos(decrad)
        let sinra = sin(rarad), cosra = cos(rarad)

        // Zenith, north and west unit vectors, uncorrected for Earth's rotation.
        let uze = Vec3(coslat * coslon, coslat * sinlon, sinlat)
        let une = Vec3(-sinlat * coslon, -sinlat * sinlon, coslat)
        let uwe = Vec3(sinlon, -coslon, 0)

        // Rotate by sidereal time to the equator-of-date frame.
        let spinAngle = -15.0 * gast
        let uz = spin(spinAngle, uze)
        let un = spin(spinAngle, une)
        let uw = spin(spinAngle, uwe)

        let p = Vec3(cosdc * cosra, cosdc * sinra, sindc)
        let pn = p.dot(un), pw = p.dot(uw), pz = p.dot(uz)

        var proj = hypot(pn, pw)
        var az = 0.0
        if proj > 0 {
            az = -atan2(pw, pn) * AstroConstants.rad2deg
            if az < 0 { az += 360 }
        }
        var zd = atan2(proj, pz) * AstroConstants.rad2deg
        var outRa = ra, outDec = dec

        if refraction == .normal {
            let zd0 = zd
            let refr = refractionAngle(.normal, altitude: 90.0 - zd)
            zd -= refr
            if refr > 0, zd > 3.0e-4 {
                let sinzd = sin(zd * d2r), coszd = cos(zd * d2r)
                let sinzd0 = sin(zd0 * d2r), coszd0 = cos(zd0 * d2r)
                let pr = Vec3(
                    ((p.x - coszd0 * uz.x) / sinzd0) * sinzd + uz.x * coszd,
                    ((p.y - coszd0 * uz.y) / sinzd0) * sinzd + uz.y * coszd,
                    ((p.z - coszd0 * uz.z) / sinzd0) * sinzd + uz.z * coszd
                )
                proj = hypot(pr.x, pr.y)
                if proj > 0 {
                    outRa = AstroConstants.rad2hour * atan2(pr.y, pr.x)
                    if outRa < 0 { outRa += 24 }
                } else {
                    outRa = 0
                }
                outDec = AstroConstants.rad2deg * atan2(pr.z, proj)
            }
        }
        return Horizontal(azimuth: az, altitude: 90.0 - zd, ra: outRa, dec: outDec)
    }

    /// Convenience: apparent topocentric azimuth/altitude of a body.
    public static func horizontal(
        _ body: Body, at time: AstroTime, observer: Observer, refraction: Refraction = .normal
    ) -> Horizontal {
        let tilt = EarthTilt(time)
        let equ = equator(body, time, observer, true, true, tilt)
        return horizon(time, observer, equ.ra, equ.dec, refraction, SiderealTime.greenwichApparent(time, tilt))
    }

    /// Port of `spin`.
    private static func spin(_ angle: Double, _ v: Vec3) -> Vec3 {
        let r = angle * AstroConstants.deg2rad
        let c = cos(r), s = sin(r)
        return Vec3(c * v.x + s * v.y, -s * v.x + c * v.y, v.z)
    }

    // MARK: Refraction

    /// Refraction in degrees to add to a geometric altitude. Port of `Astronomy_Refraction`.
    public static func refractionAngle(_ refraction: Refraction, altitude: Double) -> Double {
        guard refraction == .normal, altitude >= -90, altitude <= 90 else { return 0 }
        let hd = max(altitude, -1.0)
        var refr = (1.02 / tan((hd + 10.3 / (hd + 5.11)) * AstroConstants.deg2rad)) / 60.0
        if altitude < -1.0 {
            refr *= (altitude + 90.0) / 89.0
        }
        return refr
    }

    /// Refraction to add to an observed (bent) altitude to recover the geometric one.
    /// Port of `Astronomy_InverseRefraction`; the result is negative or zero.
    public static func inverseRefractionAngle(_ refraction: Refraction, bentAltitude: Double) -> Double {
        guard bentAltitude >= -90, bentAltitude <= 90 else { return 0 }
        var altitude = bentAltitude - refractionAngle(refraction, altitude: bentAltitude)
        for _ in 0..<50 {
            let diff = (altitude + refractionAngle(refraction, altitude: altitude)) - bentAltitude
            if abs(diff) < 1.0e-14 { break }
            altitude -= diff
        }
        return altitude - bentAltitude
    }

    // MARK: Ecliptic

    /// Geocentric apparent ecliptic position of the Sun (true equinox of date).
    /// Port of `Astronomy_SunPosition`.
    public static func sunPosition(at time: AstroTime) -> Ecliptic {
        // Correct for light travel time from the Sun so equinoxes aren't 8 minutes early.
        let adjusted = time.addingDays(-1.0 / AstroConstants.cAUPerDay)
        let sun2000 = -VSOP87Earth.heliocentric(adjusted)
        let tilt = EarthTilt(adjusted)
        let ofDate = j2000ToOfDate(sun2000, adjusted, tilt)
        return rotateEquatorialToEcliptic(ofDate, obliquityRadians: tilt.tobl * AstroConstants.deg2rad)
    }

    /// J2000 equatorial vector → true ecliptic of date. Port of `Astronomy_Ecliptic`.
    static func ecliptic(_ eqj: Vec3, at time: AstroTime) -> Ecliptic {
        let tilt = EarthTilt(time)
        let eqd = j2000ToOfDate(eqj, time, tilt)
        return rotateEquatorialToEcliptic(eqd, obliquityRadians: tilt.tobl * AstroConstants.deg2rad)
    }

    /// Port of `RotateEquatorialToEcliptic`.
    static func rotateEquatorialToEcliptic(_ pos: Vec3, obliquityRadians: Double) -> Ecliptic {
        let c = cos(obliquityRadians), s = sin(obliquityRadians)
        let v = Vec3(pos.x, pos.y * c + pos.z * s, -pos.y * s + pos.z * c)
        let xyproj = hypot(v.x, v.y)
        var elon = 0.0
        if xyproj > 0 {
            elon = AstroConstants.rad2deg * atan2(v.y, v.x)
            if elon < 0 { elon += 360 }
        }
        let elat = AstroConstants.rad2deg * atan2(v.z, xyproj)
        return Ecliptic(longitude: elon, latitude: elat, vector: v)
    }
}
