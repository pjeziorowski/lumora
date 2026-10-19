// Packages/AstroCore/Sources/AstroCore/Eclipses.swift
//
// Lunar eclipses, global solar eclipses and local solar eclipse circumstances. Ports of
// Astronomy Engine (MIT, Don Cross) `Astronomy_SearchLunarEclipse`,
// `Astronomy_SearchGlobalSolarEclipse`, `Astronomy_SearchLocalSolarEclipse` and their
// helpers (`CalcShadow`, `EarthShadow`, `MoonShadow`, `LocalMoonShadow`, `PeakEarthShadow`,
// `ShadowSemiDurationMinutes`, `GeoidIntersect`, `LocalEclipse`).
//
// Shadow model: the Earth's shadow uses a radius of 6371 km plus 88 km of atmosphere, which
// reproduces the shadow enlargement in Espenak's NASA eclipse tables; the Moon's shadow uses
// its mean radius (polar radius on the Earth's surface, as Astronomy Engine does).

import Foundation

public enum EclipseKind: String, Sendable, Hashable, Codable {
    case penumbral, partial, annular, total
}

public struct LunarEclipse: Sendable, Hashable {
    public let kind: EclipseKind
    /// Greatest eclipse: the Moon's centre closest to the axis of the Earth's shadow.
    public let peak: AstroTime
    /// Semi-durations in minutes of the penumbral, partial (umbral) and total phases; zero
    /// for phases that do not happen.
    public let semiDurationPenumbral: Double
    public let semiDurationPartial: Double
    public let semiDurationTotal: Double
    /// Fraction of the Moon's disc inside the umbra at the peak (1 for total, 0 for penumbral).
    public let obscuration: Double

    /// Contact times: P1, U1, U2, U3, U4, P4 (nil for phases that do not happen).
    public var penumbralBegin: AstroTime { peak.addingDays(-semiDurationPenumbral / 1440) }
    public var partialBegin: AstroTime? { semiDurationPartial > 0 ? peak.addingDays(-semiDurationPartial / 1440) : nil }
    public var totalBegin: AstroTime? { semiDurationTotal > 0 ? peak.addingDays(-semiDurationTotal / 1440) : nil }
    public var totalEnd: AstroTime? { semiDurationTotal > 0 ? peak.addingDays(semiDurationTotal / 1440) : nil }
    public var partialEnd: AstroTime? { semiDurationPartial > 0 ? peak.addingDays(semiDurationPartial / 1440) : nil }
    public var penumbralEnd: AstroTime { peak.addingDays(semiDurationPenumbral / 1440) }
}

public struct GlobalSolarEclipse: Sendable, Hashable {
    public let kind: EclipseKind
    /// Greatest eclipse: the axis of the Moon's shadow closest to the Earth's centre.
    public let peak: AstroTime
    /// Distance in km from the Earth's centre to the shadow axis at the peak.
    public let distance: Double
    /// Where the shadow axis meets the Earth at the peak; nil for partial eclipses whose axis
    /// misses the Earth.
    public let latitude: Double?
    public let longitude: Double?
}

public struct EclipseEvent: Sendable, Hashable {
    public let time: AstroTime
    /// The Sun's (refracted) altitude in degrees at that moment.
    public let altitude: Double
}

public struct LocalSolarEclipse: Sendable, Hashable {
    public let kind: EclipseKind
    public let partialBegin: EclipseEvent
    public let totalBegin: EclipseEvent?
    public let peak: EclipseEvent
    public let totalEnd: EclipseEvent?
    public let partialEnd: EclipseEvent
    /// Fraction of the Sun's diameter covered at the peak.
    public let magnitude: Double
    /// Fraction of the Sun's disc area covered at the peak.
    public let obscuration: Double
}

public enum Eclipses {
    static let earthMeanRadiusKm = 6371.0
    static let earthAtmosphereKm = 88.0
    static let earthEclipseRadiusKm = earthMeanRadiusKm + earthAtmosphereKm
    static let moonPolarRadiusKm = 1736.0
    /// A full or new Moon farther than this from the ecliptic (degrees) cannot be eclipsed.
    static let pruneLatitude = 1.8

