// Packages/PlannerKit/Tests/PlannerKitTests/ARTests.swift
//
// Phase 8 acceptance: attitude → view direction, Core Motion's matrix convention, the pinhole
// projection and its inverse, calibration, and the AR sky features.
//
// Core Motion convention: `CMAttitude.rotationMatrix` takes reference-frame vectors to device
// coordinates, as used by Apple's pARk sample code (WWDC 2012, "pARk": the camera transform is
// built from the matrix and applied to points given as north, west, up). In the
// `.xTrueNorthZVertical` frame the identity attitude is a phone lying face up with its right
// edge (x) toward true north (Apple, "CMAttitudeReferenceFrame").

import AstroCore
import Foundation
import Testing
@testable import PlannerKit

struct ARTests {
    let size = (width: 393.0, height: 852.0)

    func projector(_ attitude: ARAttitude, orientation: ARScreenOrientation = .portrait,
                   calibration: ARCalibration = .none, fov: Double = 60) -> ARProjector {
        let w = orientation == .portrait ? size.width : size.height
        let h = orientation == .portrait ? size.height : size.width
        return ARProjector(attitude: attitude, orientation: orientation, calibration: calibration,
                           focal: ARLens.focalPoints(horizontalFieldOfView: fov, width: w), width: w, height: h)
    }

    @Test func attitudeGivesViewDirection() {
        for (az, el, roll) in [(0.0, 0.0, 0.0), (123.4, 17.5, 0.0), (359.5, -12.0, 25.0), (271.0, 88.0, -40.0), (45.0, 30.0, 90.0)] {
            let p = projector(ARAttitude(azimuth: az, elevation: el, roll: roll))
            #expect(abs(ARAngles.signed(p.viewAzimuth - az)) < 1e-9)
            #expect(abs(p.viewElevation - el) < 1e-9)
            #expect(abs(p.roll - roll) < 1e-6)
        }
    }

    @Test func coreMotionConvention() {
        // Identity: face up, right edge north, so the back camera looks straight down.
        let flat = ARAttitude.fromCoreMotion([1, 0, 0, 0, 1, 0, 0, 0, 1])
        #expect(abs(projector(flat).viewElevation + 90) < 1e-9)
        // Upright in portrait looking north: x = east, y = up, z = south, written in the
        // reference frame (north, west, up) as the matrix rows.
        let north = ARAttitude.fromCoreMotion([0, -1, 0, 0, 0, 1, -1, 0, 0])
        let p = projector(north)
        #expect(abs(ARAngles.signed(p.viewAzimuth)) < 1e-9)
        #expect(abs(p.viewElevation) < 1e-9)
        #expect(abs(p.roll) < 1e-9)
        // The same phone turned to face east: x = south, y = up, z = west.
        let east = ARAttitude.fromCoreMotion([-1, 0, 0, 0, 0, 1, 0, 1, 0])
        #expect(abs(projector(east).viewAzimuth - 90) < 1e-9)
    }

    @Test func projectionAndInverse() {
        let p = projector(ARAttitude(azimuth: 250, elevation: 10))
        let centre = p.project(azimuth: 250, elevation: 10)!
        #expect(abs(centre.x - size.width / 2) < 1e-9 && abs(centre.y - size.height / 2) < 1e-9)
        // Half the horizontal field of view to the right lands on the right edge.
        let level = projector(ARAttitude(azimuth: 250, elevation: 0))
        let edge = level.project(azimuth: 280, elevation: 0)!
        #expect(abs(edge.x - size.width) < 1e-9)
        #expect(abs(edge.y - size.height / 2) < 1e-9)
        // Higher on the sky is higher on screen; behind the camera is nothing.
        #expect(level.project(azimuth: 250, elevation: 5)!.y < size.height / 2)
        #expect(level.project(azimuth: 70, elevation: 0) == nil)
        // Round trip through the inverse.
        let tilted = projector(ARAttitude(azimuth: 12, elevation: 33, roll: 17))
        for (x, y) in [(0.0, 0.0), (100.0, 700.0), (393.0, 852.0), (196.5, 426.0)] {
            let v = tilted.direction(at: ARScreenPoint(x: x, y: y))
            let back = tilted.project(v)!
            #expect(abs(back.x - x) < 1e-9 && abs(back.y - y) < 1e-9)
        }
    }

