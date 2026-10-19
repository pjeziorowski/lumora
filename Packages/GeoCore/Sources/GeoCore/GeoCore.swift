// Packages/GeoCore/Sources/GeoCore/GeoCore.swift
//
// Geodesy (WGS84 distance/bearing, apparent elevation with curvature and refraction),
// elevation client with cache, and coordinate → time zone lookup.
// Phase 0 skeleton: geodesy lands in Phase 6, time zone lookup in Phase 3.

import Foundation

public enum GeoCore {
    /// WGS84 semi-major axis in metres.
    public static let wgs84SemiMajorAxis = 6_378_137.0
    /// WGS84 flattening.
    public static let wgs84Flattening = 1.0 / 298.257223563
}
