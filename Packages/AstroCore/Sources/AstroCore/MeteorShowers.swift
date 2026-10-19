// Packages/AstroCore/Sources/AstroCore/MeteorShowers.swift
//
// The major annual meteor showers and where their radiants are. Catalogue values (activity
// window, peak solar longitude λ☉ J2000, radiant at the peak, entry speed, population index
// r, ZHR) are from the International Meteor Organization's Meteor Shower Calendar and its
// working list of visual showers (imo.net, "IMO Meteor Shower Calendar 2026"). Radiant drift
// is the approximate daily motion from the IMO radiant tables.

import Foundation

public struct MeteorShower: Sendable, Hashable, Identifiable {
    /// IMO three-letter code, e.g. "PER".
    public let code: String
    public let name: String
    /// Activity window as (month, day), start and end; the window may wrap the year end.
    public let begins: (month: Int, day: Int)
    public let ends: (month: Int, day: Int)
    /// Solar longitude of the peak, degrees, J2000.
    public let peakSolarLongitude: Double
    /// Radiant at the peak, J2000 (RA in degrees here, as IMO lists it).
    public let radiantRA: Double
    public let radiantDec: Double
    /// Radiant drift, degrees of RA and Dec per degree of solar longitude (≈ per day).
    public let driftRA: Double
    public let driftDec: Double
    /// Atmospheric entry speed, km/s.
    public let speed: Double
    /// Population index: how much the count grows per magnitude of fainter limiting magnitude.
    public let populationIndex: Double
    public let zhr: Double

    public var id: String { code }

    public static func == (a: MeteorShower, b: MeteorShower) -> Bool { a.code == b.code }
    public func hash(into hasher: inout Hasher) { hasher.combine(code) }

    /// The radiant on a given solar longitude (J2000), with drift from the peak.
    public func radiant(atSolarLongitude lambda: Double) -> SkyCoordinate {
        let days = longitudeOffset(lambda - peakSolarLongitude)
        var ra = (radiantRA + driftRA * days).truncatingRemainder(dividingBy: 360)
        if ra < 0 { ra += 360 }
        return SkyCoordinate(ra: ra / 15, dec: max(-90, min(90, radiantDec + driftDec * days)))
    }
}

public enum MeteorShowers {
    public static let all: [MeteorShower] = [
        shower("QUA", "Quadrantids", (12, 28), (1, 12), 283.15, 230, 49, 0.8, -0.2, 41, 2.1, 80),
        shower("LYR", "Lyrids", (4, 14), (4, 30), 32.32, 271, 34, 1.1, 0.0, 49, 2.1, 18),
        shower("ETA", "Eta Aquariids", (4, 19), (5, 28), 45.5, 338, -1, 0.9, 0.4, 66, 2.4, 50),
        shower("CAP", "Alpha Capricornids", (7, 3), (8, 15), 127, 306, -9, 0.9, 0.3, 23, 2.5, 5),
        shower("SDA", "Southern Delta Aquariids", (7, 12), (8, 23), 127, 340, -16, 0.8, 0.2, 41, 2.5, 25),
        shower("PER", "Perseids", (7, 17), (8, 24), 140.0, 48, 58, 1.35, 0.12, 59, 2.2, 100),
        shower("DRA", "Draconids", (10, 6), (10, 10), 195.4, 262, 54, 0.0, 0.0, 20, 2.6, 10),
        shower("STA", "Southern Taurids", (9, 10), (11, 20), 197, 32, 9, 0.8, 0.3, 27, 2.3, 5),
        shower("ORI", "Orionids", (10, 2), (11, 7), 208, 95, 16, 0.7, 0.1, 66, 2.5, 20),
        shower("NTA", "Northern Taurids", (10, 20), (12, 10), 230, 58, 22, 0.8, 0.2, 29, 2.3, 5),
        shower("LEO", "Leonids", (11, 6), (11, 30), 235.27, 152, 22, 0.7, -0.4, 71, 2.5, 15),
        shower("GEM", "Geminids", (12, 4), (12, 20), 262.2, 112, 33, 1.0, -0.1, 35, 2.6, 150),
        shower("URS", "Ursids", (12, 17), (12, 26), 270.7, 217, 76, 0.0, -0.3, 33, 3.0, 10),
    ]

    // swiftlint:disable:next function_parameter_count
    private static func shower(_ code: String, _ name: String, _ begins: (Int, Int), _ ends: (Int, Int), _ peak: Double,
                               _ ra: Double, _ dec: Double, _ dRA: Double, _ dDec: Double, _ speed: Double, _ r: Double,
                               _ zhr: Double) -> MeteorShower {
        MeteorShower(code: code, name: name, begins: begins, ends: ends, peakSolarLongitude: peak, radiantRA: ra,
                     radiantDec: dec, driftRA: dRA, driftDec: dDec, speed: speed, populationIndex: r, zhr: zhr)
    }

    public static func shower(code: String) -> MeteorShower? { all.first { $0.code == code } }
}

public enum SolarLongitude {
    /// J2000 mean obliquity of the ecliptic, degrees (IAU 2006: 84381.406″).
    static let obliquityJ2000 = 84_381.406 / 3600

    /// The Sun's geocentric ecliptic longitude referred to the J2000 ecliptic and equinox,
    /// the λ☉ used by the IMO, degrees [0, 360).
    public static func j2000(at time: AstroTime) -> Double {
        let sun = Ephemeris.geoVector(.sun, at: time, aberration: true)
        return Ephemeris.rotateEquatorialToEcliptic(sun, obliquityRadians: obliquityJ2000 * AstroConstants.deg2rad).longitude
    }

    /// The first time after `start` (within `limitDays`) when λ☉ (J2000) equals `lambda`.
    public static func search(_ lambda: Double, after start: AstroTime, limitDays: Double = 366) -> AstroTime? {
        // λ☉ grows by about 0.9856° a day; jump close, then refine.
        let ahead = (lambda - j2000(at: start)).truncatingRemainder(dividingBy: 360)
        let estimate = (ahead < 0 ? ahead + 360 : ahead) / 0.985_609
        guard estimate - 3 <= limitDays else { return nil }
        let t1 = start.addingDays(max(0, estimate - 3)), t2 = start.addingDays(min(limitDays, estimate + 3))
        return Search.ascendingRoot(t1, t2, toleranceSeconds: 1) { longitudeOffset(j2000(at: $0) - lambda) }
    }
}
