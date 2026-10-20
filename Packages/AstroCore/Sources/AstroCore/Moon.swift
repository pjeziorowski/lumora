// Packages/AstroCore/Sources/AstroCore/Moon.swift
//
// Geocentric Moon position. Port of Astronomy Engine `CalcMoon` (and its helpers
// `LongPeriodic`, `Init`, `Term`, `AddSol`, `SolarN`, `Planetary`) and `Astronomy_GeoMoon`.
// The series is the Nautical Almanac Office "Improved Lunar Ephemeris" (1954) as adapted
// by Montenbruck & Pfleger, "Astronomy on the Personal Computer".

import Foundation

enum LunarTheory {
    struct SolarTerm: Sendable {
        let l, s, g, p: Double
        let p0, q, r, s0: Int
        init(_ l: Double, _ s: Double, _ g: Double, _ p: Double, _ p0: Int, _ q: Int, _ r: Int, _ s0: Int) {
            self.l = l; self.s = s; self.g = g; self.p = p
            self.p0 = p0; self.q = q; self.r = r; self.s0 = s0
        }
    }

    struct NTerm: Sendable {
        let n: Double
        let p, q, r, s: Int
        init(_ n: Double, _ p: Int, _ q: Int, _ r: Int, _ s: Int) {
            self.n = n; self.p = p; self.q = q; self.r = r; self.s = s
        }
    }

