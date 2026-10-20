// Packages/GeoCore/Tests/GeoCoreTests/SightlineTests.swift
//
// Phase 6: geodetics against GeographicLib and lines of sight against surveying tables.
// Sources:
//  [GL] GeographicLib GeodSolve(1) man page, EXAMPLES: JFK (40°38'23"N 73°46'44"W) to
//       Singapore Changi (1°21'33"N 103°59'22"E): azi1 003°18'29.9", azi2 177°29'09.2",
//       s12 15 347 628 m; along that line at 2000 km: 58°34'45.1"N 71°49'36.7"W.
//       https://manpages.debian.org/jessie/geographiclib-tools/GeodSolve.1.en.html
//  [CR] Curvature and refraction correction used in levelling: (1 − κ)·d²/(2R), about
//       0.0675 m per km² with κ ≈ 0.14 (e.g. Schofield & Breach, "Engineering Surveying",
//       §3.4); curvature alone is d²/(2R) ≈ 0.0785 m per km².
//  [HZ] Wikipedia, "Horizon": geometric distance to the horizon ≈ 3.57·√h km (h in m).

import Foundation
import Testing
@testable import GeoCore

struct SightlineTests {
    static func dms(_ d: Double, _ m: Double, _ s: Double) -> Double { GeodesyTests.dms(d, m, s) }
    static let jfk = GeoPoint(latitude: dms(40, 38, 23), longitude: -dms(73, 46, 44))
    static let changi = GeoPoint(latitude: dms(1, 21, 33), longitude: dms(103, 59, 22))

    @Test func geographicLibJfkToChangi() {
        let line = Geodesy.inverse(Self.jfk, Self.changi)
        // Acceptance: 0.1% in distance, 0.1° in bearing; Vincenty agrees to the metre and 0.1".
        #expect(abs(line.distance - 15_347_628) < 1.5)
        #expect(abs(line.initialBearing - Self.dms(3, 18, 29.9)) < 0.1 / 3600)
        #expect(abs(line.finalBearing - Self.dms(177, 29, 9.2)) < 0.1 / 3600)
        let waypoint = Geodesy.destination(from: Self.jfk, bearing: line.initialBearing, distance: 2_000_000)
        #expect(abs(waypoint.latitude - Self.dms(58, 34, 45.1)) < 0.1 / 3600)
        #expect(abs(waypoint.longitude + Self.dms(71, 49, 36.7)) < 0.1 / 3600)
    }

    @Test func curvatureAndRefraction() {
        // Curvature only: 0.0785 m at 1 km, 78.5 m at 10 km... (d²/2R).
        #expect(abs(Sightline.drop(distance: 1000, k: 1) - 0.0785) < 0.0002)
        // With standard refraction: within 2% of the 0.0675 m/km² levelling constant.
        #expect(abs(Sightline.drop(distance: 1000) / 0.0675 - 1) < 0.02)
        #expect(abs(Sightline.drop(distance: 10_000) - 6.83) < 0.01)
        // Horizon from 2 m eye height: 3.57·√2 = 5.05 km geometric.
        #expect(abs(Sightline.horizonDistance(height: 2, k: 1) - 3570 * sqrt(2)) < 10)
    }

    @Test func apparentElevationRoundTrips() {
        // A 300 m ridge 12 km away from a 20 m viewpoint: (300 − 20 − 9.8)/12000.
        let angle = Sightline.apparentElevation(observerHeight: 20, targetHeight: 300, distance: 12_000)
        let expected = atan((280 - Sightline.drop(distance: 12_000)) / 12_000) * 180 / .pi
        #expect(abs(angle - expected) < 1e-12 && abs(angle - 1.29) < 0.01)
        let h = Sightline.height(forAngle: angle, observerHeight: 20, distance: 12_000)
        #expect(abs(h - 300) < 1e-9)
        // Sea-level target at the horizon distance sits at minus the dip angle.
        let d = Sightline.horizonDistance(height: 100)
        let dip = Sightline.apparentElevation(observerHeight: 100, targetHeight: 0, distance: d)
        #expect(dip < 0 && dip > -0.4)
        // Zero distance does not divide by zero.
        #expect(Sightline.apparentElevation(observerHeight: 0, targetHeight: 10, distance: 0) == 90)
    }

    @Test func elevationCachePerCell() async {
        let service = ElevationService { lat, _ in lat > 80 ? nil : 123.4 }
        #expect(await service.elevation(latitude: 46.0, longitude: 7.0) == 123.4)
        #expect(await service.elevation(latitude: 46.00002, longitude: 7.00002) == 123.4)
        #expect(await service.fetchCount == 1)
        // Failures are not cached.
        #expect(await service.elevation(latitude: 85, longitude: 0) == nil)
        #expect(await service.elevation(latitude: 85, longitude: 0) == nil)
        #expect(await service.fetchCount == 3)
        // Antimeridian: 180 and -180 share a cell.
        _ = await service.elevation(latitude: 10, longitude: 180)
        #expect(await service.cached(latitude: 10, longitude: -180) == 123.4)
    }
}
