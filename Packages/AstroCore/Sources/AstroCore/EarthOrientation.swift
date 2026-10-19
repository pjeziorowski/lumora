// Packages/AstroCore/Sources/AstroCore/EarthOrientation.swift
//
// Precession, nutation, obliquity, sidereal time and observer geocentric position.
// Ports of Astronomy Engine `iau2000b`, `mean_obliq`, `e_tilt`, `precession_rot`,
// `nutation_rot`, `era`, `Astronomy_SiderealTime`, `terra` and `geo_pos`.

import Foundation

/// Direction of a precession/nutation rotation.
enum PrecessDirection: Sendable {
    /// J2000 mean equator (EQJ) → equator of date.
    case from2000
    /// Equator of date → J2000 mean equator (EQJ).
    case into2000
}

/// Nutation and obliquity for one instant. Port of `earth_tilt_t`.
struct EarthTilt: Sendable {
    /// Nutation in longitude, arcseconds.
    let dpsi: Double
    /// Nutation in obliquity, arcseconds.
    let deps: Double
    /// Mean obliquity, degrees.
    let mobl: Double
    /// True obliquity, degrees.
    let tobl: Double
    /// Equation of the equinoxes, seconds of time.
    let ee: Double

    init(_ time: AstroTime) {
        // IAU 2000B truncated nutation (Astronomy Engine `iau2000b`).
        let t = time.tt / 36525.0
        let asec360 = AstroConstants.asec360, asec2rad = AstroConstants.asec2rad
        let elp = fmod(1_287_104.79305 + t * 129_596_581.0481, asec360) * asec2rad
        let f = fmod(335_779.526232 + t * 1_739_527_262.8478, asec360) * asec2rad
        let d = fmod(1_072_260.70369 + t * 1_602_961_601.2090, asec360) * asec2rad
        let om = fmod(450_160.398036 - t * 6_962_890.5431, asec360) * asec2rad

        var sarg = sin(om), carg = cos(om)
        var dp = (-172_064_161.0 - 174_666.0 * t) * sarg + 33386.0 * carg
        var de = (92_052_331.0 + 9086.0 * t) * carg + 15377.0 * sarg

        var arg = 2.0 * (f - d + om)
        sarg = sin(arg); carg = cos(arg)
        dp += (-13_170_906.0 - 1675.0 * t) * sarg - 13696.0 * carg
        de += (5_730_336.0 - 3015.0 * t) * carg - 4587.0 * sarg

        arg = 2.0 * (f + om)
        sarg = sin(arg); carg = cos(arg)
        dp += (-2_276_413.0 - 234.0 * t) * sarg + 2796.0 * carg
        de += (978_459.0 - 485.0 * t) * carg + 1374.0 * sarg

        arg = 2.0 * om
        sarg = sin(arg); carg = cos(arg)
        dp += (2_074_554.0 + 207.0 * t) * sarg - 698.0 * carg
        de += (-897_492.0 + 470.0 * t) * carg - 291.0 * sarg

        sarg = sin(elp); carg = cos(elp)
        dp += (1_475_877.0 - 3633.0 * t) * sarg + 11817.0 * carg
        de += (73871.0 - 184.0 * t) * carg - 1924.0 * sarg

        dpsi = -0.000135 + dp * 1.0e-7
        deps = +0.000388 + de * 1.0e-7
        mobl = meanObliquity(tt: time.tt)
        tobl = mobl + deps / 3600.0
        ee = dpsi * cos(mobl * AstroConstants.deg2rad) / 15.0
    }
}

/// Mean obliquity of the ecliptic in degrees. Port of `mean_obliq`.
func meanObliquity(tt: Double) -> Double {
    let t = tt / 36525.0
    var asec = -0.0000000434 * t - 0.000000576
    asec = asec * t + 0.00200340
    asec = asec * t - 0.0001831
    asec = asec * t - 46.836769
    asec = asec * t + 84381.406
    return asec / 3600.0
}

