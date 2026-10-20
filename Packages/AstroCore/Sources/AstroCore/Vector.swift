// Packages/AstroCore/Sources/AstroCore/Vector.swift
//
// Minimal 3-vector and 3x3 rotation used by the ephemeris. Matrix layout follows
// Astronomy Engine `astro_rotation_t`: `rotate` computes out[i] = Σj rot[j][i]·in[j].

import Foundation

public struct Vec3: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vec3(0, 0, 0)

    public var length: Double { (x * x + y * y + z * z).squareRoot() }

    public func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }

    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static prefix func - (a: Vec3) -> Vec3 { Vec3(-a.x, -a.y, -a.z) }
    public static func * (s: Double, a: Vec3) -> Vec3 { Vec3(s * a.x, s * a.y, s * a.z) }

    /// Angle between two vectors in degrees. Port of `Astronomy_AngleBetween`.
    public func angle(to b: Vec3) -> Double {
        let r = length * b.length
        guard r >= 1.0e-8, r.isFinite else { return .nan }
        let d = dot(b) / r
        if d <= -1 { return 180 }
        if d >= 1 { return 0 }
        return acos(d) * AstroConstants.rad2deg
    }
}

/// 3x3 rotation matrix, stored as rot[i][j] = r{i}{j}.
struct Rotation: Sendable {
    var r00, r01, r02: Double
    var r10, r11, r12: Double
    var r20, r21, r22: Double

    func rotate(_ v: Vec3) -> Vec3 {
        Vec3(
            r00 * v.x + r10 * v.y + r20 * v.z,
            r01 * v.x + r11 * v.y + r21 * v.z,
            r02 * v.x + r12 * v.y + r22 * v.z
        )
    }

    var transposed: Rotation {
        Rotation(r00: r00, r01: r10, r02: r20,
                 r10: r01, r11: r11, r12: r21,
                 r20: r02, r21: r12, r22: r22)
    }
}
