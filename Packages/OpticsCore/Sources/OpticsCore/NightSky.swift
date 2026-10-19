// Packages/OpticsCore/Sources/OpticsCore/NightSky.swift
//
// Spot stars and star trails (brief §2.10, §2.11, §3.2).
//   500 rule: t = 500 / (f × crop) (the constant is a setting: 500, 600 …)
//   NPF:      t = (35·N + 30·p) / (f · cos δ)
//   accurate: t = (16.856·N + 0.0997·f + 13.713·p) / (f · cos δ)
// with p the pixel pitch in µm and δ the declination of the stars in frame (0 at the
// celestial equator, where they move fastest). Stars move 15.041″ per second of time ×
// cos δ; a trail of angle θ covers θ(rad) × f / p pixels.

import Foundation

public enum SpotStars {
    public static func rule(constant: Double = 500, focalLength f: Double, cropFactor: Double) -> Double {
        constant / (f * cropFactor)
    }

    /// cos δ, with |δ| capped at 89° so the pole does not give an infinite time.
    static func declinationFactor(_ declination: Double) -> Double {
        cos(min(abs(declination), 89) * .pi / 180)
    }

    public static func npf(aperture n: Double, pixelPitchMicrons p: Double, focalLength f: Double,
                           declination: Double = 0) -> Double {
        (35 * n + 30 * p) / (f * declinationFactor(declination))
    }

    public static func npfAccurate(aperture n: Double, pixelPitchMicrons p: Double, focalLength f: Double,
                                   declination: Double = 0) -> Double {
        (16.856 * n + 0.0997 * f + 13.713 * p) / (f * declinationFactor(declination))
    }
}

public struct StarTrailResult: Sendable, Hashable {
    /// Angle the stars sweep, degrees.
    public let angle: Double
    /// Trail length on the sensor in mm, and in pixels when the resolution is known.
    public let lengthMM: Double
    public let lengthPixels: Double?
    /// Trail length as a fraction of the frame width.
    public let fractionOfWidth: Double
}

public enum StarTrails {
    /// Sidereal rate, arcseconds of sky per second of time.
    public static let siderealRate = 15.041

    public static func compute(seconds t: Double, focalLength f: Double, sensor: Sensor, declination: Double = 0) -> StarTrailResult {
        let degrees = siderealRate * t * cos(declination * .pi / 180) / 3600
        let mm = degrees * .pi / 180 * f
        let pitch = sensor.pixelPitchMicrons.map { $0 / 1000 }
        return StarTrailResult(angle: degrees, lengthMM: mm, lengthPixels: pitch.map { mm / $0 },
                               fractionOfWidth: mm / sensor.widthMM)
    }

    /// Exposure time for a trail of `pixels` pixels (inverse of `compute`).
    public static func seconds(forPixels pixels: Double, focalLength f: Double, pixelPitchMicrons p: Double,
                               declination: Double = 0) -> Double {
        let radians = pixels * p / 1000 / f
        return radians * 180 / .pi * 3600 / (siderealRate * cos(declination * .pi / 180))
    }

    /// Exposure time for the stars to sweep `degrees` around the pole (e.g. 360 for a full circle).
    public static func seconds(forArc degrees: Double) -> Double {
        degrees * 3600 / siderealRate
    }
}
