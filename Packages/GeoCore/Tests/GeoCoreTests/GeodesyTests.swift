// Packages/GeoCore/Tests/GeoCoreTests/GeodesyTests.swift

import Foundation
import Testing
@testable import GeoCore

struct GeodesyTests {
    static func dms(_ d: Double, _ m: Double, _ s: Double) -> Double {
        (abs(d) + m / 60 + s / 3600) * (d < 0 ? -1 : 1)
    }

    // Golden: Geoscience Australia, "Vincenty's formulae" worked example, Flinders Peak to
    // Buninyong on GRS80 (which differs from WGS84 by 0.1 mm in b; negligible here).
    // https://www.icsm.gov.au/education/fundamentals-mapping/datums/geodetic-calculations (GDA2020 technical manual §7)
    static let flinders = GeoPoint(latitude: dms(-37, 57, 3.72030), longitude: dms(144, 25, 29.52440))
    static let buninyong = GeoPoint(latitude: dms(-37, 39, 10.15610), longitude: dms(143, 55, 35.38390))

    @Test func inverseFlindersPeakToBuninyong() {
        let line = Geodesy.inverse(Self.flinders, Self.buninyong)
        #expect(abs(line.distance - 54_972.271) < 0.002)
        #expect(abs(line.initialBearing - Self.dms(306, 52, 5.37)) < 0.5 / 3600)
        // Reverse azimuth 127°10'25.07" = final bearing + 180°.
        #expect(abs((line.finalBearing + 180).truncatingRemainder(dividingBy: 360) - Self.dms(127, 10, 25.07)) < 0.5 / 3600)
    }

    @Test func directFlindersPeakToBuninyong() {
        let p = Geodesy.destination(from: Self.flinders, bearing: Self.dms(306, 52, 5.37), distance: 54_972.271)
        // 1e-7° ≈ 1 cm.
        #expect(abs(p.latitude - Self.buninyong.latitude) < 1e-7)
        #expect(abs(p.longitude - Self.buninyong.longitude) < 1e-7)
    }

    // Golden: WGS84 equatorial quadrant = a·π/2 (exact along the equator) and meridian
    // quadrant 10 001 965.729 m (NIMA TR8350.2 derived; also GeographicLib GeodSolve).
    @Test func quadrants() {
        let equator = Geodesy.inverse(GeoPoint(latitude: 0, longitude: 0), GeoPoint(latitude: 0, longitude: 90))
        #expect(abs(equator.distance - 6_378_137 * Double.pi / 2) < 0.001)
        #expect(abs(equator.initialBearing - 90) < 1e-9)
        let meridian = Geodesy.inverse(GeoPoint(latitude: 0, longitude: 0), GeoPoint(latitude: 90, longitude: 0))
        #expect(abs(meridian.distance - 10_001_965.729) < 0.01)
    }

    /// Direct then inverse returns the input distance and bearing everywhere, including
    /// near the poles and across the antimeridian.
    @Test func roundTrip() {
        for lat in stride(from: -89.0, through: 89.0, by: 22.25) {
            for lon in [-179.99, -90.0, 0.0, 120.0, 179.99] {
                for bearing in stride(from: 0.0, to: 360.0, by: 45.0) {
                    let start = GeoPoint(latitude: lat, longitude: lon)
                    let end = Geodesy.destination(from: start, bearing: bearing, distance: 25_000)
                    #expect(end.latitude.isFinite && end.longitude.isFinite)
                    let back = Geodesy.inverse(start, end)
                    #expect(abs(back.distance - 25_000) < 0.01, "lat \(lat) lon \(lon) brg \(bearing)")
                    var dBearing = abs(back.initialBearing - bearing)
                    dBearing = min(dBearing, 360 - dBearing)
                    #expect(dBearing < 1e-6, "lat \(lat) lon \(lon) brg \(bearing)")
                }
            }
        }
    }

    @Test func destinationIsContinuousAcrossAntimeridian() {
        let start = GeoPoint(latitude: -16.8, longitude: 179.95)
        let east = Geodesy.destination(from: start, bearing: 90, distance: 20_000)
        #expect(east.longitude > 180 && east.longitude < 180.2)
        #expect(east.normalized.longitude < -179.8)
        let west = Geodesy.destination(from: GeoPoint(latitude: -16.8, longitude: -179.95), bearing: 270, distance: 20_000)
        #expect(west.longitude < -180)
    }

    @Test func fromThePole() {
        let p = Geodesy.destination(from: GeoPoint(latitude: 90, longitude: 0), bearing: 180, distance: 111_694.6)
        #expect(p.latitude.isFinite && p.longitude.isFinite)
        #expect(abs(p.latitude - 89) < 0.001)
    }