    struct Shadow {
        let time: AstroTime
        /// Position of the shadow plane along the shadow axis.
        let u: Double
        /// Distance (km) from the target to the shadow axis.
        let r: Double
        /// Umbra radius (km) at the target; negative for an antumbra.
        let k: Double
        /// Penumbra radius (km) at the target.
        let p: Double
        let target: Vec3
        let dir: Vec3
    }

    static func calcShadow(bodyRadiusKm: Double, time: AstroTime, target: Vec3, dir: Vec3) -> Shadow {
        let u = dir.dot(target) / dir.dot(dir)
        let d = Vec3(u * dir.x - target.x, u * dir.y - target.y, u * dir.z - target.z)
        let r = AstroConstants.kmPerAU * d.length
        let k = AstroConstants.sunRadiusKm - (1 + u) * (AstroConstants.sunRadiusKm - bodyRadiusKm)
        let p = -AstroConstants.sunRadiusKm + (1 + u) * (AstroConstants.sunRadiusKm + bodyRadiusKm)
        return Shadow(time: time, u: u, r: r, k: k, p: p, target: target, dir: dir)
    }

    static func earthShadow(_ time: AstroTime) -> Shadow {
        // Sunlight through the Earth's centre: the reverse of the light-time and aberration
        // corrected geocentric Sun.
        let s = Ephemeris.geoVector(.sun, at: time, aberration: true)
        let m = LunarTheory.geoMoon(time)
        return calcShadow(bodyRadiusKm: earthEclipseRadiusKm, time: time, target: m, dir: -s)
    }

    static func moonShadow(_ time: AstroTime) -> Shadow {
        let s = Ephemeris.geoVector(.sun, at: time, aberration: true)
        let m = LunarTheory.geoMoon(time)
        // Target: lunacentric Earth. Direction: heliocentric Moon.
        return calcShadow(bodyRadiusKm: AstroConstants.moonMeanRadiusKm, time: time, target: -m, dir: m - s)
    }

    static func localMoonShadow(_ time: AstroTime, _ observer: Observer) -> Shadow {
        let pos = observerJ2000(time, observer, EarthTilt(time))
        let s = Ephemeris.geoVector(.sun, at: time, aberration: true)
        let m = LunarTheory.geoMoon(time)
        return calcShadow(bodyRadiusKm: AstroConstants.moonMeanRadiusKm, time: time, target: pos - m, dir: m - s)
    }

    /// The time near `center` when `shadow(t).r` is smallest.
    static func peak(near center: AstroTime, window: Double, _ shadow: (AstroTime) -> Shadow) -> Shadow? {
        let dt = 1.0 / 86_400
        let slope: (AstroTime) -> Double = { t in
            (shadow(t.addingDays(dt)).r - shadow(t.addingDays(-dt)).r) / dt
        }
        guard let t = Search.ascendingRoot(center.addingDays(-window), center.addingDays(window), toleranceSeconds: 1, slope)
        else { return nil }
        return shadow(t)
    }

    static func moonEclipticLatitude(_ time: AstroTime) -> Double {
        LunarTheory.calc(time.tt / 36525.0).latitude * AstroConstants.rad2deg
    }

    // MARK: Lunar

    /// The first lunar eclipse (penumbral or deeper) after `start`.
    public static func nextLunarEclipse(after start: AstroTime) -> LunarEclipse? {
        var time = start
        for _ in 0..<14 {
            guard let fullMoon = Lunar.searchPhase(180, start: time, limitDays: 40) else { return nil }
            if abs(moonEclipticLatitude(fullMoon)) < pruneLatitude,
               let shadow = peak(near: fullMoon, window: 0.1, earthShadow),
               shadow.r < shadow.p + AstroConstants.moonMeanRadiusKm {
                return lunarEclipse(at: shadow)
            }
            time = fullMoon.addingDays(10)
        }
        return nil
    }

    static func lunarEclipse(at shadow: Shadow) -> LunarEclipse {
        let moon = AstroConstants.moonMeanRadiusKm
        var kind = EclipseKind.penumbral
        var obscuration = 0.0
        var partial = 0.0, total = 0.0
        let penumbral = semiDuration(center: shadow.time, radiusLimit: shadow.p + moon, windowMinutes: 200)
        if shadow.r < shadow.k + moon {
            kind = .partial
            partial = semiDuration(center: shadow.time, radiusLimit: shadow.k + moon, windowMinutes: penumbral)
            if shadow.r + moon < shadow.k {
                kind = .total
                obscuration = 1
                total = semiDuration(center: shadow.time, radiusLimit: shadow.k - moon, windowMinutes: partial)
            } else {
                obscuration = circleOverlap(shadow.k, moon, shadow.r) / (Double.pi * moon * moon)
            }
        }
        return LunarEclipse(kind: kind, peak: shadow.time, semiDurationPenumbral: penumbral, semiDurationPartial: partial,
                            semiDurationTotal: total, obscuration: obscuration)
    }

