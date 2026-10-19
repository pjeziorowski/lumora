// Packages/PlannerKit/Sources/PlannerKit/Geodetics/Geodetics.swift
//
// The second ("target") pin and what the observer sees of it: distance and bearing on the
// WGS84 ellipsoid, the height difference, and the apparent elevation angle of the target's
// ground and of the top of an object standing there (a ridge, a building, a lighthouse),
// corrected for Earth curvature and refraction. The obstacle report adds when the Sun and
// Moon line up with the target today and whether they clear the object's top, and how tall
// the object would have to be for the body to sit exactly on it.

import AstroCore
import Foundation
import GeoCore

public struct TargetPin: Sendable, Hashable, Codable {
    public var point: GeoPoint
    /// Ground elevation (m above sea level), or nil while unknown.
    public var groundElevation: Double?
    /// Height of the object standing at the pin, above its ground (m).
    public var objectHeight: Double

    public init(point: GeoPoint, groundElevation: Double? = nil, objectHeight: Double = 0) {
        self.point = point
        self.groundElevation = groundElevation
        self.objectHeight = objectHeight
    }
}

public struct GeodeticsReport: Sendable, Hashable {
    public let distance: Double
    public let bearing: Double
    /// Bearing from the target back to the observer.
    public let backBearing: Double
    /// Observer eye level and target ground, m above sea level (target nil when unknown).
    public let observerHeight: Double
    public let targetGround: Double?
    /// Target ground minus observer eye level (m), when known.
    public let heightDifference: Double?
    /// The object at the target and its top above sea level (unknown ground = sea level).
    public let objectHeight: Double
    public let topHeight: Double
    /// Apparent elevation of the target's ground and of the object's top (degrees). An
    /// unknown ground elevation counts as sea level.
    public let groundAngle: Double
    public let topAngle: Double
    /// Drop from curvature and refraction at the target's distance (m).
    public let curvatureDrop: Double

    public static func compute(observer: PillLocation, eyeHeight: Double, target: TargetPin,
                               k: Double = Sightline.standardRefraction) -> GeodeticsReport {
        let line = Geodesy.inverse(observer.geoPoint, target.point)
        let eye = observer.elevation + eyeHeight
        let ground = target.groundElevation ?? 0
        return GeodeticsReport(
            distance: line.distance,
            bearing: line.initialBearing,
            backBearing: (line.finalBearing + 180).truncatingRemainder(dividingBy: 360),
            observerHeight: eye,
            targetGround: target.groundElevation,
            heightDifference: target.groundElevation.map { $0 - eye },
            objectHeight: target.objectHeight,
            topHeight: ground + target.objectHeight,
            groundAngle: Sightline.apparentElevation(observerHeight: eye, targetHeight: ground, distance: line.distance, k: k),
            topAngle: Sightline.apparentElevation(observerHeight: eye, targetHeight: ground + target.objectHeight,
                                                  distance: line.distance, k: k),
            curvatureDrop: Sightline.drop(distance: line.distance, k: k)
        )
    }
}

/// The Sun or Moon crossing the target's bearing today.
public struct BodyAlignment: Sendable, Hashable {
    public let body: FindBody
    public let time: Date
    public let elevation: Double
    /// Body elevation minus the angle to the object's top: positive when it shows above.
    public let clearance: Double
    /// Object height (above the target's ground) that would put the body's centre exactly
    /// on its top; negative when the body is below the target's ground line.
    public let heightForAlignment: Double
}

public struct ObstacleReport: Sendable, Hashable {
    public let geodetics: GeodeticsReport
    public let alignments: [BodyAlignment]

    /// Alignments of the Sun and Moon with the target's bearing during `day`.
    public static func compute(observer: PillLocation, eyeHeight: Double, target: TargetPin, day: LocalDay,
                               k: Double = Sightline.standardRefraction) -> ObstacleReport {
        let g = GeodeticsReport.compute(observer: observer, eyeHeight: eyeHeight, target: target, k: k)
        var alignments: [BodyAlignment] = []
        for body in [FindBody.sun, .moon] {
            for m in BodyFinder.alignments(body, azimuth: g.bearing, observer: observer.observer, from: day.start, to: day.end) {
                let needed = Sightline.height(forAngle: m.elevation, observerHeight: g.observerHeight, distance: g.distance, k: k)
                    - (target.groundElevation ?? 0)
                alignments.append(BodyAlignment(body: body, time: m.time, elevation: m.elevation,
                                                clearance: m.elevation - g.topAngle, heightForAlignment: needed))
            }
        }
        return ObstacleReport(geodetics: g, alignments: alignments.sorted { $0.time < $1.time })
    }
}
