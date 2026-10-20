// Packages/PlannerKit/Sources/PlannerKit/Geodetics/MapOptics.swift
//
// Field of view and depth of field drawn on the Planner map from the observer pin: the
// horizontal angle of view as a wedge along a bearing, and arcs across it at the near
// limit, the focus distance and the far limit of acceptable sharpness. The bearing is the
// target pin's when there is one, else the one the user set. Numbers come from OpticsCore.

import Foundation
import GeoCore
import OpticsCore

public struct MapOptics: Sendable, Hashable, Codable {
    public var showFieldOfView = false
    public var showDepthOfField = false
    public var focalLength = 24.0
    public var aperture = 8.0
    /// Focus distance in metres, used when not focusing on the target pin.
    public var focusDistance = 500.0
    /// Focus at the target pin's distance when there is one.
    public var focusOnTarget = true
    public var orientation: Orientation = .landscape
    /// Bearing (degrees) used when there is no target pin.
    public var bearing = 0.0

    public init() {}

    public var isVisible: Bool { showFieldOfView || showDepthOfField }
}

/// The resolved geometry, in metres and degrees, for display and tests.
public struct MapOpticsGeometry: Sendable, Hashable {
    public let bearing: Double
    public let horizontalAngle: Double
    public let focus: Double
    public let near: Double
    /// Far limit, or nil when it is at infinity.
    public let far: Double?
    public let hyperfocal: Double
    /// Length of the wedge's edges.
    public let length: Double

    public static func compute(_ o: MapOptics, sensor: Sensor, coc: Double, targetDistance: Double?, targetBearing: Double?,
                               radius: Double) -> MapOpticsGeometry {
        let fov = FieldOfView.compute(sensor: sensor, focalLength: o.focalLength, distance: 1, orientation: o.orientation)
        let focus = max(0.1, (o.focusOnTarget ? targetDistance : nil) ?? o.focusDistance)
        let r = DepthOfField.compute(DoFInput(focalLength: o.focalLength, aperture: o.aperture, distance: focus * 1000, coc: coc))
        let far = r.far.isFinite ? r.far / 1000 : nil
        let length = max(radius, focus * 1.3, (far ?? 0) * 1.15, (targetDistance ?? 0) * 1.15)
        return MapOpticsGeometry(bearing: targetBearing ?? o.bearing, horizontalAngle: fov.horizontal, focus: focus,
                                 near: r.near / 1000, far: far, hyperfocal: r.hyperfocal / 1000, length: length)
    }
}

extension PlannerOverlays {
    /// Wedge edges and depth-of-field arcs for `optics`, as map lines from `pin`.
    public static func opticsLines(_ optics: MapOptics, geometry g: MapOpticsGeometry, pin: GeoPoint) -> [OverlayLine] {
        guard optics.isVisible else { return [] }
        var lines: [OverlayLine] = []
        let half = g.horizontalAngle / 2
        func point(_ bearing: Double, _ distance: Double) -> GeoPoint {
            Geodesy.destination(from: pin, bearing: bearing, distance: distance).unwrapped(near: pin.longitude)
        }
        func arc(_ distance: Double) -> [GeoPoint] {
            let steps = max(4, Int(g.horizontalAngle / 3))
            return (0...steps).map { point(g.bearing - half + g.horizontalAngle * Double($0) / Double(steps), distance) }
        }
        if optics.showFieldOfView {
            for (i, side) in [-half, half].enumerated() {
                lines.append(OverlayLine(body: .camera, role: .fovEdge, isAboveHorizon: true,
                                         points: [pin, point(g.bearing + side, g.length)], index: i))
            }
            lines.append(OverlayLine(body: .camera, role: .fovCenter, isAboveHorizon: true,
                                     points: [pin, point(g.bearing, g.length)], index: 0))
        }
        if optics.showDepthOfField {
            lines.append(OverlayLine(body: .camera, role: .dofNear, isAboveHorizon: true, points: arc(g.near), index: 0))
            lines.append(OverlayLine(body: .camera, role: .focus, isAboveHorizon: true, points: arc(g.focus), index: 0))
            if let far = g.far {
                lines.append(OverlayLine(body: .camera, role: .dofFar, isAboveHorizon: true, points: arc(far), index: 0))
            }
        }
        return lines
    }

    /// The line from the observer pin to the target pin.
    public static func targetLine(pin: GeoPoint, target: GeoPoint) -> OverlayLine {
        OverlayLine(body: .target, role: .now, isAboveHorizon: true,
                    points: [pin, target.unwrapped(near: pin.longitude)], index: 0)
    }
}