    /// Minutes from the peak until the Moon's centre is `radiusLimit` km from the shadow axis,
    /// averaged over the two sides.
    static func semiDuration(center: AstroTime, radiusLimit: Double, windowMinutes: Double) -> Double {
        let window = windowMinutes / 1440
        guard let before = Search.ascendingRoot(center.addingDays(-window), center, toleranceSeconds: 1, {
            -(earthShadow($0).r - radiusLimit)
        }), let after = Search.ascendingRoot(center, center.addingDays(window), toleranceSeconds: 1, {
            earthShadow($0).r - radiusLimit
        }) else { return 0 }
        return (after.ut - before.ut) * 1440 / 2
    }

    /// Area of the overlap of two circles with radii `a` and `b` whose centres are `c` apart.
    static func circleOverlap(_ a: Double, _ b: Double, _ c: Double) -> Double {
        if c >= a + b { return 0 }
        if c <= abs(a - b) { return Double.pi * min(a, b) * min(a, b) }
        let x = (a * a - b * b + c * c) / (2 * c)
        let y = (a * a - x * x).squareRoot()
        let lensA = a * a * acos(x / a) - x * y
        let lensB = b * b * acos((c - x) / b) - (c - x) * y
        return lensA + lensB
    }

    // MARK: Solar, global

    /// The first solar eclipse visible anywhere on Earth after `start`.
    public static func nextGlobalSolarEclipse(after start: AstroTime) -> GlobalSolarEclipse? {
        var time = start
        for _ in 0..<14 {
            guard let newMoon = Lunar.searchPhase(0, start: time, limitDays: 40) else { return nil }
            if abs(moonEclipticLatitude(newMoon)) < pruneLatitude,
               let shadow = peak(near: newMoon, window: 0.1, moonShadow),
               shadow.r < shadow.p + earthMeanRadiusKm {
                return geoidIntersect(shadow)
            }
            time = newMoon.addingDays(10)
        }
        return nil
    }

    /// Where the shadow axis meets the oblate Earth, and whether the eclipse is total there.
    static func geoidIntersect(_ shadow: Shadow) -> GlobalSolarEclipse {
        let tilt = EarthTilt(shadow.time)
        let km = AstroConstants.kmPerAU, f = AstroConstants.earthFlattening
        let v0 = j2000ToOfDate(shadow.dir, shadow.time, tilt)
        let e0 = j2000ToOfDate(shadow.target, shadow.time, tilt)
        // Stretch z so the Earth becomes a sphere of the equatorial radius.
        let v = Vec3(v0.x * km, v0.y * km, v0.z * km / f)
        let e = Vec3(e0.x * km, e0.y * km, e0.z * km / f)
        let radius = AstroConstants.earthEquatorialRadiusKm
        let a = v.dot(v), b = -2 * v.dot(e), c = e.dot(e) - radius * radius
        let radic = b * b - 4 * a * c
        guard radic > 0 else {
            return GlobalSolarEclipse(kind: .partial, peak: shadow.time, distance: shadow.r, latitude: nil, longitude: nil)
        }
        // The nearer intersection is on the day side.
        let u = (-b - radic.squareRoot()) / (2 * a)
        let px = u * v.x - e.x, py = u * v.y - e.y, pz = (u * v.z - e.z) * f
        let proj = hypot(px, py) * AstroConstants.earthFlatteningSquared
        let latitude = proj == 0 ? (pz > 0 ? 90.0 : -90.0) : atan(pz / proj) * AstroConstants.rad2deg
        let gast = SiderealTime.greenwichApparent(shadow.time, tilt)
        var longitude = fmod(atan2(py, px) * AstroConstants.rad2deg - 15 * gast, 360)
        if longitude <= -180 { longitude += 360 } else if longitude > 180 { longitude -= 360 }
        // Umbra radius at that surface point decides total or annular.
        let o = ofDateToJ2000(Vec3(px / km, py / km, pz / km), shadow.time, tilt) + shadow.target
        let surface = calcShadow(bodyRadiusKm: moonPolarRadiusKm, time: shadow.time, target: o, dir: shadow.dir)
        return GlobalSolarEclipse(kind: kindFromUmbra(surface.k), peak: shadow.time, distance: shadow.r,
                                  latitude: latitude, longitude: longitude)
    }

