// Packages/AstroCore/Sources/AstroCore/Constants.swift
//
// Physical and numeric constants. Values are taken verbatim from Astronomy Engine
// (MIT, Don Cross, https://github.com/cosinekitty/astronomy), source/c/astronomy.c.

import Foundation

public enum AstroConstants {
    /// Kilometres per astronomical unit.
    public static let kmPerAU = 1.4959787069098932e+8
    /// Speed of light in AU per day.
    public static let cAUPerDay = 173.1446326846693
    /// Mean synodic month in days.
    public static let meanSynodicMonth = 29.530588
    /// Standard atmospheric refraction at the horizon, in degrees (34').
    public static let refractionNearHorizon = 34.0 / 60.0

    public static let sunRadiusKm = 695_700.0
    public static let moonEquatorialRadiusKm = 1738.1
    public static let moonMeanRadiusKm = 1737.4
    public static let earthEquatorialRadiusKm = 6378.1366
    public static let earthFlattening = 0.996647180302104

    static let sunRadiusAU = sunRadiusKm / kmPerAU
    static let moonEquatorialRadiusAU = moonEquatorialRadiusKm / kmPerAU
    static let earthEquatorialRadiusAU = earthEquatorialRadiusKm / kmPerAU
    static let earthFlatteningSquared = earthFlattening * earthFlattening

    static let daysPerTropicalYear = 365.24217
    static let solarDaysPerSiderealDay = 0.9972695717592592
    static let secondsPerDay = 86_400.0
    static let asec360 = 1_296_000.0
    static let asec2rad = 4.848136811095359935899141e-6
    /// Arcseconds per radian.
    static let arc = 3600.0 * 180.0 / Double.pi
    static let deg2rad = Double.pi / 180.0
    static let rad2deg = 180.0 / Double.pi
    static let hour2rad = Double.pi / 12.0
    static let rad2hour = 12.0 / Double.pi
    static let pi2 = 2.0 * Double.pi
}

/// Wraps an angle difference into (-180, +180]. Port of Astronomy Engine `LongitudeOffset`.
@inlinable
func longitudeOffset(_ diff: Double) -> Double {
    var offset = diff
    while offset <= -180 { offset += 360 }
    while offset > 180 { offset -= 360 }
    return offset
}

/// Wraps an angle into [0, 360). Port of Astronomy Engine `NormalizeLongitude`.
@inlinable
func normalizeLongitude(_ lon: Double) -> Double {
    var value = lon.truncatingRemainder(dividingBy: 360)
    if value < 0 { value += 360 }
    return value
}
