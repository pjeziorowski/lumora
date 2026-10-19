// Packages/PlannerKit/Sources/PlannerKit/Planner/PlannerOverlays.swift
//
// Map geometry for the Planner, as geographic polylines drawn from the observer pin:
// - direction lines to the Sun and Moon now, and to where they rise and set today;
// - the day's path, projected so the horizon sits on a circle of `radius` around the pin
//   and the zenith at the pin (distance = radius × (90° − elevation) / 90°). Stretches
//   below the horizon are drawn on the circle itself and flagged so the map can thin them.
// Points are geodesic (Vincenty direct) with longitudes unwrapped around the pin, so lines
// stay continuous across the antimeridian; `mercatorSafe` clamps latitudes for MapKit.

import AstroCore
import Foundation
import GeoCore

public enum OverlayBody: String, Sendable, Hashable, CaseIterable {
    case sun, moon, galacticCenter
}

public enum OverlayRole: String, Sendable, Hashable {
    /// Direction to the body at the selected instant.
    case now
    case rise
    case set
    /// Part of the daily path above the horizon.
    case pathUp
    /// Part of the daily path below the horizon.
    case pathDown
}

/// Which bodies the map draws.
public struct PlannerLayers: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let sun = PlannerLayers(rawValue: 1)
    public static let moon = PlannerLayers(rawValue: 2)
    public static let milkyWay = PlannerLayers(rawValue: 4)
    public static let all: PlannerLayers = [.sun, .moon, .milkyWay]
}

public struct OverlayLine: Sendable, Hashable, Identifiable {
    public let body: OverlayBody
    public let role: OverlayRole
    /// True when the body is above the horizon along this line (thick) or not (thin/dashed).
    public let isAboveHorizon: Bool
    public let points: [GeoPoint]
    public let index: Int
    public var id: String { "\(body.rawValue).\(role.rawValue).\(index)" }
}

/// Where to draw the body itself: on its path at the instant.
public struct OverlayMarker: Sendable, Hashable, Identifiable {
    public let body: OverlayBody
    public let point: GeoPoint
    public let isAboveHorizon: Bool
    public var id: String { body.rawValue }
}

public struct PlannerOverlays: Sendable, Hashable {
    public let lines: [OverlayLine]
    public let markers: [OverlayMarker]

    /// Mercator maps cannot show the poles; MapKit's limit is about ±85.05°.
    public static let mercatorLimit = 85.0511

