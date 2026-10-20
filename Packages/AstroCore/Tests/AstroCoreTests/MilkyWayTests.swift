// Packages/AstroCore/Tests/AstroCoreTests/MilkyWayTests.swift
//
// Phase 4: galactic frame, galactic-centre position, arc tilt and visibility windows.
// Golden windows and positions: Golden/milkyway.json, generated independently with
// Skyfield + JPL DE421 by Tools/golden/generate_milkyway.py.

import Foundation
import Testing
@testable import AstroCore

struct MilkyWayTests {
    struct File: Decodable {
        struct Night: Decodable {
            let site: String
            let lat: Double, lon: Double, height: Double
            let zone: String
            let night: String
            let visible: [[String]]
        }
        struct Sample: Decodable {
            let site: String
            let lat: Double, lon: Double, height: Double
            let time: String
            let azimuth: Double, altitude: Double, tilt: Double
        }
        let nights: [Night]
        let samples: [Sample]
    }

    static let file: File = {
        do {
            return try JSONDecoder().decode(File.self, from: Data(contentsOf: Golden.url("milkyway", "json")))
        } catch {
            fatalError("milkyway.json: \(error)")
        }
    }()

    // Golden: the galactic frame origin in J2000, 17h45m37.20s −28°56′10.2″ (ESA Hipparcos
    // Catalogue vol. 1 §1.5.3 transformation; matches the brief's 17h45.6m −28°56′).
    @Test func galacticCenterCoordinates() {
        let gc = FixedSky.galacticCenter
        let raSeconds: Double = 17 * 3600 + 45 * 60 + 37.20
        let dec: Double = -(28 + 56 / 60.0 + 10.2 / 3600)
        #expect(abs(gc.ra * 3600 - raSeconds) < 0.1)
        #expect(abs(gc.dec - dec) < 2.0 / 3600)
    }

    // Golden: north galactic pole at α = 192.85948°, δ = +27.12825° (Hipparcos, J2000).
    @Test func northGalacticPole() {
        let pole = Galactic.toEquatorial(l: 0, b: 90)
        #expect(abs(pole.ra * 15 - 192.85948) < 1e-6)
        #expect(abs(pole.dec - 27.12825) < 1e-6)
    }

    @Test func galacticRoundTrip() {
        for l in stride(from: 0.0, to: 360.0, by: 37.0) {
            for b in [-80.0, -30, 0, 45, 85] {
                let eq = Galactic.toEquatorial(l: l, b: b)
                let back = Galactic.fromEquatorial(eq)
                #expect(abs(longitudeOffset(back.l - l)) < 1e-9 && abs(back.b - b) < 1e-9)
            }
        }
    }

    /// Galactic-centre azimuth/elevation against Skyfield (above 5° so refraction models agree).
    @Test func centerPositionMatchesSkyfield() {
        var azStats = Stats(), altStats = Stats(), tiltStats = Stats()
        for s in Self.file.samples {
            let observer = Observer(latitude: s.lat, longitude: s.lon, height: s.height)
            let t = Golden.time(s.time)
            let h = MilkyWay.center(at: t, observer: observer)
            let tilt = MilkyWay.arcTilt(at: t, observer: observer)
            if s.altitude > 5 {
                azStats.add(abs(longitudeOffset(h.azimuth - s.azimuth)))
                altStats.add(abs(h.altitude - s.altitude))
            } else {
                // Near and below the horizon the two refraction models diverge (Skyfield
                // stops refracting below −1°); only check the geometry is in the same place.
                #expect(abs(h.altitude - s.altitude) < 1)
                #expect(abs(longitudeOffset(h.azimuth - s.azimuth)) < 0.1)
            }
            tiltStats.add(abs(tilt - s.tilt))
        }
        print("ACCURACY | Galactic centre azimuth vs Skyfield (alt > 5): n=\(azStats.n) max=\(String(format: "%.4f", azStats.max)) deg")
        print("ACCURACY | Galactic centre elevation vs Skyfield (alt > 5): n=\(altStats.n) max=\(String(format: "%.4f", altStats.max)) deg")
        print("ACCURACY | Milky Way arc tilt vs Skyfield: n=\(tiltStats.n) max=\(String(format: "%.3f", tiltStats.max)) deg")
        #expect(azStats.max < 0.1 && altStats.max < 0.1)
        #expect(tiltStats.max < 0.5)
    }

    /// Core visibility windows on 2026 new-moon nights at five sites (34°N, 29°N, 52°N, 23°S,
    /// 34°S) agree with Skyfield within ±2 min. Includes nights with no window (Warsaw in
    /// June/July has no astronomical night; December everywhere is out of season).
    @Test func visibilityWindowsMatchSkyfield() {
        var stats = Stats()
        var worst = ""
        for night in Self.file.nights {
            let observer = Observer(latitude: night.lat, longitude: night.lon, height: night.height)
            let (start, end) = Self.noonToNoon(night.night, zone: night.zone)
            let windows = MilkyWay.windows(observer: observer, from: start, to: end)
            #expect(windows.visible.count == night.visible.count, "\(night.site) \(night.night)")
            for (span, golden) in zip(windows.visible, night.visible) {
                for (mine, ref) in [(span.start, golden[0]), (span.end, golden[1])] {
                    let error = abs(mine.ut - Golden.time(ref).ut) * 1440
                    if error > stats.max { worst = "\(night.site) \(night.night) \(ref)" }
                    stats.add(error)
                }
            }
        }
        print("ACCURACY | Milky Way core window edges vs Skyfield: n=\(stats.n) mean=\(String(format: "%.2f", stats.mean)) min max=\(String(format: "%.2f", stats.max)) min (worst: \(worst))")
        #expect(stats.max < 2)
    }

