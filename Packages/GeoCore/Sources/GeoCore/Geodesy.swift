// Packages/GeoCore/Sources/GeoCore/Geodesy.swift
//
// WGS84 geodesy: Vincenty's inverse (distance and bearings between two points) and direct
// (point at a distance along a bearing) solutions, plus longitude unwrapping so lines drawn
// near the antimeridian stay continuous.
//
// Reference: T. Vincenty, "Direct and inverse solutions of geodesics on the ellipsoid with
// application of nested equations", Survey Review XXIII (176), April 1975, pp. 88–93.
// Written from the published equations; no code was copied.

import Foundation

/// A geographic position in degrees. Longitude may lie outside [-180, 180] when unwrapped.
public struct GeoPoint: Sendable, Hashable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Longitude folded into [-180, 180).
    public var normalized: GeoPoint {
        GeoPoint(latitude: latitude, longitude: Geodesy.normalizeLongitude(longitude))
    }

    /// The same point with its longitude shifted by whole turns to lie within 180° of
    /// `reference`'s longitude, so a polyline through both does not jump across the map.
    public func unwrapped(near reference: Double) -> GeoPoint {
        var lon = longitude
        while lon - reference > 180 { lon -= 360 }
        while lon - reference < -180 { lon += 360 }
        return GeoPoint(latitude: latitude, longitude: lon)
    }
}

public struct GeodesicLine: Sendable, Hashable {
    /// Ellipsoidal distance in metres.
    public let distance: Double
    /// Forward azimuth at the start point, degrees east of true north [0, 360).
    public let initialBearing: Double
    /// Forward azimuth on arrival at the end point [0, 360).
    public let finalBearing: Double
}

public enum Geodesy {
    static let a = GeoCore.wgs84SemiMajorAxis
    static let f = GeoCore.wgs84Flattening
    static let b = a * (1 - f)
    static let rad = Double.pi / 180

    /// Mean Earth radius (IUGG R1 = (2a + b) / 3) in metres, for spherical shortcuts.
    public static let meanRadius = (2 * GeoCore.wgs84SemiMajorAxis + GeoCore.wgs84SemiMajorAxis * (1 - GeoCore.wgs84Flattening)) / 3

    public static func normalizeLongitude(_ lon: Double) -> Double {
        var x = (lon + 180).truncatingRemainder(dividingBy: 360)
        if x < 0 { x += 360 }
        return x - 180
    }

    static func normalizeBearing(_ deg: Double) -> Double {
        var x = deg.truncatingRemainder(dividingBy: 360)
        if x < 0 { x += 360 }
        return x
    }

    // MARK: Inverse

    /// Distance and bearings from `p1` to `p2` (Vincenty inverse). Falls back to a spherical
    /// great circle for nearly antipodal points, where the iteration does not converge.
    public static func inverse(_ p1: GeoPoint, _ p2: GeoPoint) -> GeodesicLine {
        let phi1 = p1.latitude * rad, phi2 = p2.latitude * rad
        let L = (normalizeLongitude(p2.longitude - p1.longitude)) * rad
        let U1 = atan((1 - f) * tan(phi1)), U2 = atan((1 - f) * tan(phi2))
        let sinU1 = sin(U1), cosU1 = cos(U1), sinU2 = sin(U2), cosU2 = cos(U2)

        var lambda = L
        var sinSigma = 0.0, cosSigma = 1.0, sigma = 0.0, cos2Alpha = 1.0, cos2SigmaM = 0.0
        var sinLambda = 0.0, cosLambda = 1.0
        var converged = false
        for _ in 0..<200 {
            sinLambda = sin(lambda)
            cosLambda = cos(lambda)
            let t1 = cosU2 * sinLambda
            let t2 = cosU1 * sinU2 - sinU1 * cosU2 * cosLambda
            sinSigma = (t1 * t1 + t2 * t2).squareRoot()
            if sinSigma == 0 {
                // Coincident points.
                return GeodesicLine(distance: 0, initialBearing: 0, finalBearing: 0)
            }
            cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda
            sigma = atan2(sinSigma, cosSigma)
            let sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma
            cos2Alpha = 1 - sinAlpha * sinAlpha
            // Equatorial line: cos²α = 0.
            cos2SigmaM = cos2Alpha != 0 ? cosSigma - 2 * sinU1 * sinU2 / cos2Alpha : 0
            let C = f / 16 * cos2Alpha * (4 + f * (4 - 3 * cos2Alpha))
            let previous = lambda
            lambda = L + (1 - C) * f * sinAlpha
                * (sigma + C * sinSigma * (cos2SigmaM + C * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)))
            if abs(lambda - previous) < 1e-12 {
                converged = true
                break
            }
            if abs(lambda) > .pi { break }
        }
        guard converged else { return sphericalInverse(p1, p2) }