/// Rotates ecliptic coordinates into equatorial coordinates for the given obliquity (degrees).
/// Port of `obl_ecl2equ_vec`.
func eclipticToEquatorial(obliquity: Double, _ ecl: Vec3) -> Vec3 {
    let r = obliquity * AstroConstants.deg2rad
    let c = cos(r), s = sin(r)
    return Vec3(ecl.x, ecl.y * c - ecl.z * s, ecl.y * s + ecl.z * c)
}

/// Port of `precession_rot` (IAU 2006 precession, Capitaine et al. 2003).
func precessionRotation(_ time: AstroTime, _ direction: PrecessDirection) -> Rotation {
    var eps0 = 84381.406
    let t = time.tt / 36525.0

    var psia = -0.0000000951 * t + 0.000132851
    psia = psia * t - 0.00114045
    psia = psia * t - 1.0790069
    psia = psia * t + 5038.481507
    psia *= t

    var omegaa = 0.0000003337 * t - 0.000000467
    omegaa = omegaa * t - 0.00772503
    omegaa = omegaa * t + 0.0512623
    omegaa = omegaa * t - 0.025754
    omegaa = omegaa * t + eps0

    var chia = -0.0000000560 * t + 0.000170663
    chia = chia * t - 0.00121197
    chia = chia * t - 2.3814292
    chia = chia * t + 10.556403
    chia *= t

    let a2r = AstroConstants.asec2rad
    eps0 *= a2r; psia *= a2r; omegaa *= a2r; chia *= a2r

    let sa = sin(eps0), ca = cos(eps0)
    let sb = sin(-psia), cb = cos(-psia)
    let sc = sin(-omegaa), cc = cos(-omegaa)
    let sd = sin(chia), cd = cos(chia)

    let xx = cd * cb - sb * sd * cc
    let yx = cd * sb * ca + sd * cc * cb * ca - sa * sd * sc
    let zx = cd * sb * sa + sd * cc * cb * sa + ca * sd * sc
    let xy = -sd * cb - sb * cd * cc
    let yy = -sd * sb * ca + cd * cc * cb * ca - sa * cd * sc
    let zy = -sd * sb * sa + cd * cc * cb * sa + ca * cd * sc
    let xz = sb * sc
    let yz = -sc * cb * ca - sa * cc
    let zz = -sc * cb * sa + cc * ca

    switch direction {
    case .into2000:
        return Rotation(r00: xx, r01: yx, r02: zx, r10: xy, r11: yy, r12: zy, r20: xz, r21: yz, r22: zz)
    case .from2000:
        return Rotation(r00: xx, r01: xy, r02: xz, r10: yx, r11: yy, r12: yz, r20: zx, r21: zy, r22: zz)
    }
}

/// Port of `nutation_rot`.
func nutationRotation(_ tilt: EarthTilt, _ direction: PrecessDirection) -> Rotation {
    let oblm = tilt.mobl * AstroConstants.deg2rad
    let oblt = tilt.tobl * AstroConstants.deg2rad
    let psi = tilt.dpsi * AstroConstants.asec2rad
    let cobm = cos(oblm), sobm = sin(oblm)
    let cobt = cos(oblt), sobt = sin(oblt)
    let cpsi = cos(psi), spsi = sin(psi)

    let xx = cpsi
    let yx = -spsi * cobm
    let zx = -spsi * sobm
    let xy = spsi * cobt
    let yy = cpsi * cobm * cobt + sobm * sobt
    let zy = cpsi * sobm * cobt - cobm * sobt
    let xz = spsi * sobt
    let yz = cpsi * cobm * sobt - sobm * cobt
    let zz = cpsi * sobm * sobt + cobm * cobt

    switch direction {
    case .from2000:
        return Rotation(r00: xx, r01: xy, r02: xz, r10: yx, r11: yy, r12: yz, r20: zx, r21: zy, r22: zz)
    case .into2000:
        return Rotation(r00: xx, r01: yx, r02: zx, r10: xy, r11: yy, r12: zy, r20: xz, r21: yz, r22: zz)
    }
}

