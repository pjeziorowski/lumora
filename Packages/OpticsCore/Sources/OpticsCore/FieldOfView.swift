// Packages/OpticsCore/Sources/OpticsCore/FieldOfView.swift
//
// Field of view (brief §2.9, §3.2): angle = 2·atan(d / 2f) for each sensor dimension,
// frame size at distance D = D·d/f (thin lens, focus at infinity), magnification
// m = f / (D − f), 35 mm equivalent = f × crop. The inverse mode solves the focal length
// or distance for a wanted frame width.

import Foundation

public struct FoVResult: Sendable, Hashable {
    /// Angles of view in degrees.
    public let horizontal: Double
    public let vertical: Double
    public let diagonal: Double
    /// Frame size at the subject distance, mm.
    public let frameWidth: Double
    public let frameHeight: Double
    public let magnification: Double
    public let equivalentFocalLength: Double
}

public enum FieldOfView {
    public static func angle(dimension d: Double, focalLength f: Double) -> Double {
        2 * atan(d / (2 * f)) * 180 / .pi
    }

    public static func compute(sensor: Sensor, focalLength f: Double, distance: Double,
                               orientation: Orientation = .landscape) -> FoVResult {
        let s = orientation == .portrait ? sensor.rotated : sensor
        return FoVResult(
            horizontal: angle(dimension: s.widthMM, focalLength: f),
            vertical: angle(dimension: s.heightMM, focalLength: f),
            diagonal: angle(dimension: s.diagonalMM, focalLength: f),
            frameWidth: distance * s.widthMM / f,
            frameHeight: distance * s.heightMM / f,
            magnification: distance > f ? f / (distance - f) : .infinity,
            equivalentFocalLength: f * sensor.cropFactor
        )
    }

    /// Focal length that frames `frameWidth` at `distance` (mm), across the sensor width.
    public static func focalLength(forFrameWidth frameWidth: Double, distance: Double, sensor: Sensor,
                                   orientation: Orientation = .landscape) -> Double {
        let s = orientation == .portrait ? sensor.rotated : sensor
        return distance * s.widthMM / frameWidth
    }

    /// Distance at which `focalLength` frames `frameWidth` (mm).
    public static func distance(forFrameWidth frameWidth: Double, focalLength: Double, sensor: Sensor,
                                orientation: Orientation = .landscape) -> Double {
        let s = orientation == .portrait ? sensor.rotated : sensor
        return frameWidth * focalLength / s.widthMM
    }

    /// Focal length giving a horizontal angle of view (degrees).
    public static func focalLength(forAngle degrees: Double, dimension: Double) -> Double {
        dimension / (2 * tan(degrees * .pi / 360))
    }
}
