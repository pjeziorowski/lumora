// Packages/GeoCore/Sources/GeoCore/Sightline.swift
//
// Lines of sight over a curved, refracting Earth: how far a distant point drops below the
// observer's horizontal plane, the apparent elevation angle of that point, and the height
// a point must have to appear at a given angle. Used to tell whether the Sun or Moon clears
// a ridge or building seen from the observer pin.
//
// Model (standard surveying correction): a ray bends with the Earth but less sharply, which
// is the same as straight rays over an Earth of radius k·R. With refraction coefficient
// κ ≈ 0.13, k = 1 / (1 − κ) ≈ 1.15. The drop at distance d is d² / (2·k·R) and the
// apparent elevation of a point h₂ seen from h₁ is atan((h₂ − h₁ − d²/(2kR)) / d).

import Foundation

public enum Sightline {
    /// Effective Earth-radius factor for standard atmospheric refraction (κ = 0.13).
    public static let standardRefraction = 1.15

    /// How far a point at horizontal distance `distance` (m) lies below the observer's
    /// tangent plane, combining curvature and refraction. `k = 1` gives curvature only.
    public static func drop(distance: Double, k: Double = standardRefraction) -> Double {
        distance * distance / (2 * k * Geodesy.meanRadius)
    }

    /// Apparent elevation angle (degrees) of a point at height `targetHeight` (m above sea
    /// level) and `distance` (m) away, seen from `observerHeight` (m above sea level).
    public static func apparentElevation(observerHeight: Double, targetHeight: Double, distance: Double,
                                         k: Double = standardRefraction) -> Double {
        guard distance > 0 else { return targetHeight >= observerHeight ? 90 : -90 }
        return atan((targetHeight - observerHeight - drop(distance: distance, k: k)) / distance) * 180 / .pi
    }

    /// Height above sea level (m) a point `distance` away must reach to appear at
    /// `angle` degrees from `observerHeight`: the inverse of `apparentElevation`.
    public static func height(forAngle angle: Double, observerHeight: Double, distance: Double,
                              k: Double = standardRefraction) -> Double {
        observerHeight + distance * tan(angle * .pi / 180) + drop(distance: distance, k: k)
    }

    /// Distance (m) to the horizon from `height` metres above a level surface.
    public static func horizonDistance(height: Double, k: Double = standardRefraction) -> Double {
        sqrt(max(0, 2 * k * Geodesy.meanRadius * height))
    }
}
