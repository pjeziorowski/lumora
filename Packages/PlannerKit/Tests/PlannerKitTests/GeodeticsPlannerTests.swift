// Packages/PlannerKit/Tests/PlannerKitTests/GeodeticsPlannerTests.swift
//
// Phase 6: the target pin, panels 6 (geodetics) and 7 (obstacle), and the field and depth
// of field drawn on the map. Distances and bearings come from GeoCore's Vincenty solution
// (checked against GeographicLib there); here the checks are that the panels and overlays
// use them consistently, and that the obstacle answers are self-consistent.

import AstroCore
import Foundation
import GeoCore
import OpticsCore
import Testing
@testable import PlannerKit

@MainActor
struct GeodeticsPlannerTests {
    static let manhattan = FindTests.manhattan
    /// 3 km along the Manhattanhenge azimuth, across the Hudson on the Palisades.
    static var palisades: GeoPoint { Geodesy.destination(from: manhattan.geoPoint, bearing: 299.1, distance: 3000).normalized }

    @Test func geodeticsReport() {
        let target = TargetPin(point: Self.palisades, groundElevation: 60, objectHeight: 40)
        let g = GeodeticsReport.compute(observer: Self.manhattan, eyeHeight: 1.7, target: target)
        #expect(abs(g.distance - 3000) < 0.01)
        #expect(abs(g.bearing - 299.1) < 1e-6)
        #expect(abs(g.backBearing - 119.1) < 0.05)
        #expect(abs(g.heightDifference! - 58.3) < 1e-9)
        let expectedTop = atan((100 - 1.7 - Sightline.drop(distance: 3000)) / 3000) * 180 / .pi
        #expect(abs(g.topAngle - expectedTop) < 1e-9)
        #expect(g.topAngle > g.groundAngle)
    }