/// Converts a J2000 (EQJ) vector into the true equator and equinox of date (EQD).
func j2000ToOfDate(_ v: Vec3, _ time: AstroTime, _ tilt: EarthTilt) -> Vec3 {
    let mean = precessionRotation(time, .from2000).rotate(v)
    return nutationRotation(tilt, .from2000).rotate(mean)
}

/// Converts a true-of-date (EQD) vector into J2000 (EQJ).
func ofDateToJ2000(_ v: Vec3, _ time: AstroTime, _ tilt: EarthTilt) -> Vec3 {
    let mean = nutationRotation(tilt, .into2000).rotate(v)
    return precessionRotation(time, .into2000).rotate(mean)
}

/// Earth Rotation Angle in degrees. Port of `era`.
func earthRotationAngle(ut: Double) -> Double {
    let thet1 = 0.7790572732640 + 0.00273781191135448 * ut
    let thet3 = fmod(ut, 1.0)
    var theta = 360.0 * fmod(thet1 + thet3, 1.0)
    if theta < 0 { theta += 360 }
    return theta
}

public enum SiderealTime {
    /// Greenwich Apparent Sidereal Time in sidereal hours [0, 24). Port of `Astronomy_SiderealTime`.
    public static func greenwichApparent(_ time: AstroTime) -> Double {
        greenwichApparent(time, EarthTilt(time))
    }

    static func greenwichApparent(_ time: AstroTime, _ tilt: EarthTilt) -> Double {
        let t = time.tt / 36525.0
        let eqeq = 15.0 * tilt.ee
        let theta = earthRotationAngle(ut: time.ut)
        var st = -0.0000000368 * t - 0.000029956
        st = st * t - 0.00000044
        st = st * t + 1.3915817
        st = st * t + 4612.156534
        st = st * t + eqeq + 0.014506
        var gst = fmod(st / 3600.0 + theta, 360.0) / 15.0
        if gst < 0 { gst += 24 }
        return gst
    }

    /// Local apparent sidereal time in hours [0, 24) at an east-positive longitude.
    public static func localApparent(_ time: AstroTime, longitude: Double) -> Double {
        var lst = fmod(greenwichApparent(time) + longitude / 15.0, 24.0)
        if lst < 0 { lst += 24 }
        return lst
    }
}

/// Observer position in true-of-date equatorial coordinates (AU). Port of `terra` (position only).
func terra(_ observer: Observer, siderealTime st: Double) -> Vec3 {
    let phi = observer.latitude * AstroConstants.deg2rad
    let sinphi = sin(phi), cosphi = cos(phi)
    let c = 1.0 / hypot(cosphi, sinphi * AstroConstants.earthFlattening)
    let s = c * AstroConstants.earthFlatteningSquared
    let htKm = observer.height / 1000.0
    let ach = AstroConstants.earthEquatorialRadiusKm * c + htKm
    let ash = AstroConstants.earthEquatorialRadiusKm * s + htKm
    let stlocl = (15.0 * st + observer.longitude) * AstroConstants.deg2rad
    let k = AstroConstants.kmPerAU
    return Vec3(ach * cosphi * cos(stlocl) / k, ach * cosphi * sin(stlocl) / k, ash * sinphi / k)
}

/// Observer geocentric position in J2000 (EQJ) coordinates. Port of `geo_pos`.
func observerJ2000(_ time: AstroTime, _ observer: Observer, _ tilt: EarthTilt) -> Vec3 {
    let gast = SiderealTime.greenwichApparent(time, tilt)
    return ofDateToJ2000(terra(observer, siderealTime: gast), time, tilt)
}