    static let solarTerms: [SolarTerm] = [
        SolarTerm(13.902, 14.06, -0.001, 0.2607, 0, 0, 0, 4),
        SolarTerm(0.403, -4.01, 0.394, 0.0023, 0, 0, 0, 3),
        SolarTerm(2369.912, 2373.36, 0.601, 28.2333, 0, 0, 0, 2),
        SolarTerm(-125.154, -112.79, -0.725, -0.9781, 0, 0, 0, 1),
        SolarTerm(1.979, 6.98, -0.445, 0.0433, 1, 0, 0, 4),
        SolarTerm(191.953, 192.72, 0.029, 3.0861, 1, 0, 0, 2),
        SolarTerm(-8.466, -13.51, 0.455, -0.1093, 1, 0, 0, 1),
        SolarTerm(22639.5, 22609.07, 0.079, 186.5398, 1, 0, 0, 0),
        SolarTerm(18.609, 3.59, -0.094, 0.0118, 1, 0, 0, -1),
        SolarTerm(-4586.465, -4578.13, -0.077, 34.3117, 1, 0, 0, -2),
        SolarTerm(3.215, 5.44, 0.192, -0.0386, 1, 0, 0, -3),
        SolarTerm(-38.428, -38.64, 0.001, 0.6008, 1, 0, 0, -4),
        SolarTerm(-0.393, -1.43, -0.092, 0.0086, 1, 0, 0, -6),
        SolarTerm(-0.289, -1.59, 0.123, -0.0053, 0, 1, 0, 4),
        SolarTerm(-24.42, -25.1, 0.04, -0.3, 0, 1, 0, 2),
        SolarTerm(18.023, 17.93, 0.007, 0.1494, 0, 1, 0, 1),
        SolarTerm(-668.146, -126.98, -1.302, -0.3997, 0, 1, 0, 0),
        SolarTerm(0.56, 0.32, -0.001, -0.0037, 0, 1, 0, -1),
        SolarTerm(-165.145, -165.06, 0.054, 1.9178, 0, 1, 0, -2),
        SolarTerm(-1.877, -6.46, -0.416, 0.0339, 0, 1, 0, -4),
        SolarTerm(0.213, 1.02, -0.074, 0.0054, 2, 0, 0, 4),
        SolarTerm(14.387, 14.78, -0.017, 0.2833, 2, 0, 0, 2),
        SolarTerm(-0.586, -1.2, 0.054, -0.01, 2, 0, 0, 1),
        SolarTerm(769.016, 767.96, 0.107, 10.1657, 2, 0, 0, 0),
        SolarTerm(1.75, 2.01, -0.018, 0.0155, 2, 0, 0, -1),
        SolarTerm(-211.656, -152.53, 5.679, -0.3039, 2, 0, 0, -2),
        SolarTerm(1.225, 0.91, -0.03, -0.0088, 2, 0, 0, -3),
        SolarTerm(-30.773, -34.07, -0.308, 0.3722, 2, 0, 0, -4),
        SolarTerm(-0.57, -1.4, -0.074, 0.0109, 2, 0, 0, -6),
        SolarTerm(-2.921, -11.75, 0.787, -0.0484, 1, 1, 0, 2),
        SolarTerm(1.267, 1.52, -0.022, 0.0164, 1, 1, 0, 1),
        SolarTerm(-109.673, -115.18, 0.461, -0.949, 1, 1, 0, 0),
        SolarTerm(-205.962, -182.36, 2.056, 1.4437, 1, 1, 0, -2),
        SolarTerm(0.233, 0.36, 0.012, -0.0025, 1, 1, 0, -3),
        SolarTerm(-4.391, -9.66, -0.471, 0.0673, 1, 1, 0, -4),
        SolarTerm(0.283, 1.53, -0.111, 0.006, 1, -1, 0, 4),
        SolarTerm(14.577, 31.7, -1.54, 0.2302, 1, -1, 0, 2),
        SolarTerm(147.687, 138.76, 0.679, 1.1528, 1, -1, 0, 0),
        SolarTerm(-1.089, 0.55, 0.021, 0.0, 1, -1, 0, -1),
        SolarTerm(28.475, 23.59, -0.443, -0.2257, 1, -1, 0, -2),
        SolarTerm(-0.276, -0.38, -0.006, -0.0036, 1, -1, 0, -3),
        SolarTerm(0.636, 2.27, 0.146, -0.0102, 1, -1, 0, -4),
        SolarTerm(-0.189, -1.68, 0.131, -0.0028, 0, 2, 0, 2),
        SolarTerm(-7.486, -0.66, -0.037, -0.0086, 0, 2, 0, 0),
        SolarTerm(-8.096, -16.35, -0.74, 0.0918, 0, 2, 0, -2),
        SolarTerm(-5.741, -0.04, 0.0, -0.0009, 0, 0, 2, 2),
        SolarTerm(0.255, 0.0, 0.0, 0.0, 0, 0, 2, 1),
        SolarTerm(-411.608, -0.2, 0.0, -0.0124, 0, 0, 2, 0),
        SolarTerm(0.584, 0.84, 0.0, 0.0071, 0, 0, 2, -1),
        SolarTerm(-55.173, -52.14, 0.0, -0.1052, 0, 0, 2, -2),
        SolarTerm(0.254, 0.25, 0.0, -0.0017, 0, 0, 2, -3),
        SolarTerm(0.025, -1.67, 0.0, 0.0031, 0, 0, 2, -4),
        SolarTerm(1.06, 2.96, -0.166, 0.0243, 3, 0, 0, 2),
        SolarTerm(36.124, 50.64, -1.3, 0.6215, 3, 0, 0, 0),
        SolarTerm(-13.193, -16.4, 0.258, -0.1187, 3, 0, 0, -2),
        SolarTerm(-1.187, -0.74, 0.042, 0.0074, 3, 0, 0, -4),
        SolarTerm(-0.293, -0.31, -0.002, 0.0046, 3, 0, 0, -6),
        SolarTerm(-0.29, -1.45, 0.116, -0.0051, 2, 1, 0, 2),
        SolarTerm(-7.649, -10.56, 0.259, -0.1038, 2, 1, 0, 0),
        SolarTerm(-8.627, -7.59, 0.078, -0.0192, 2, 1, 0, -2),
        SolarTerm(-2.74, -2.54, 0.022, 0.0324, 2, 1, 0, -4),
        SolarTerm(1.181, 3.32, -0.212, 0.0213, 2, -1, 0, 2),
        SolarTerm(9.703, 11.67, -0.151, 0.1268, 2, -1, 0, 0),
        SolarTerm(-0.352, -0.37, 0.001, -0.0028, 2, -1, 0, -1),
        SolarTerm(-2.494, -1.17, -0.003, -0.0017, 2, -1, 0, -2),
        SolarTerm(0.36, 0.2, -0.012, -0.0043, 2, -1, 0, -4),
        SolarTerm(-1.167, -1.25, 0.008, -0.0106, 1, 2, 0, 0),
        SolarTerm(-7.412, -6.12, 0.117, 0.0484, 1, 2, 0, -2),
        SolarTerm(-0.311, -0.65, -0.032, 0.0044, 1, 2, 0, -4),
        SolarTerm(0.757, 1.82, -0.105, 0.0112, 1, -2, 0, 2),
        SolarTerm(2.58, 2.32, 0.027, 0.0196, 1, -2, 0, 0),
        SolarTerm(2.533, 2.4, -0.014, -0.0212, 1, -2, 0, -2),
        SolarTerm(-0.344, -0.57, -0.025, 0.0036, 0, 3, 0, -2),
        SolarTerm(-0.992, -0.02, 0.0, 0.0, 1, 0, 2, 2),
        SolarTerm(-45.099, -0.02, 0.0, -0.001, 1, 0, 2, 0),
        SolarTerm(-0.179, -9.52, 0.0, -0.0833, 1, 0, 2, -2),
        SolarTerm(-0.301, -0.33, 0.0, 0.0014, 1, 0, 2, -4),
        SolarTerm(-6.382, -3.37, 0.0, -0.0481, 1, 0, -2, 2),
        SolarTerm(39.528, 85.13, 0.0, -0.7136, 1, 0, -2, 0),
        SolarTerm(9.366, 0.71, 0.0, -0.0112, 1, 0, -2, -2),
        SolarTerm(0.202, 0.02, 0.0, 0.0, 1, 0, -2, -4),
        SolarTerm(0.415, 0.1, 0.0, 0.0013, 0, 1, 2, 0),
        SolarTerm(-2.152, -2.26, 0.0, -0.0066, 0, 1, 2, -2),
        SolarTerm(-1.44, -1.3, 0.0, 0.0014, 0, 1, -2, 2),
        SolarTerm(0.384, -0.04, 0.0, 0.0, 0, 1, -2, -2),
        SolarTerm(1.938, 3.6, -0.145, 0.0401, 4, 0, 0, 0),
        SolarTerm(-0.952, -1.58, 0.052, -0.013, 4, 0, 0, -2),
        SolarTerm(-0.551, -0.94, 0.032, -0.0097, 3, 1, 0, 0),
        SolarTerm(-0.482, -0.57, 0.005, -0.0045, 3, 1, 0, -2),
        SolarTerm(0.681, 0.96, -0.026, 0.0115, 3, -1, 0, 0),
        SolarTerm(-0.297, -0.27, 0.002, -0.0009, 2, 2, 0, -2),
        SolarTerm(0.254, 0.21, -0.003, 0.0, 2, -2, 0, -2),
        SolarTerm(-0.25, -0.22, 0.004, 0.0014, 1, 3, 0, -2),
        SolarTerm(-3.996, 0.0, 0.0, 0.0004, 2, 0, 2, 0),
        SolarTerm(0.557, -0.75, 0.0, -0.009, 2, 0, 2, -2),
        SolarTerm(-0.459, -0.38, 0.0, -0.0053, 2, 0, -2, 2),
        SolarTerm(-1.298, 0.74, 0.0, 0.0004, 2, 0, -2, 0),
        SolarTerm(0.538, 1.14, 0.0, -0.0141, 2, 0, -2, -2),
        SolarTerm(0.263, 0.02, 0.0, 0.0, 1, 1, 2, 0),
        SolarTerm(0.426, 0.07, 0.0, -0.0006, 1, 1, -2, -2),
        SolarTerm(-0.304, 0.03, 0.0, 0.0003, 1, -1, 2, 0),
        SolarTerm(-0.372, -0.19, 0.0, -0.0027, 1, -1, -2, 2),
        SolarTerm(0.418, 0.0, 0.0, 0.0, 0, 0, 4, 0),
        SolarTerm(-0.33, -0.04, 0.0, 0.0, 3, 0, 2, 0),
    ]