    public static func build(_ snapshot: PlannerSnapshot, radius: Double, layers: PlannerLayers = .all) -> PlannerOverlays {
        let pin = snapshot.location.geoPoint
        var lines: [OverlayLine] = []
        var markers: [OverlayMarker] = []
        let day = snapshot.day

        func ray(_ azimuth: Double, length: Double) -> [GeoPoint] {
            [pin, Geodesy.destination(from: pin, bearing: azimuth, distance: length).unwrapped(near: pin.longitude)]
        }

        var bodies: [(OverlayBody, BodyNow, [SkyEvent], [SkyEvent], SkyPath)] = []
        if layers.contains(.sun) { bodies.append((.sun, snapshot.sun, day.sunRises, day.sunSets, day.sunPath)) }
        if layers.contains(.moon) { bodies.append((.moon, snapshot.moon.position, day.moonRises, day.moonSets, day.moonPath)) }
        for (body, now, rises, sets, path) in bodies {
            for (i, segment) in pathSegments(path.samples.map { ($0.azimuth, $0.altitude) }, pin: pin, radius: radius).enumerated() {
                lines.append(OverlayLine(body: body, role: segment.up ? .pathUp : .pathDown, isAboveHorizon: segment.up,
                                         points: segment.points, index: i))
            }
            for (i, e) in rises.enumerated() {
                lines.append(OverlayLine(body: body, role: .rise, isAboveHorizon: true, points: ray(e.azimuth, length: radius), index: i))
            }
            for (i, e) in sets.enumerated() {
                lines.append(OverlayLine(body: body, role: .set, isAboveHorizon: true, points: ray(e.azimuth, length: radius), index: i))
            }
            lines.append(OverlayLine(body: body, role: .now, isAboveHorizon: now.isUp,
                                     points: ray(now.azimuth, length: radius * 1.15), index: 0))
            markers.append(OverlayMarker(body: body, point: project(now.azimuth, now.altitude, pin: pin, radius: radius),
                                         isAboveHorizon: now.isUp))
        }
        if layers.contains(.milkyWay) {
            // The galactic plane is a great circle: draw only the arc above the horizon.
            let plane = snapshot.galacticPlane + snapshot.galacticPlane.prefix(1)
            let segments = pathSegments(plane.map { ($0.azimuth, $0.altitude) }, pin: pin, radius: radius).filter(\.up)
            for (i, segment) in segments.enumerated() {
                lines.append(OverlayLine(body: .galacticCenter, role: .pathUp, isAboveHorizon: true, points: segment.points, index: i))
            }
            let gc = snapshot.galacticCenter
            lines.append(OverlayLine(body: .galacticCenter, role: .now, isAboveHorizon: gc.isUp,
                                     points: ray(gc.azimuth, length: radius * 1.15), index: 0))
            markers.append(OverlayMarker(body: .galacticCenter, point: project(gc.azimuth, gc.altitude, pin: pin, radius: radius),
                                         isAboveHorizon: gc.isUp))
        }
        return PlannerOverlays(lines: lines, markers: markers)
    }

    /// The map point for a body at (azimuth, elevation): on the horizon circle when it is
    /// down, moving in toward the pin as it climbs.
    public static func project(_ azimuth: Double, _ altitude: Double, pin: GeoPoint, radius: Double) -> GeoPoint {
        let distance = radius * (90 - max(0, min(90, altitude))) / 90
        return Geodesy.destination(from: pin, bearing: azimuth, distance: distance).unwrapped(near: pin.longitude)
    }

    struct Segment {
        var up: Bool
        var points: [GeoPoint]
    }

    /// Splits a sampled path into runs above and below the horizon. Each run starts with the
    /// interpolated horizon crossing so consecutive runs join without a gap.
    static func pathSegments(_ samples: [(azimuth: Double, altitude: Double)], pin: GeoPoint, radius: Double) -> [Segment] {
        guard var previous = samples.first else { return [] }
        let first = project(previous.azimuth, previous.altitude, pin: pin, radius: radius)
        var segments = [Segment(up: previous.altitude > 0, points: [first])]
        for sample in samples.dropFirst() {
            let up = sample.altitude > 0
            if up != segments[segments.count - 1].up {
                // Linear interpolation of the crossing azimuth (shortest way round).
                let f = previous.altitude / (previous.altitude - sample.altitude)
                var dAz = sample.azimuth - previous.azimuth
                if dAz > 180 { dAz -= 360 }
                if dAz < -180 { dAz += 360 }
                let crossing = project(previous.azimuth + f * dAz, 0, pin: pin, radius: radius)
                segments[segments.count - 1].points.append(crossing)
                segments.append(Segment(up: up, points: [crossing]))
            }
            segments[segments.count - 1].points.append(project(sample.azimuth, sample.altitude, pin: pin, radius: radius))
            previous = sample
        }
        return segments.filter { $0.points.count >= 2 }
    }

    /// The point with its latitude clamped to what a Web Mercator map can show.
    public static func mercatorSafe(_ p: GeoPoint) -> GeoPoint {
        GeoPoint(latitude: max(-mercatorLimit, min(mercatorLimit, p.latitude)), longitude: p.longitude)
    }

    /// Line length for a map showing `spanMeters` across its narrower side: long enough to
    /// read, short enough to keep the path on screen.
    public static func radius(forVisibleSpan spanMeters: Double) -> Double {
        max(50, min(2_000_000, spanMeters * 0.38))
    }
}