    @Test func nearlyAntipodalFallsBack() {
        let line = Geodesy.inverse(GeoPoint(latitude: 0, longitude: 0), GeoPoint(latitude: 0.5, longitude: 179.7))
        #expect(line.distance.isFinite && line.distance > 19_900_000 && line.distance < 20_100_000)
    }

    @Test func unwrap() {
        #expect(GeoPoint(latitude: 0, longitude: -179).unwrapped(near: 179).longitude == 181)
        #expect(GeoPoint(latitude: 0, longitude: 179).unwrapped(near: -179).longitude == -181)
        #expect(GeoPoint(latitude: 0, longitude: 10).unwrapped(near: 20).longitude == 10)
        #expect(Geodesy.normalizeLongitude(540) == -180)
        #expect(Geodesy.normalizeLongitude(-190) == 170)
    }
}

struct PlaceLookupTests {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.lock(); value += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    @Test func cachesPerCell() async {
        let calls = Counter()
        let lookup = PlaceLookup { _, _ in
            calls.increment()
            return PlaceInfo(name: "Warsaw", timeZoneIdentifier: "Europe/Warsaw")
        }
        let first = await lookup.resolve(latitude: 52.2297, longitude: 21.0122)
        #expect(first.timeZoneIdentifier == "Europe/Warsaw" && !first.isFallbackZone && first.name == "Warsaw")
        // Same 0.01° cell.
        _ = await lookup.resolve(latitude: 52.2301, longitude: 21.0119)
        #expect(calls.count == 1)
        // Next cell over.
        _ = await lookup.resolve(latitude: 52.2497, longitude: 21.0122)
        #expect(calls.count == 2)
        #expect(await lookup.cached(latitude: 52.2297, longitude: 21.0122)?.timeZoneIdentifier == "Europe/Warsaw")
    }

    @Test func failedLookupFallsBackAndIsNotCached() async {
        let calls = Counter()
        let lookup = PlaceLookup { _, _ in
            calls.increment()
            return nil
        }
        let sea = await lookup.resolve(latitude: -30, longitude: -140)
        #expect(sea.isFallbackZone)
        #expect(TimeZone(identifier: sea.timeZoneIdentifier)?.secondsFromGMT() == -9 * 3600)
        _ = await lookup.resolve(latitude: -30, longitude: -140)
        #expect(calls.count == 2)
    }

    @Test func invalidZoneFallsBack() async {
        let lookup = PlaceLookup { _, _ in PlaceInfo(name: "Somewhere", timeZoneIdentifier: "Not/AZone") }
        let r = await lookup.resolve(latitude: 10, longitude: 30)
        #expect(r.isFallbackZone && r.name == "Somewhere")
        #expect(TimeZone(identifier: r.timeZoneIdentifier)?.secondsFromGMT() == 2 * 3600)
    }

    /// The cache key folds ±180° together, so the dateline cell is shared.
    @Test func datelineCellShared() async {
        let calls = Counter()
        let lookup = PlaceLookup { _, _ in
            calls.increment()
            return PlaceInfo(name: nil, timeZoneIdentifier: "Pacific/Fiji")
        }
        _ = await lookup.resolve(latitude: -16.8, longitude: 180)
        _ = await lookup.resolve(latitude: -16.8, longitude: -180)
        #expect(calls.count == 1)
    }

    @Test func nauticalZones() {
        #expect(PlaceLookup.nauticalZone(longitude: 0).secondsFromGMT() == 0)
        #expect(PlaceLookup.nauticalZone(longitude: 7.4).secondsFromGMT() == 0)
        #expect(PlaceLookup.nauticalZone(longitude: 7.6).secondsFromGMT() == 3600)
        #expect(PlaceLookup.nauticalZone(longitude: 179.9).secondsFromGMT() == 12 * 3600)
        #expect(PlaceLookup.nauticalZone(longitude: -179.9).secondsFromGMT() == -12 * 3600)
        #expect(PlaceLookup.nauticalZone(longitude: -74).secondsFromGMT() == -5 * 3600)
    }

    @Test func evictsOldestBeyondCapacity() async {
        let lookup = PlaceLookup(capacity: 2) { _, _ in PlaceInfo(name: nil, timeZoneIdentifier: "UTC") }
        _ = await lookup.resolve(latitude: 1, longitude: 1)
        _ = await lookup.resolve(latitude: 2, longitude: 2)
        _ = await lookup.resolve(latitude: 3, longitude: 3)
        #expect(await lookup.cached(latitude: 1, longitude: 1) == nil)
        #expect(await lookup.cached(latitude: 3, longitude: 3) != nil)
    }
}