    /// Positive umbra radius: total; negative (antumbra): annular. The 14 m bias matches
    /// Espenak's classification, as in Astronomy Engine.
    static func kindFromUmbra(_ k: Double) -> EclipseKind { k > 0.014 ? .total : .annular }

    // MARK: Solar, local

    /// The first solar eclipse seen by `observer` after `start` (the Sun must be above the
    /// horizon at its beginning or end). Searches at most `limitDays`.
    public static func nextLocalSolarEclipse(after start: AstroTime, observer: Observer,
                                             limitDays: Double = 366 * 20) -> LocalSolarEclipse? {
        var time = start
        while time.ut - start.ut < limitDays {
            guard let newMoon = Lunar.searchPhase(0, start: time, limitDays: 40) else { return nil }
            if abs(moonEclipticLatitude(newMoon)) < pruneLatitude,
               let shadow = peak(near: newMoon, window: 0.2, { localMoonShadow($0, observer) }),
               shadow.r < shadow.p,
               let eclipse = localEclipse(shadow, observer),
               eclipse.partialBegin.altitude > 0 || eclipse.partialEnd.altitude > 0 {
                return eclipse
            }
            time = newMoon.addingDays(10)
        }
        return nil
    }

    static func localEclipse(_ shadow: Shadow, _ observer: Observer) -> LocalSolarEclipse? {
        let partialWindow = 0.2, totalWindow = 0.01
        func transition(_ direction: Double, _ from: AstroTime, _ to: AstroTime, _ total: Bool) -> EclipseEvent? {
            let t = Search.ascendingRoot(from, to, toleranceSeconds: 1) { time in
                let s = localMoonShadow(time, observer)
                return direction * (total ? abs(s.k) - s.r : s.p - s.r)
            }
            return t.map { event($0, observer) }
        }
        guard let begin = transition(1, shadow.time.addingDays(-partialWindow), shadow.time, false),
              let end = transition(-1, shadow.time, shadow.time.addingDays(partialWindow), false) else { return nil }
        var kind = EclipseKind.partial
        var totalBegin: EclipseEvent?, totalEnd: EclipseEvent?
        if shadow.r < abs(shadow.k) {
            totalBegin = transition(1, shadow.time.addingDays(-totalWindow), shadow.time, true)
            totalEnd = transition(-1, shadow.time, shadow.time.addingDays(totalWindow), true)
            kind = kindFromUmbra(shadow.k)
        }
        let (magnitude, obscuration) = solarCoverage(shadow.time, observer)
        return LocalSolarEclipse(kind: kind, partialBegin: begin, totalBegin: totalBegin, peak: event(shadow.time, observer),
                                 totalEnd: totalEnd, partialEnd: end,
                                 magnitude: magnitude, obscuration: kind == .total ? 1 : obscuration)
    }

    static func event(_ time: AstroTime, _ observer: Observer) -> EclipseEvent {
        EclipseEvent(time: time, altitude: Ephemeris.horizontal(.sun, at: time, observer: observer).altitude)
    }

    /// Topocentric magnitude (fraction of the Sun's diameter covered) and obscuration (area).
    static func solarCoverage(_ time: AstroTime, _ observer: Observer) -> (Double, Double) {
        let obs = observerJ2000(time, observer, EarthTilt(time))
        let sun = Ephemeris.geoVector(.sun, at: time, aberration: true) - obs
        let moon = LunarTheory.geoMoon(time) - obs
        let rs = asin(AstroConstants.sunRadiusAU / sun.length)
        let rm = asin(AstroConstants.moonMeanRadiusKm / AstroConstants.kmPerAU / moon.length)
        let separation = sun.angle(to: moon) * AstroConstants.deg2rad
        let magnitude = max(0, (rs + rm - separation) / (2 * rs))
        let obscuration = circleOverlap(rs, rm, separation) / (Double.pi * rs * rs)
        return (magnitude, min(1, obscuration))
    }
}