    /// Published season: in the northern mid-latitudes the core is visible roughly February
    /// to October and not in December; in the south the longest windows are in June/July.
    @Test func seasonShape() {
        let byNight = Dictionary(grouping: Self.file.nights, by: \.site)
        for (site, nights) in byNight {
            let durations = nights.map { night -> Double in
                let observer = Observer(latitude: night.lat, longitude: night.lon, height: night.height)
                let (start, end) = Self.noonToNoon(night.night, zone: night.zone)
                return MilkyWay.windows(observer: observer, from: start, to: end).visibleDays * 24
            }
            #expect(durations.last == 0, "\(site): December should have no core window")
            if nights[0].lat < 0 {
                let best = durations.indices.max { durations[$0] < durations[$1] }!
                #expect(["2026-06-15", "2026-07-14"].contains(nights[best].night), "\(site)")
            }
        }
    }

    @Test func moonFreeIsSubsetOfVisible() {
        // Full moon 2026-08-28: the Moon washes out most of the window at La Palma.
        let observer = Observer(latitude: 28.7606, longitude: -17.8816, height: 2400)
        let (start, end) = Self.noonToNoon("2026-08-27", zone: "Atlantic/Canary")
        let w = MilkyWay.windows(observer: observer, from: start, to: end)
        #expect(w.visibleDays > 0)
        #expect(w.moonFreeDays < w.visibleDays * 0.5)
        for span in w.moonFree {
            #expect(w.visible.contains { $0.start.ut <= span.start.ut + 1e-9 && $0.end.ut >= span.end.ut - 1e-9 })
        }
        // New moon night: no interference.
        let (s2, e2) = Self.noonToNoon("2026-08-12", zone: "Atlantic/Canary")
        let n = MilkyWay.windows(observer: observer, from: s2, to: e2)
        #expect(abs(n.moonFreeDays - n.visibleDays) < 1e-6)
    }

    @Test func orientationClasses() {
        #expect(ArcOrientation.of(tilt: 10) == .horizontal)
        #expect(ArcOrientation.of(tilt: 45) == .diagonal)
        #expect(ArcOrientation.of(tilt: 80) == .vertical)
    }

    @Test func planeSamplesStartAtCenter() {
        let observer = Observer(latitude: 28.76, longitude: -17.88)
        let t = AstroTime(year: 2026, month: 6, day: 16, hour: 2)
        let plane = MilkyWay.plane(at: t, observer: observer, step: 10)
        #expect(plane.count == 36)
        let c = MilkyWay.center(at: t, observer: observer)
        #expect(abs(plane[0].horizontal.azimuth - c.azimuth) < 1e-9 && abs(plane[0].horizontal.altitude - c.altitude) < 1e-9)
        // Half the great circle is above the horizon (± refraction and sampling).
        let up = plane.filter { $0.horizontal.altitude > 0 }.count
        #expect((17...19).contains(up))
    }

    @Test func polarObserver() {
        // At the north pole the core never rises (declination −29°).
        let observer = Observer(latitude: 90, longitude: 0)
        let w = MilkyWay.windows(observer: observer, from: AstroTime(year: 2026, month: 12, day: 1),
                                 to: AstroTime(year: 2026, month: 12, day: 2))
        #expect(w.centerUp.isEmpty && w.visible.isEmpty)
        #expect(!w.dark.isEmpty)
        // At the south pole in June the core is up and it is dark all day.
        let south = Observer(latitude: -90, longitude: 0)
        let s = MilkyWay.windows(observer: south, from: AstroTime(year: 2026, month: 6, day: 15),
                                 to: AstroTime(year: 2026, month: 6, day: 16))
        #expect(abs(s.visibleDays - 1) < 1e-9)
    }

    @Test func intervalsClipToRange() {
        let start = AstroTime(ut: 0), end = AstroTime(ut: 1)
        let spans = MilkyWay.intervals(from: start, to: end, step: 0.01) { $0.ut < 0.25 || $0.ut > 0.75 }
        #expect(spans.count == 2)
        #expect(spans[0].start.ut == 0 && abs(spans[0].end.ut - 0.25) < 20.0 / 86_400)
        #expect(abs(spans[1].start.ut - 0.75) < 20.0 / 86_400 && spans[1].end.ut == 1)
    }

    // MARK: Helpers

    struct Stats {
        var n = 0, sum = 0.0, max = 0.0
        mutating func add(_ v: Double) { n += 1; sum += v; max = Swift.max(max, v) }
        var mean: Double { n == 0 ? 0 : sum / Double(n) }
    }

    /// Local noon on `date` to local noon the next day, in `zone`.
    static func noonToNoon(_ date: String, zone: String) -> (AstroTime, AstroTime) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        let p = date.split(separator: "-").compactMap { Int($0) }
        let noon = cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!
        return (AstroTime(noon), AstroTime(noon.addingTimeInterval(86_400)))
    }
}