    static let nTerms: [NTerm] = [
        NTerm(-526.069, 0, 0, 1, -2),
        NTerm(-3.352, 0, 0, 1, -4),
        NTerm(44.297, 1, 0, 1, -2),
        NTerm(-6.0, 1, 0, 1, -4),
        NTerm(20.599, -1, 0, 1, 0),
        NTerm(-30.598, -1, 0, 1, -2),
        NTerm(-24.649, -2, 0, 1, 0),
        NTerm(-2.0, -2, 0, 1, -2),
        NTerm(-22.571, 0, 1, 1, -2),
        NTerm(10.985, 0, -1, 1, -2),
    ]

    /// Ecliptic coordinates of the Moon in the mean equinox of date.
    struct Position: Sendable {
        /// Geocentric ecliptic longitude, radians.
        let longitude: Double
        /// Geocentric ecliptic latitude, radians.
        let latitude: Double
        /// Distance in AU.
        let distance: Double
    }

    /// Cosine/sine tables CO(-6...6, 1...4) and SI(-6...6, 1...4) from `MoonContext`.
    private struct Harmonics {
        var co = [Double](repeating: 0, count: 13 * 4)
        var si = [Double](repeating: 0, count: 13 * 4)
        @inline(__always) static func index(_ x: Int, _ y: Int) -> Int { (x + 6) * 4 + (y - 1) }
        @inline(__always) func c(_ x: Int, _ y: Int) -> Double { co[Self.index(x, y)] }
        @inline(__always) func s(_ x: Int, _ y: Int) -> Double { si[Self.index(x, y)] }