    @Test func obstacleAlignmentsAreConsistent() {
        let day = LocalDay(year: 2026, month: 5, day: 29, timeZone: Self.manhattan.timeZone)
        let target = TargetPin(point: Self.palisades, groundElevation: 0, objectHeight: 0)
        let report = ObstacleReport.compute(observer: Self.manhattan, eyeHeight: 0, target: target, day: day)
        let sun = report.alignments.filter { $0.body == .sun }
        // The Sun crosses 299.1° once that evening, near the AMNH time (20:13 EDT).
        #expect(sun.count == 1)
        #expect(abs(sun[0].time.timeIntervalSince(PlannerTests.instant("2026-05-30T00:13:00Z"))) < 120)
        // An object exactly `heightForAlignment` tall puts the Sun's centre on its top.
        let tall = TargetPin(point: Self.palisades, groundElevation: 0, objectHeight: sun[0].heightForAlignment)
        let check = ObstacleReport.compute(observer: Self.manhattan, eyeHeight: 0, target: tall, day: day)
        #expect(abs(check.alignments.first { $0.body == .sun }!.clearance) < 1e-6)
        // A 300 m object hides it.
        let tower = TargetPin(point: Self.palisades, groundElevation: 0, objectHeight: 300)
        #expect(ObstacleReport.compute(observer: Self.manhattan, eyeHeight: 0, target: tower, day: day)
            .alignments.first { $0.body == .sun }!.clearance < 0)
    }

    @Test func panelsWithAndWithoutTarget() {
        let snap = PlannerTests.snapshot(Self.manhattan, "2026-05-30T00:00:00Z")
        let empty = PlannerPanels.panel(.geodetics, snapshot: snap, instant: snap.instant, options: PlannerDisplayOptions())
        #expect(empty.rows.first?.value == "None")
        let report = ObstacleReport.compute(observer: Self.manhattan, eyeHeight: 1.7,
                                            target: TargetPin(point: Self.palisades, groundElevation: nil, objectHeight: 50),
                                            day: snap.day.day)
        let geo = PlannerPanels.panel(.geodetics, snapshot: snap, instant: snap.instant, options: PlannerDisplayOptions(),
                                      obstacle: report)
        let value = { (label: String) in geo.rows.first { $0.label == label }?.value ?? "" }
        #expect(value("Distance") == "3.00 km")
        #expect(value("Bearing").hasPrefix("299.10°"))
        #expect(value("Target ground") == "Unknown (sea level used)")
        let obstacle = PlannerPanels.panel(.obstacle, snapshot: snap, instant: snap.instant, options: PlannerDisplayOptions(),
                                           obstacle: report)
        #expect(obstacle.rows.contains { $0.label == "Sun on the line" && $0.value.hasPrefix("20:1") })
        #expect(obstacle.rows.contains { $0.label == "Object height" && $0.value == "50 m" })
    }

    @Test func mapOpticsGeometry() {
        var optics = MapOptics()
        optics.showFieldOfView = true
        optics.showDepthOfField = true
        optics.focalLength = 50
        optics.aperture = 8
        let sensor = Sensor(widthMM: 36, heightMM: 24)
        let g = MapOpticsGeometry.compute(optics, sensor: sensor, coc: 0.03, targetDistance: 3000, targetBearing: 299.1, radius: 500)
        #expect(abs(g.horizontalAngle - 39.6) < 0.05)
        #expect(g.focus == 3000 && g.bearing == 299.1)
        // 50 mm f/8 c 0.03: hyperfocal 10.47 m, so focused at 3 km the far limit is infinite.
        #expect(g.far == nil && abs(g.hyperfocal - 10.4667) < 0.001 && abs(g.near - 10.43) < 0.05)
        let pin = Self.manhattan.geoPoint
        let lines = PlannerOverlays.opticsLines(optics, geometry: g, pin: pin)
        let edges = lines.filter { $0.role == .fovEdge }
        #expect(edges.count == 2)
        let bearings = edges.map { Geodesy.inverse(pin, $0.points[1]).initialBearing }.sorted()
        #expect(abs(bearings[0] - (299.1 - 19.8)) < 0.05 && abs(bearings[1] - (299.1 + 19.8)) < 0.05)
        #expect(!lines.contains { $0.role == .dofFar })
        // Close focus: all three arcs, at the DoF distances.
        optics.focusOnTarget = false
        optics.focusDistance = 5
        let close = MapOpticsGeometry.compute(optics, sensor: sensor, coc: 0.03, targetDistance: 3000, targetBearing: 299.1, radius: 500)
        let r = DepthOfField.compute(DoFInput(focalLength: 50, aperture: 8, distance: 5000, coc: 0.03))
        #expect(abs(close.near - r.near / 1000) < 1e-9 && abs(close.far! - r.far / 1000) < 1e-9)
        let arcs = PlannerOverlays.opticsLines(optics, geometry: close, pin: pin)
        let far = arcs.first { $0.role == .dofFar }!
        for p in far.points { #expect(abs(Geodesy.inverse(pin, p).distance - close.far!) < 0.01) }
    }

    @Test func plannerStateTarget() async {
        let session = PillSession(defaults: nil, fallback: Self.manhattan) { PlannerTests.instant("2026-05-30T00:00:00Z") }
        let state = PlannerState(session: session, elevation: { _, _ in 61.5 })
        state.refresh()
        await state.settle()
        await state.setTarget(Self.palisades, objectHeight: 20)
        #expect(state.target?.groundElevation == 61.5)
        #expect(state.obstacle != nil)
        #expect(abs(state.obstacle!.geodetics.topAngle
            - Sightline.apparentElevation(observerHeight: 0 + 1.7, targetHeight: 81.5, distance: 3000)) < 1e-9)
        state.setObjectHeight(0)
        #expect(state.obstacle!.geodetics.objectHeight == 0)
        await state.setTarget(nil)
        #expect(state.obstacle == nil)
        // Find through the state jumps the Planner to a match.
        let matches = await state.find(FindQuery(body: .sun, azimuth: 299.1, azimuthTolerance: 0.15, elevation: 0.5,
                                                 elevationTolerance: 0.5, start: PlannerTests.instant("2026-05-25T00:00:00Z"),
                                                 end: PlannerTests.instant("2026-06-05T00:00:00Z")))
        #expect(!matches.isEmpty)
        state.show(matches[0])
        #expect(session.instant == matches[0].time)
    }
}
