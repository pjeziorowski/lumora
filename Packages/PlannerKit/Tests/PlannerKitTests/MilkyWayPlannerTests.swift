// Packages/PlannerKit/Tests/PlannerKitTests/MilkyWayPlannerTests.swift
//
// Phase 4: Milky Way tool reports, Planner panel 5, map arc and jumps.
// Season shape checked against published guides: core season roughly February to October
// in both hemispheres, with the longest nights in June/July; at 52°N there is no
// astronomical night in June and July, so no core window then (see AstroCore's
// MilkyWayTests for the per-night Skyfield comparison).

import AstroCore
import Foundation
import Testing
@testable import PlannerKit

struct MilkyWayPlannerTests {
    static let joshuaTree = PillLocation(name: "Joshua Tree", latitude: 34.1347, longitude: -116.3131, elevation: 900,
                                         timeZoneIdentifier: "America/Los_Angeles")
    static let laPalma = PillLocation(name: "La Palma", latitude: 28.7606, longitude: -17.8816, elevation: 2400,
                                      timeZoneIdentifier: "Atlantic/Canary")
    static let warsaw = PillLocation.samples[0]
    static let sydney = PillLocation.samples[2]

    @Test func nightReportOnNewMoon() {
        let day = LocalDay(year: 2026, month: 7, day: 14, timeZone: Self.joshuaTree.timeZone)
        let report = MilkyWayNightReport.compute(location: Self.joshuaTree, day: day)
        #expect(report.visible.count == 1)
        // Skyfield: 2026-07-15 04:39:04Z – 10:34:23Z (Golden/milkyway.json).
        let span = report.visible[0]
        #expect(abs(span.start.timeIntervalSince(PlannerTests.instant("2026-07-15T04:39:04Z"))) < 120)
        #expect(abs(span.end.timeIntervalSince(PlannerTests.instant("2026-07-15T10:34:23Z"))) < 120)
        #expect(report.moonInterference == .none)
        let best = report.bestMoment!
        #expect(best.altitude > 20 && best.altitude < 30)
        #expect(abs(best.azimuth - 180) < 25)
        #expect(report.path.count == 97)
    }

    @Test func fullMoonInterferes() {
        let day = LocalDay(year: 2026, month: 8, day: 27, timeZone: Self.laPalma.timeZone)
        let report = MilkyWayNightReport.compute(location: Self.laPalma, day: day)
        #expect(report.moonIllumination > 0.95)
        #expect(report.moonInterference == .severe)
    }