        /// Port of `Term`: returns (cos, sin) of p·l + q·l' + r·F + s·D.
        func term(_ p: Int, _ q: Int, _ r: Int, _ s: Int) -> (x: Double, y: Double) {
            var x = 1.0, y = 0.0
            @inline(__always) func add(_ i: Int, _ k: Int) {
                guard i != 0 else { return }
                let c2 = c(i, k), s2 = self.s(i, k)
                (x, y) = (x * c2 - y * s2, y * c2 + x * s2)
            }
            add(p, 1)
            add(q, 2)
            add(r, 3)
            add(s, 4)
            return (x, y)
        }
    }

    @inline(__always) private static func frac(_ x: Double) -> Double { x - floor(x) }
    @inline(__always) private static func sine(_ phi: Double) -> Double { sin(AstroConstants.pi2 * phi) }

    /// Port of `CalcMoon`. `t` is Julian centuries of TT since J2000.
    static func calc(_ t: Double) -> Position {
        let arc = AstroConstants.arc
        let pi2 = AstroConstants.pi2

        // LongPeriodic
        let s1 = sine(0.19833 + 0.05611 * t)
        let s2 = sine(0.27869 + 0.04508 * t)
        let s3 = sine(0.16827 - 0.36903 * t)
        let s4 = sine(0.34734 - 5.37261 * t)
        let s5 = sine(0.10498 - 5.37899 * t)
        let s6 = sine(0.42681 - 0.41855 * t)
        let s7 = sine(0.14943 - 5.37511 * t)
        let dl0 = 0.84 * s1 + 0.31 * s2 + 14.27 * s3 + 7.26 * s4 + 0.28 * s5 + 0.24 * s6
        let dl = 2.94 * s1 + 0.31 * s2 + 14.27 * s3 + 9.34 * s4 + 1.12 * s5 + 0.83 * s6
        let dls = -6.40 * s1 - 1.89 * s6
        let df = 0.21 * s1 + 0.31 * s2 + 14.27 * s3 - 88.70 * s4 - 15.30 * s5 + 0.24 * s6 - 1.86 * s7
        let dd = dl0 - dls
        let dgam = -3332e-9 * sine(0.59734 - 5.37261 * t)
            - 539e-9 * sine(0.35498 - 5.37899 * t)
            - 64e-9 * sine(0.39943 - 5.37511 * t)

        // Init
        let t2 = t * t
        var dlam = 0.0, ds = 0.0, gam1c = 0.0, sinpi = 3422.7000
        let l0 = pi2 * frac(0.60643382 + 1336.85522467 * t - 0.00000313 * t2) + dl0 / arc
        let l = pi2 * frac(0.37489701 + 1325.55240982 * t + 0.00002565 * t2) + dl / arc
        let ls = pi2 * frac(0.99312619 + 99.99735956 * t - 0.00000044 * t2) + dls / arc
        let f = pi2 * frac(0.25909118 + 1342.22782980 * t - 0.00000892 * t2) + df / arc
        let d = pi2 * frac(0.82736186 + 1236.85308708 * t - 0.00000397 * t2) + dd / arc

        var h = Harmonics()
        for i in 1...4 {
            let arg: Double, maxJ: Int, fac: Double
            switch i {
            case 1: arg = l; maxJ = 4; fac = 1.000002208
            case 2: arg = ls; maxJ = 3; fac = 0.997504612 - 0.002495388 * t
            case 3: arg = f; maxJ = 4; fac = 1.000002708 + 139.978 * dgam
            default: arg = d; maxJ = 6; fac = 1.0
            }
            h.co[Harmonics.index(0, i)] = 1.0
            h.co[Harmonics.index(1, i)] = cos(arg) * fac
            h.si[Harmonics.index(0, i)] = 0.0
            h.si[Harmonics.index(1, i)] = sin(arg) * fac
            if maxJ >= 2 {
                for j in 2...maxJ {
                    let c1 = h.c(j - 1, i), sn1 = h.s(j - 1, i)
                    let c2 = h.c(1, i), sn2 = h.s(1, i)
                    h.co[Harmonics.index(j, i)] = c1 * c2 - sn1 * sn2
                    h.si[Harmonics.index(j, i)] = sn1 * c2 + c1 * sn2
                }
            }
            for j in 1...maxJ {
                h.co[Harmonics.index(-j, i)] = h.c(j, i)
                h.si[Harmonics.index(-j, i)] = -h.s(j, i)
            }
        }

        // AddSol
        for term in solarTerms {
            let (x, y) = h.term(term.p0, term.q, term.r, term.s0)
            dlam += term.l * y
            ds += term.s * y
            gam1c += term.g * x
            sinpi += term.p * x
        }

        // SolarN
        var n = 0.0
        for term in nTerms {
            n += term.n * h.term(term.p, term.q, term.r, term.s).y
        }

        // Planetary
        dlam += 0.82 * sine(0.7736 - 62.5512 * t) + 0.31 * sine(0.0466 - 125.1025 * t)
        dlam += 0.35 * sine(0.5785 - 25.1042 * t) + 0.66 * sine(0.4591 + 1335.8075 * t)
        dlam += 0.64 * sine(0.3130 - 91.5680 * t) + 1.14 * sine(0.1480 + 1331.2898 * t)
        dlam += 0.21 * sine(0.5918 + 1056.5859 * t) + 0.44 * sine(0.5784 + 1322.8595 * t)
        dlam += 0.24 * sine(0.2275 - 5.7374 * t) + 0.28 * sine(0.2965 + 2.6929 * t)
        dlam += 0.33 * sine(0.3132 + 6.3368 * t)

        let sArg = f + ds / arc
        let latSeconds = (1.000002708 + 139.978 * dgam) * (18518.511 + 1.189 + gam1c) * sin(sArg)
            - 6.24 * sin(3 * sArg) + n

        return Position(
            longitude: pi2 * frac((l0 + dlam / arc) / pi2),
            latitude: latSeconds * (AstroConstants.deg2rad / 3600.0),
            distance: (arc * AstroConstants.earthEquatorialRadiusAU) / (0.999953253 * sinpi)
        )
    }

    /// Geocentric Moon vector in J2000 equatorial coordinates (AU). Port of `Astronomy_GeoMoon`.
    static func geoMoon(_ time: AstroTime) -> Vec3 {
        let m = calc(time.tt / 36525.0)
        let distCosLat = m.distance * cos(m.latitude)
        let ecl = Vec3(distCosLat * cos(m.longitude), distCosLat * sin(m.longitude), m.distance * sin(m.latitude))
        let mean = eclipticToEquatorial(obliquity: meanObliquity(tt: time.tt), ecl)
        return precessionRotation(time, .into2000).rotate(mean)
    }
}