    @Test func landscapeKeepsTheHorizonLevel() {
        // Turned a quarter clockwise with the interface in landscape-left: the horizon is level
        // and the view still points where the camera does.
        let p = projector(ARAttitude(azimuth: 200, elevation: 0, roll: 90), orientation: .landscapeLeft)
        let left = p.project(azimuth: 190, elevation: 0)!, right = p.project(azimuth: 210, elevation: 0)!
        #expect(abs(left.y - right.y) < 1e-9)
        #expect(left.x < right.x)
        #expect(p.project(azimuth: 200, elevation: 10)!.y < p.height / 2)
        #expect(abs(p.viewAzimuth - 200) < 1e-9)
    }

    @Test func calibrationShiftsAndAligns() {
        let raw = ARAttitude(azimuth: 100, elevation: 10)
        let shifted = projector(raw, calibration: ARCalibration(heading: 5, pitch: 2))
        #expect(abs(shifted.viewAzimuth - 105) < 1e-9)
        #expect(abs(shifted.viewElevation - 12) < 1e-9)

        // Outdoor acceptance, simulated: the compass reads 7° east of the truth and the
        // horizon sensor 1.5° high. The user centres the Sun and taps Align; afterwards the
        // Moon, elsewhere in the frame, lands on its true direction.
        let warsaw = PillLocation.samples[0]
        let instant = Date(timeIntervalSince1970: 1_781_366_400) // 2026-06-13 16:00 UTC
        let sun = Ephemeris.horizontal(.sun, at: AstroTime(instant), observer: warsaw.observer)
        let moon = Ephemeris.horizontal(.moon, at: AstroTime(instant), observer: warsaw.observer)
        // The phone really points at the Sun, but its sensors say otherwise.
        let sensed = ARAttitude(azimuth: sun.azimuth + 7, elevation: sun.altitude + 1.5)
        let before = projector(sensed, fov: 80)
        let calibration = ARCalibration.none.aligning(view: (before.viewAzimuth, before.viewElevation),
                                                      to: (sun.azimuth, sun.altitude))
        let after = projector(sensed, calibration: calibration, fov: 80)
        let sunPoint = after.project(azimuth: sun.azimuth, elevation: sun.altitude)!
        #expect(abs(sunPoint.x - after.width / 2) < 1e-6 && abs(sunPoint.y - after.height / 2) < 1e-6)
        if let moonPoint = after.project(azimuth: moon.azimuth, elevation: moon.altitude) {
            let seen = after.direction(at: moonPoint)
            #expect(abs(ARAngles.signed(seen.azimuth - moon.azimuth)) < 0.01)
            #expect(abs(seen.elevation - moon.altitude) < 0.01)
        }
    }

    @Test func lensFieldOfView() {
        // A 69.4° (4:3) main camera in a 393 × 852 portrait preview: the long side shows the
        // full 69.4°, the short side is cropped to about 35°.
        let f = ARLens.focalPoints(cameraFieldOfView: 69.4, width: 393, height: 852)
        #expect(abs(ARLens.fieldOfView(size: 852, focal: f) - 69.4) < 1e-9)
        #expect(abs(ARLens.fieldOfView(size: 393, focal: f) - 35.4) < 0.1)
        // A 4:3 preview shows the whole frame both ways.
        let full = ARLens.focalPoints(cameraFieldOfView: 60, width: 300, height: 400)
        #expect(abs(ARLens.fieldOfView(size: 400, focal: full) - 60) < 1e-9)
        #expect(abs(ARLens.fieldOfView(size: 300, focal: full) - 2 * atan(tan(30 * Double.pi / 180) * 0.75) * 180 / .pi) < 1e-9)
    }

