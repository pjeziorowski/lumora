// Packages/PlannerKit/Sources/PlannerKit/AR/ARProjection.swift
//
// Geometry for the AR views: device attitude → the direction the back camera looks
// (azimuth, elevation, roll), compass and horizon calibration, and a rectilinear (pinhole)
// projection of sky directions onto the camera preview. No CoreMotion or UIKit here; the app
// passes in the attitude matrix and the preview size.
//
// World frame: east-north-up (ENU), azimuth clockwise from true north. Device frame (Apple's
// convention): x to the right of the screen, y to its top, z out of the screen toward the
// user, so the back camera looks along −z.

import Foundation

/// A direction or point in the local east-north-up frame.
public struct ARVector: Sendable, Hashable {
    public var east: Double
    public var north: Double
    public var up: Double

    public init(east: Double, north: Double, up: Double) {
        self.east = east
        self.north = north
        self.up = up
    }

    /// Unit vector toward an azimuth/elevation in degrees.
    public init(azimuth: Double, elevation: Double) {
        let a = azimuth * .pi / 180, e = elevation * .pi / 180
        self.init(east: cos(e) * sin(a), north: cos(e) * cos(a), up: sin(e))
    }

    public static let upward = ARVector(east: 0, north: 0, up: 1)

    public var length: Double { (east * east + north * north + up * up).squareRoot() }
    public var normalized: ARVector { let l = length; return l > 0 ? self * (1 / l) : self }

    /// Azimuth in [0, 360) and elevation in degrees.
    public var azimuth: Double { ARAngles.wrap(atan2(east, north) * 180 / .pi) }
    public var elevation: Double { asin(max(-1, min(1, up / max(length, .leastNormalMagnitude)))) * 180 / .pi }

    public func dot(_ o: ARVector) -> Double { east * o.east + north * o.north + up * o.up }
    public func cross(_ o: ARVector) -> ARVector {
        ARVector(east: north * o.up - up * o.north, north: up * o.east - east * o.up, up: east * o.north - north * o.east)
    }

    /// Rotates about `axis` (unit) by `degrees`, right-handed (Rodrigues).
    public func rotated(about axis: ARVector, degrees: Double) -> ARVector {
        let t = degrees * .pi / 180
        let k = axis.normalized
        return self * cos(t) + k.cross(self) * sin(t) + k * (k.dot(self) * (1 - cos(t)))
    }

    public static func + (a: ARVector, b: ARVector) -> ARVector {
        ARVector(east: a.east + b.east, north: a.north + b.north, up: a.up + b.up)
    }

    public static func - (a: ARVector, b: ARVector) -> ARVector {
        ARVector(east: a.east - b.east, north: a.north - b.north, up: a.up - b.up)
    }

    public static func * (a: ARVector, s: Double) -> ARVector { ARVector(east: a.east * s, north: a.north * s, up: a.up * s) }
}

public enum ARAngles {
    /// Wraps to [0, 360).
    public static func wrap(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// Wraps to (−180, 180].
    public static func signed(_ degrees: Double) -> Double {
        let r = wrap(degrees)
        return r > 180 ? r - 360 : r
    }
}

/// The device's axes expressed in the world frame.
public struct ARAttitude: Sendable, Hashable {
    /// Right edge of the screen (device +x).
    public var x: ARVector
    /// Top edge of the screen in portrait (device +y).
    public var y: ARVector
    /// Out of the screen toward the user (device +z); the back camera looks along −z.
    public var z: ARVector

    public init(x: ARVector, y: ARVector, z: ARVector) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// From Core Motion's `CMAttitude.rotationMatrix` in the `.xTrueNorthZVertical` reference
    /// frame (X true north, Y west, Z up). The matrix takes reference-frame vectors to device
    /// coordinates, so its rows are the device axes expressed in the reference frame.
    public static func fromCoreMotion(m11: Double, m12: Double, m13: Double,
                                      m21: Double, m22: Double, m23: Double,
                                      m31: Double, m32: Double, m33: Double) -> ARAttitude {
        // Reference (north, west, up) → ENU (east = −west).
        func enu(_ n: Double, _ w: Double, _ u: Double) -> ARVector { ARVector(east: -w, north: n, up: u) }
        return ARAttitude(x: enu(m11, m12, m13), y: enu(m21, m22, m23), z: enu(m31, m32, m33))
    }

