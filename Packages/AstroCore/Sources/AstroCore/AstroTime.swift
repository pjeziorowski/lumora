// Packages/AstroCore/Sources/AstroCore/AstroTime.swift
//
// Time scales. Port of Astronomy Engine `astro_time_t`, `Astronomy_MakeTime`,
// `Astronomy_AddDays`, `TerrestrialTime`, `Astronomy_DeltaT_EspenakMeeus`
// and the NOVAS-derived calendar conversion in `Astronomy_UtcFromTime`.

import Foundation

/// An instant expressed both as Universal Time (UT1 ≈ UTC) and Terrestrial Time,
/// each counted in days since the J2000 epoch (2000-01-01T12:00:00Z).
public struct AstroTime: Sendable, Hashable, Comparable {
    /// UT days since J2000. Used for anything tied to Earth's rotation.
    public let ut: Double
    /// TT days since J2000. Used for orbital motion.
    public let tt: Double

    /// Unix timestamp of the J2000 epoch, 2000-01-01T12:00:00Z.
    static let j2000UnixSeconds = 946_728_000.0

    public init(ut: Double) {
        self.ut = ut
        self.tt = ut + DeltaT.espenakMeeus(ut: ut) / AstroConstants.secondsPerDay
    }

    /// Creates a time from Terrestrial Time days, solving for UT (inverse of `TerrestrialTime`).
    public init(tt: Double) {
        var dt = AstroTime(ut: tt).tt - tt
        while true {
            let ut = tt - dt
            let err = AstroTime(ut: ut).tt - tt
            if abs(err) < 1.0e-12 {
                self.ut = ut
                self.tt = tt
                return
            }
            dt += err
        }
    }

    public init(_ date: Date) {
        self.init(ut: (date.timeIntervalSince1970 - Self.j2000UnixSeconds) / AstroConstants.secondsPerDay)
    }

    /// Creates a time from a UTC Gregorian calendar date (proleptic before 1582).
    /// Port of `Astronomy_MakeTime` (Fliegel & Van Flandern via NOVAS `julian_date`).
    public init(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Double = 0) {
        let y = Int64(year), m = Int64(month), d = Int64(day)
        let f = (14 - m) / 12
        var y2000 = d - 365_972_956
        y2000 += (1461 * (y + 1_000_000 - f)) / 4
        y2000 += (367 * (m - 2 + 12 * f)) / 12
        y2000 -= (3 * ((y + 1_000_100 - f) / 100)) / 4
        let ut = (Double(y2000) - 0.5) + Double(hour) / 24 + Double(minute) / 1440 + second / 86_400
        self.init(ut: ut)
    }

    public var date: Date {
        Date(timeIntervalSince1970: ut * AstroConstants.secondsPerDay + Self.j2000UnixSeconds)
    }

    /// Julian Day number on the UT scale.
    public var julianDay: Double { ut + 2_451_545.0 }

    /// ΔT = TT − UT in seconds.
    public var deltaT: Double { (tt - ut) * AstroConstants.secondsPerDay }

    /// Adds days on the UT scale (Astronomy Engine `Astronomy_AddDays`).
    public func addingDays(_ days: Double) -> AstroTime { AstroTime(ut: ut + days) }

    public static func < (lhs: AstroTime, rhs: AstroTime) -> Bool { lhs.tt < rhs.tt }
}

/// ΔT models.
public enum DeltaT {
    /// Espenak & Meeus piecewise polynomials, "Five Millennium Canon of Solar Eclipses".
    /// Port of `Astronomy_DeltaT_EspenakMeeus`. Returns seconds.
    public static func espenakMeeus(ut: Double) -> Double {
        let y = 2000 + ((ut - 14) / AstroConstants.daysPerTropicalYear)
        if y < -500 {
            let u = (y - 1820) / 100
            return -20 + 32 * u * u
        }
        if y < 500 {
            let u = y / 100
            let u2 = u * u, u3 = u * u2, u4 = u2 * u2, u5 = u2 * u3, u6 = u3 * u3
            return 10583.6 - 1014.41 * u + 33.78311 * u2 - 5.952053 * u3 - 0.1798452 * u4 + 0.022174192 * u5 + 0.0090316521 * u6
        }
        if y < 1600 {
            let u = (y - 1000) / 100
            let u2 = u * u, u3 = u * u2, u4 = u2 * u2, u5 = u2 * u3, u6 = u3 * u3
            return 1574.2 - 556.01 * u + 71.23472 * u2 + 0.319781 * u3 - 0.8503463 * u4 - 0.005050998 * u5 + 0.0083572073 * u6
        }
        if y < 1700 {
            let u = y - 1600
            let u2 = u * u, u3 = u * u2
            return 120 - 0.9808 * u - 0.01532 * u2 + u3 / 7129.0
        }
        if y < 1800 {
            let u = y - 1700
            let u2 = u * u, u3 = u * u2, u4 = u2 * u2
            return 8.83 + 0.1603 * u - 0.0059285 * u2 + 0.00013336 * u3 - u4 / 1_174_000
        }
        if y < 1860 {
            let u = y - 1800
            let u2 = u * u, u3 = u * u2, u4 = u2 * u2, u5 = u2 * u3, u6 = u3 * u3, u7 = u3 * u4
            var r = 13.72 - 0.332447 * u + 0.0068612 * u2 + 0.0041116 * u3
            r += -0.00037436 * u4 + 0.0000121272 * u5 - 0.0000001699 * u6 + 0.000000000875 * u7
            return r
        }
        if y < 1900 {
            let u = y - 1860
            let u2 = u * u, u3 = u * u2, u4 = u2 * u2, u5 = u2 * u3
            return 7.62 + 0.5737 * u - 0.251754 * u2 + 0.01680668 * u3 - 0.0004473624 * u4 + u5 / 233_174
        }
        if y < 1920 {
            let u = y - 1900
            let u2 = u * u, u3 = u * u2, u4 = u2 * u2
            return -2.79 + 1.494119 * u - 0.0598939 * u2 + 0.0061966 * u3 - 0.000197 * u4
        }
        if y < 1941 {
            let u = y - 1920
            let u2 = u * u, u3 = u * u2
            return 21.20 + 0.84493 * u - 0.076100 * u2 + 0.0020936 * u3
        }
        if y < 1961 {
            let u = y - 1950
            let u2 = u * u, u3 = u * u2
            return 29.07 + 0.407 * u - u2 / 233 + u3 / 2547
        }
        if y < 1986 {
            let u = y - 1975
            let u2 = u * u, u3 = u * u2
            return 45.45 + 1.067 * u - u2 / 260 - u3 / 718
        }
        if y < 2005 {
            let u = y - 2000
            let u2 = u * u, u3 = u * u2, u4 = u2 * u2, u5 = u2 * u3
            return 63.86 + 0.3345 * u - 0.060374 * u2 + 0.0017275 * u3 + 0.000651814 * u4 + 0.00002373599 * u5
        }
        if y < 2050 {
            let u = y - 2000
            return 62.92 + 0.32217 * u + 0.005589 * u * u
        }
        if y < 2150 {
            let u = (y - 1820) / 100
            return -20 + 32 * u * u - 0.5628 * (2150 - y)
        }
        let u = (y - 1820) / 100
        return -20 + 32 * u * u
    }
}
