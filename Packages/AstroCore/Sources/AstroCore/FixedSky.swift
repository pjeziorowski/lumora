// Packages/AstroCore/Sources/AstroCore/FixedSky.swift
//
// Objects fixed on the celestial sphere (galactic centre, galactic plane, Polaris, meteor
// radiants): J2000 catalogue coordinates → apparent azimuth/elevation at an instant, and
// galactic ↔ equatorial conversion.
//
// J2000 → true equator of date uses the ported IAU 2006 precession and IAU 2000B nutation
// (Astronomy Engine `Rotation_EQJ_EQD`); the horizon step is the ported `Astronomy_Horizon`.
// Annual aberration (≤ 20″) and proper motion are ignored, well inside the ±0.1° target.
//
// Galactic frame: IAU 1958 definition expressed in J2000/ICRS (ESA, The Hipparcos
// Catalogue, vol. 1, §1.5.3, 1997): north galactic pole α = 192.85948°, δ = +27.12825°,
// galactic longitude of the north celestial pole l = 122.93192°.

import Foundation

/// A catalogue position: right ascension in hours, declination in degrees (J2000).
public struct SkyCoordinate: Sendable, Hashable, Codable {
    public let ra: Double
    public let dec: Double

    public init(ra: Double, dec: Double) {
        self.ra = ra
        self.dec = dec
    }

    /// Unit vector in the J2000 equatorial frame.
    var vector: Vec3 {
        let r = ra * AstroConstants.hour2rad, d = dec * AstroConstants.deg2rad
        return Vec3(cos(d) * cos(r), cos(d) * sin(r), sin(d))
    }
}

public enum Galactic {
    static let poleRA = 192.85948
    static let poleDec = 27.12825
    static let ncpLongitude = 122.93192

    /// Galactic longitude/latitude (degrees) → J2000 equatorial.
    public static func toEquatorial(l: Double, b: Double) -> SkyCoordinate {
        let d2r = AstroConstants.deg2rad
        let lr = l * d2r, br = b * d2r
        let dg = poleDec * d2r, lo = ncpLongitude * d2r
        let sinDec = sin(br) * sin(dg) + cos(br) * cos(dg) * cos(lo - lr)
        let y = cos(br) * sin(lo - lr)
        let x = sin(br) * cos(dg) - cos(br) * sin(dg) * cos(lo - lr)
        var ra = (poleRA + atan2(y, x) * AstroConstants.rad2deg).truncatingRemainder(dividingBy: 360)
        if ra < 0 { ra += 360 }
        return SkyCoordinate(ra: ra / 15, dec: asin(max(-1, min(1, sinDec))) * AstroConstants.rad2deg)
    }

    /// J2000 equatorial → galactic (l in [0, 360), b in degrees).
    public static func fromEquatorial(_ c: SkyCoordinate) -> (l: Double, b: Double) {
        let d2r = AstroConstants.deg2rad
        let a = c.ra * 15 * d2r, d = c.dec * d2r
        let ag = poleRA * d2r, dg = poleDec * d2r
        let sinB = sin(d) * sin(dg) + cos(d) * cos(dg) * cos(a - ag)
        let y = cos(d) * sin(a - ag)
        let x = sin(d) * cos(dg) - cos(d) * sin(dg) * cos(a - ag)
        var l = (ncpLongitude - atan2(y, x) * AstroConstants.rad2deg).truncatingRemainder(dividingBy: 360)
        if l < 0 { l += 360 }
        return (l, asin(max(-1, min(1, sinB))) * AstroConstants.rad2deg)
    }
}

public enum FixedSky {
    /// The galactic centre as the origin of the galactic frame (l = 0, b = 0): J2000
    /// 17h45m37.2s −28°56′10″, matching the brief's 17h45.6m −28°56′. Sagittarius A* lies
    /// 4′ away, invisible at map and AR scale; using the frame origin keeps the centre
    /// exactly on the plotted galactic plane.
    public static let galacticCenter = Galactic.toEquatorial(l: 0, b: 0)

    /// Polaris (α UMi), J2000: 02h31m49.09s +89°15′50.8″ (SIMBAD, Hipparcos).
    public static let polaris = SkyCoordinate(ra: 2 + 31.0 / 60 + 49.09 / 3600, dec: 89 + 15.0 / 60 + 50.8 / 3600)

    /// Apparent azimuth/elevation of a J2000 position.
    public static func horizontal(_ c: SkyCoordinate, at time: AstroTime, observer: Observer,
                                  refraction: Refraction = .normal) -> Horizontal {
        Frame(time).horizontal(c, observer: observer, refraction: refraction)
    }

    /// Precession, nutation and sidereal time for one instant, reused for many objects.
    public struct Frame: Sendable {
        let time: AstroTime
        let rotation: Rotation
        let gast: Double

        public init(_ time: AstroTime) {
            let tilt = EarthTilt(time)
            self.time = time
            rotation = precessionRotation(time, .from2000).combined(with: nutationRotation(tilt, .from2000))
            gast = SiderealTime.greenwichApparent(time, tilt)
        }

        public func horizontal(_ c: SkyCoordinate, observer: Observer, refraction: Refraction = .normal) -> Horizontal {
            let equ = Ephemeris.vectorToRaDec(rotation.rotate(c.vector))
            return Ephemeris.horizon(time, observer, equ.ra, equ.dec, refraction, gast)
        }
    }
}