    @Test func yearSeasonNorth() {
        let year = MilkyWayYearReport.compute(location: Self.joshuaTree, year: 2026)
        #expect(year.nights.count == 365)
        let start = year.seasonStart!, end = year.seasonEnd!
        #expect([1, 2].contains(start.month), "season starts \(start)")
        #expect([10, 11].contains(end.month), "season ends \(end)")
        let months = year.months
        #expect(months[11].visibleHours == 0)
        #expect(Set(year.bestMonths.prefix(3).map(\.month)).isSubset(of: [5, 6, 7, 8]))
        // Best nights cluster around new moons.
        for night in year.bestNights(5) { #expect(night.moonIllumination < 0.35, "\(night.day)") }
    }

    @Test func yearSeasonWarsawHasSummerGap() {
        let months = MilkyWayYearReport.compute(location: Self.warsaw, year: 2026).months
        // No astronomical night from about late May to late July at 52°N.
        #expect(months[5].visibleHours == 0)
        #expect(months[6].visibleHours < months[3].visibleHours / 4)
        #expect(months[3].visibleHours > 0 && months[7].visibleHours > 0)
    }

    @Test func yearSeasonSouth() {
        let year = MilkyWayYearReport.compute(location: Self.sydney, year: 2026)
        let best = year.bestMonths.prefix(3).map(\.month)
        #expect(Set(best).isSubset(of: [4, 5, 6, 7, 8]), "\(best)")
        #expect(year.months[11].visibleHours < 1)
    }

    // MARK: Planner

    @Test func plannerPanelAndOverlays() {
        let snap = PlannerTests.snapshot(Self.laPalma, "2026-06-16T02:00:00Z")
        #expect(snap.galacticCenter.isUp)
        let gc = MilkyWay.center(at: AstroTime(snap.instant), observer: Self.laPalma.observer)
        #expect(abs(snap.galacticCenter.azimuth - gc.azimuth) < 1e-9)
        let panel = PlannerPanels.panel(.milkyWay, snapshot: snap, instant: snap.instant, options: PlannerDisplayOptions())
        let value = { (label: String) in panel.rows.first { $0.label == label }?.value ?? "" }
        // Night of 15 June (local): Skyfield window 21:45Z–04:38Z = 22:45–05:38 WEST.
        #expect(value("Core visible").hasPrefix("22:4"))
        #expect(value("Arc").hasPrefix(ArcOrientation.of(tilt: snap.arcTilt).label))
        #expect(value("Moon-free") == value("Core visible"))

        let all = PlannerOverlays.build(snap, radius: 3000)
        let arc = all.lines.filter { $0.body == .galacticCenter && $0.role == .pathUp }
        #expect(!arc.isEmpty)
        for line in arc { for p in line.points { #expect(p.latitude.isFinite && p.longitude.isFinite) } }
        #expect(all.markers.contains { $0.body == .galacticCenter })
        let none = PlannerOverlays.build(snap, radius: 3000, layers: [.sun, .moon])
        #expect(!none.lines.contains { $0.body == .galacticCenter })
        let onlyMilkyWay = PlannerOverlays.build(snap, radius: 3000, layers: .milkyWay)
        #expect(onlyMilkyWay.lines.allSatisfy { $0.body == .galacticCenter })
    }

    @Test func nightPanelBeforeAndAfterNoon() {
        // 03:00 local on 16 June belongs to the night of 15 June; 23:00 to the night of 16 June.
        let morning = PlannerTests.snapshot(Self.laPalma, "2026-06-16T02:00:00Z")
        let night = morning.day.night(containing: morning.instant)
        #expect(LocalDay(containing: night.start, timeZone: Self.laPalma.timeZone).day == 15)
        let evening = PlannerTests.snapshot(Self.laPalma, "2026-06-16T22:00:00Z")
        #expect(LocalDay(containing: evening.day.night(containing: evening.instant).start, timeZone: Self.laPalma.timeZone).day == 16)
    }

    @Test func milkyWayJumps() {
        let snap = PlannerTests.snapshot(Self.laPalma, "2026-06-16T12:00:00Z")
        let starts = PlannerJump.milkyWayStart.candidates(in: snap.day)
        let ends = PlannerJump.milkyWayEnd.candidates(in: snap.day)
        // On 16 June the morning window ends (~05:38) and the evening one starts (~22:4x).
        #expect(starts.count == 1 && ends.count == 1)
        #expect(ends[0] < starts[0])
        // Warsaw in June: nothing to jump to.
        let warsaw = PlannerTests.snapshot(Self.warsaw, "2026-06-21T12:00:00Z")
        #expect(PlannerJump.milkyWayStart.candidates(in: warsaw.day).isEmpty)
    }

    @Test func polarPinHasNoCore() {
        let north = PillLocation(name: "Pole", latitude: 89.9, longitude: 0, timeZoneIdentifier: "UTC")
        let snap = PlannerTests.snapshot(north, "2026-12-21T00:00:00Z")
        #expect(!snap.galacticCenter.isUp)
        let panel = PlannerPanels.panel(.milkyWay, snapshot: snap, instant: snap.instant, options: PlannerDisplayOptions())
        #expect(panel.rows.first { $0.label == "Core visible" }?.value == "Not tonight")
        // The core is down but half the band is still above the horizon.
        #expect(PlannerOverlays.build(snap, radius: 1000).lines.contains { $0.body == .galacticCenter && $0.role == .pathUp })
    }
}
