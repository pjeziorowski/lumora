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

    /// Rotation equivalent to applying `self`, then `next`. Port of `Astronomy_CombineRotation`.
    func combined(with next: Rotation) -> Rotation {
        let a = [[r00, r01, r02], [r10, r11, r12], [r20, r21, r22]]
        let b = [[next.r00, next.r01, next.r02], [next.r10, next.r11, next.r12], [next.r20, next.r21, next.r22]]
        func c(_ i: Int, _ j: Int) -> Double { a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j] }
        return Rotation(r00: c(0, 0), r01: c(0, 1), r02: c(0, 2),
                        r10: c(1, 0), r11: c(1, 1), r12: c(1, 2),
                        r20: c(2, 0), r21: c(2, 1), r22: c(2, 2))
    }

    var transposed: Rotation {
        Rotation(r00: r00, r01: r10, r02: r20,
                 r10: r01, r11: r11, r12: r21,
                 r20: r02, r21: r12, r22: r22)
    }
}