    /// A phone held in portrait with the back camera toward `azimuth`/`elevation`, turned
    /// `roll` degrees clockwise (as seen by its user) about the view axis.
    public init(azimuth: Double, elevation: Double, roll: Double = 0) {
        let forward = ARVector(azimuth: azimuth, elevation: elevation)
        let a = azimuth * .pi / 180
        // Horizontal right-hand direction; defined even when looking straight up or down.
        let right0 = ARVector(east: cos(a), north: -sin(a), up: 0)
        let up0 = right0.cross(forward)
        // Seen by the user, looking along `forward`, a right-handed turn about it is clockwise.
        let right = right0.rotated(about: forward, degrees: roll)
        let up = up0.rotated(about: forward, degrees: roll)
        self.init(x: right, y: up, z: forward * -1)
    }
}

/// How the interface is turned relative to the device, so screen right/up can be read from
/// the device axes. Names follow `UIInterfaceOrientation`.
public enum ARScreenOrientation: String, Sendable, Hashable, Codable, CaseIterable {
    /// Home indicator at the bottom: screen right = +x, up = +y.
    case portrait
    /// Upside down: right = −x, up = −y.
    case portraitUpsideDown
    /// Interface landscape-left (device top to the right): right = +y, up = −x.
    case landscapeLeft
    /// Interface landscape-right (device top to the left): right = −y, up = +x.
    case landscapeRight

    func axes(_ a: ARAttitude) -> (right: ARVector, up: ARVector) {
        switch self {
        case .portrait: (a.x, a.y)
        case .portraitUpsideDown: (a.x * -1, a.y * -1)
        case .landscapeLeft: (a.y, a.x * -1)
        case .landscapeRight: (a.y * -1, a.x)
        }
    }
}

/// Compass and horizon corrections. `heading` is added to the view's azimuth and `pitch` to
/// its elevation; both are set with sliders or by centring a known object.
public struct ARCalibration: Sendable, Hashable, Codable {
    public var heading: Double
    public var pitch: Double

    public init(heading: Double = 0, pitch: Double = 0) {
        self.heading = heading
        self.pitch = pitch
    }

    public static let none = ARCalibration()

    /// The calibration that puts `actual` (azimuth, elevation) at the centre of a view whose
    /// calibrated axis currently points at `view`.
    public func aligning(view: (azimuth: Double, elevation: Double),
                         to actual: (azimuth: Double, elevation: Double)) -> ARCalibration {
        ARCalibration(heading: ARAngles.signed(heading + ARAngles.signed(actual.azimuth - view.azimuth)),
                      pitch: pitch + (actual.elevation - view.elevation))
    }
}

/// A point on the preview in points from the top-left corner.
public struct ARScreenPoint: Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum ARLens {
    /// Focal length in screen points for a preview that fills `width × height` (aspect fill)
    /// with a camera whose horizontal field of view across its long side is
    /// `cameraFieldOfView` degrees and whose frame has `aspect` (long / short, 4:3 = 1.333).
    public static func focalPoints(cameraFieldOfView: Double, aspect: Double = 4.0 / 3.0,
                                   width: Double, height: Double) -> Double {
        let tanLong = tan(cameraFieldOfView / 2 * .pi / 180)
        let tanShort = tanLong / aspect
        let (longSide, shortSide) = width >= height ? (width, height) : (height, width)
        // Aspect fill: the scale that covers both sides; the other side is cropped.
        return max(longSide / (2 * tanLong), shortSide / (2 * tanShort))
    }

    /// Focal length in points for a view `width` points wide showing `horizontal` degrees.
    public static func focalPoints(horizontalFieldOfView horizontal: Double, width: Double) -> Double {
        width / (2 * tan(max(1, min(170, horizontal)) / 2 * .pi / 180))
    }