        let u2 = cos2Alpha * (a * a - b * b) / (b * b)
        let A = 1 + u2 / 16_384 * (4096 + u2 * (-768 + u2 * (320 - 175 * u2)))
        let B = u2 / 1024 * (256 + u2 * (-128 + u2 * (74 - 47 * u2)))
        let deltaSigma = B * sinSigma * (cos2SigmaM + B / 4 * (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)
            - B / 6 * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma) * (-3 + 4 * cos2SigmaM * cos2SigmaM)))
        let s = b * A * (sigma - deltaSigma)
        let alpha1 = atan2(cosU2 * sinLambda, cosU1 * sinU2 - sinU1 * cosU2 * cosLambda)
        let alpha2 = atan2(cosU1 * sinLambda, -sinU1 * cosU2 + cosU1 * sinU2 * cosLambda)
        return GeodesicLine(distance: s,
                            initialBearing: normalizeBearing(alpha1 / rad),
                            finalBearing: normalizeBearing(alpha2 / rad))
    }

    static func sphericalInverse(_ p1: GeoPoint, _ p2: GeoPoint) -> GeodesicLine {
        let phi1 = p1.latitude * rad, phi2 = p2.latitude * rad
        let dLon = normalizeLongitude(p2.longitude - p1.longitude) * rad
        let h = sin((phi2 - phi1) / 2) * sin((phi2 - phi1) / 2) + cos(phi1) * cos(phi2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(h.squareRoot(), (1 - h).squareRoot())
        let y = sin(dLon) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLon)
        let y2 = sin(-dLon) * cos(phi1)
        let x2 = cos(phi2) * sin(phi1) - sin(phi2) * cos(phi1) * cos(-dLon)
        return GeodesicLine(distance: meanRadius * c,
                            initialBearing: normalizeBearing(atan2(y, x) / rad),
                            finalBearing: normalizeBearing(atan2(y2, x2) / rad + 180))
    }

    // MARK: Direct

    /// The point `distance` metres from `start` along the geodesic leaving at `bearing`
    /// degrees east of north (Vincenty direct). The returned longitude is continuous with
    /// the start's (it may exceed ±180 near the antimeridian); use `.normalized` to fold it.
    public static func destination(from start: GeoPoint, bearing: Double, distance: Double) -> GeoPoint {
        destinationWithBearing(from: start, bearing: bearing, distance: distance).point
    }

    /// Destination plus the forward azimuth on arrival.
    public static func destinationWithBearing(from start: GeoPoint, bearing: Double, distance: Double)
        -> (point: GeoPoint, finalBearing: Double) {
        guard distance != 0 else { return (start, normalizeBearing(bearing)) }
        let alpha1 = bearing * rad
        let sinAlpha1 = sin(alpha1), cosAlpha1 = cos(alpha1)
        // Keep the reduced latitude finite at the poles.
        let phi1 = max(-89.999_999_9, min(89.999_999_9, start.latitude)) * rad
        let tanU1 = (1 - f) * tan(phi1)
        let cosU1 = 1 / (1 + tanU1 * tanU1).squareRoot(), sinU1 = tanU1 * cosU1
        let sigma1 = atan2(tanU1, cosAlpha1)
        let sinAlpha = cosU1 * sinAlpha1
        let cos2Alpha = 1 - sinAlpha * sinAlpha
        let u2 = cos2Alpha * (a * a - b * b) / (b * b)
        let A = 1 + u2 / 16_384 * (4096 + u2 * (-768 + u2 * (320 - 175 * u2)))
        let B = u2 / 1024 * (256 + u2 * (-128 + u2 * (74 - 47 * u2)))

        var sigma = distance / (b * A)
        var cos2SigmaM = 0.0, sinSigma = 0.0, cosSigma = 1.0
        for _ in 0..<100 {
            cos2SigmaM = cos(2 * sigma1 + sigma)
            sinSigma = sin(sigma)
            cosSigma = cos(sigma)
            let deltaSigma = B * sinSigma * (cos2SigmaM + B / 4 * (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)
                - B / 6 * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma) * (-3 + 4 * cos2SigmaM * cos2SigmaM)))
            let previous = sigma
            sigma = distance / (b * A) + deltaSigma
            if abs(sigma - previous) < 1e-12 { break }
        }
        cos2SigmaM = cos(2 * sigma1 + sigma)
        sinSigma = sin(sigma)
        cosSigma = cos(sigma)

        let tmp = sinU1 * sinSigma - cosU1 * cosSigma * cosAlpha1
        let phi2 = atan2(sinU1 * cosSigma + cosU1 * sinSigma * cosAlpha1,
                         (1 - f) * (sinAlpha * sinAlpha + tmp * tmp).squareRoot())
        let lambda = atan2(sinSigma * sinAlpha1, cosU1 * cosSigma - sinU1 * sinSigma * cosAlpha1)
        let C = f / 16 * cos2Alpha * (4 + f * (4 - 3 * cos2Alpha))
        let L = lambda - (1 - C) * f * sinAlpha
            * (sigma + C * sinSigma * (cos2SigmaM + C * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)))
        let alpha2 = atan2(sinAlpha, -tmp)
        let point = GeoPoint(latitude: phi2 / rad, longitude: start.longitude + L / rad)
        return (point, normalizeBearing(alpha2 / rad))
    }
}