    @Test func nightFeatures() {
        // The celestial equator rises due east and sets due west; the pole stands at the latitude.
        let lat = 52.2297
        let equator = ARSky.declinationCircle(0, latitude: lat, step: 90)
        #expect(abs(equator[1].azimuth - 90) < 1e-9)   // hour angle −90°
        #expect(abs(equator[3].azimuth - 270) < 1e-9)  // hour angle +90°
        let warsaw = ARSky.compute(location: PillLocation.samples[0], instant: Date(timeIntervalSince1970: 1_781_301_600),
                                   mode: .night)
        let pole = warsaw.markers.first { $0.kind == .celestialPole }!
        #expect(abs(pole.direction.elevation - lat) < 0.02) // plus 0.01° of refraction
        let polaris = warsaw.markers.first { $0.kind == .polaris }!
        let separation = acos(pole.direction.dot(polaris.direction)) * 180 / .pi
        #expect(separation > 0.6 && separation < 0.8) // Polaris is ~0.65° from the pole in 2026
        #expect(warsaw.lines.filter { $0.kind == .starTrail }.count == 3)
        // Southern sky: the south pole, no Polaris.
        let cape = ARSky.compute(location: PillLocation.samples[5], instant: Date(timeIntervalSince1970: 1_781_301_600),
                                 mode: .night)
        #expect(cape.markers.contains { $0.kind == .celestialPole && abs($0.direction.azimuth - 180) < 1e-9 })
        #expect(!cape.markers.contains { $0.kind == .polaris })
    }

    @Test func sunMoonAndFrameFeatures() {
        let warsaw = PillLocation.samples[0]
        let instant = Date(timeIntervalSince1970: 1_781_366_400)
        let sky = ARSky.compute(location: warsaw, instant: instant, mode: .sunMoon)
        let sun = Ephemeris.horizontal(.sun, at: AstroTime(instant), observer: warsaw.observer)
        let marker = sky.markers.first { $0.kind == .sun }!
        #expect(abs(marker.direction.azimuth - sun.azimuth) < 1e-9)
        #expect(abs(marker.direction.elevation - sun.altitude) < 1e-9)
        // Summer day in Warsaw: the Sun is up for 16+ hours, so 17+ hour marks above −6°.
        #expect(sky.markers.filter { $0.kind == .sunHour }.count >= 17)
        #expect(sky.lines.contains { $0.kind == .sunPath } && sky.lines.contains { $0.kind == .moonPath })

        // Ground lines for the depth of field: 1.6 m eye height, flat ground 10 m away lies
        // 9.09° below the horizon.
        #expect(abs(ARSky.groundDepression(distance: 10, eyeHeight: 1.6) - 9.0903) < 1e-4)
        let frame = ARSky.compute(location: warsaw, instant: instant, mode: .frame,
                                  focus: ARFocusLines(near: 3, focus: 6, far: nil))
        #expect(frame.lines.contains { $0.kind == .focusNear } && !frame.lines.contains { $0.kind == .focusFar })

        // Midnight sun at Longyearbyen: the path never crosses the horizon, nothing breaks.
        let polar = ARSky.compute(location: PillLocation.samples[7], instant: instant, mode: .sunMoon)
        #expect(polar.lines.first { $0.kind == .sunPath }!.points.allSatisfy { $0.elevation > 0 })
    }

    @Test func polylinesSplitBehindTheCamera() {
        let p = projector(ARAttitude(azimuth: 0, elevation: 0))
        let horizon = stride(from: 0.0, through: 360, by: 2).map { ARVector(azimuth: $0, elevation: 0) }
        let parts = p.polylines(horizon)
        // In front: azimuths 0–~88 and ~272–360, two runs, nothing from behind.
        #expect(parts.count == 2)
        #expect(parts.allSatisfy { run in run.allSatisfy { abs($0.y - p.height / 2) < 1e-9 } })
    }
}