    /// Field of view in degrees across `size` points at focal length `focal` points.
    public static func fieldOfView(size: Double, focal: Double) -> Double {
        2 * atan(size / (2 * focal)) * 180 / .pi
    }
}

/// Projects world directions onto the preview with a pinhole model.
public struct ARProjector: Sendable {
    public let forward: ARVector
    public let right: ARVector
    public let up: ARVector
    public let focal: Double
    public let width: Double
    public let height: Double

    public init(attitude: ARAttitude, orientation: ARScreenOrientation = .portrait, calibration: ARCalibration = .none,
                focal: Double, width: Double, height: Double) {
        let axes = orientation.axes(attitude)
        var f = (attitude.z * -1).normalized
        var r = axes.right.normalized
        var u = axes.up.normalized
        // Horizon: tilt the view about its own horizontal axis.
        if calibration.pitch != 0 {
            let horizontal = f.cross(ARVector.upward)
            if horizontal.length > 1e-9 {
                // A right-handed turn about the level right-hand axis raises the view.
                let axis = horizontal.normalized
                f = f.rotated(about: axis, degrees: calibration.pitch)
                r = r.rotated(about: axis, degrees: calibration.pitch)
                u = u.rotated(about: axis, degrees: calibration.pitch)
            }
        }
        // Compass: turn everything about the vertical (clockwise from above = negative).
        if calibration.heading != 0 {
            f = f.rotated(about: .upward, degrees: -calibration.heading)
            r = r.rotated(about: .upward, degrees: -calibration.heading)
            u = u.rotated(about: .upward, degrees: -calibration.heading)
        }
        forward = f
        right = r
        up = u
        self.focal = focal
        self.width = width
        self.height = height
    }

    public var viewAzimuth: Double { forward.azimuth }
    public var viewElevation: Double { forward.elevation }
    /// Clockwise turn of the phone about the view axis, degrees; the horizon then appears
    /// tilted the other way on screen.
    public var roll: Double {
        let level = forward.cross(.upward)
        guard level.length > 1e-9 else { return 0 }
        let r0 = level.normalized
        return atan2(r0.cross(right).dot(forward), r0.dot(right)) * 180 / .pi
    }

    public var horizontalFieldOfView: Double { ARLens.fieldOfView(size: width, focal: focal) }
    public var verticalFieldOfView: Double { ARLens.fieldOfView(size: height, focal: focal) }

    /// Screen position of a direction, or nil when it is behind the camera.
    public func project(_ v: ARVector) -> ARScreenPoint? {
        let d = v.normalized
        let z = d.dot(forward)
        guard z > 0.02 else { return nil }
        return ARScreenPoint(x: width / 2 + focal * d.dot(right) / z, y: height / 2 - focal * d.dot(up) / z)
    }

    public func project(azimuth: Double, elevation: Double) -> ARScreenPoint? {
        project(ARVector(azimuth: azimuth, elevation: elevation))
    }

    /// The direction seen at a screen point.
    public func direction(at p: ARScreenPoint) -> ARVector {
        (forward * focal + right * (p.x - width / 2) - up * (p.y - height / 2)).normalized
    }

    /// Whether a point lies on the preview, with `margin` points of slack.
    public func isOnScreen(_ p: ARScreenPoint, margin: Double = 0) -> Bool {
        p.x >= -margin && p.x <= width + margin && p.y >= -margin && p.y <= height + margin
    }

    /// Projects a polyline, splitting it where it passes behind the camera or leaves the
    /// preview far enough to make a straight segment misleading.
    public func polylines(_ points: [ARVector]) -> [[ARScreenPoint]] {
        var result: [[ARScreenPoint]] = []
        var current: [ARScreenPoint] = []
        let limit = 4 * max(width, height)
        for v in points {
            if let p = project(v), abs(p.x - width / 2) < limit, abs(p.y - height / 2) < limit {
                current.append(p)
            } else {
                if current.count > 1 { result.append(current) }
                current = []
            }
        }
        if current.count > 1 { result.append(current) }
        return result
    }
}
