// Packages/OpticsCore/Tests/OpticsCoreTests/OpticsCoreTests.swift
//
// Phase 5 calculators against published values. Sources (retrieved 2026-10-19):
//  [W]  Wikipedia, "Hyperfocal distance": 50 mm f/8, c = 0.03 mm → f²/(Nc) = 10 417 mm,
//       0.5% from the f²/(Nc) + f definition; focused at H the near limit is H/2 (5.2 m).
//  [BA] Bob Atkins, "Depth of field" (bobatkins.com): 24 mm f/8 hyperfocal 2.88 m, near
//       limit 1.44 m when focused there; 50 mm f/11 at 3 m has ~0.7 m in front, ~1.4 m
//       behind; Airy disc 2.7 µm at f/2, 30 µm at f/22, 43 µm at f/32; 8×10 in print at
//       10 in allows 0.2 mm blur, 0.025 mm on a 35 mm frame enlarged 8×.
//  [LS] Light Stalking, "NPF rule": Nikon D750 (35.9 mm, 6016 px) pitch 5.97 µm; 24 mm
//       f/2.8 gives NPF 11.54 s and 500/24 ≈ 21 s.
//  [EV] Standard EV table (ISO 2720 / "sunny 16"): f/1 1 s = EV 0; f/16 1/125 ≈ EV 15.
//  [FoV] Published angles for a 50 mm lens on 36 × 24 mm: 39.6° × 27.0°, diagonal 46.8°;
//       24 mm: diagonal 84.1°.
// DOFMaster and the brief use the Greenleaf thin-lens formulas implemented here; other
// calculators drop the "+ f" term, which the tests bound to within 1% at normal distances.

import Foundation
import Testing
@testable import OpticsCore

struct ExposureTests {
    @Test func evTable() {
        #expect(abs(Exposure.ev(aperture: 1, shutter: 1, iso: 100)) < 1e-12)
        #expect(abs(Exposure.ev(aperture: 16, shutter: 1.0 / 125, iso: 100) - 15) < 0.05)
        // ISO 400 needs two stops less light: EV100 drops by 2.
        #expect(abs(Exposure.ev(aperture: 8, shutter: 1.0 / 60, iso: 400) - (Exposure.ev(aperture: 8, shutter: 1.0 / 60, iso: 100) - 2)) < 1e-12)
    }

    @Test func equivalentExposureKeepsEV() {
        let metered = ExposureSettings(aperture: 8, shutter: 1.0 / 125, iso: 100)
        let wide = Exposure.equivalent(to: metered, fixed: ExposureSettings(aperture: 2.8, shutter: 0, iso: 100), solving: .shutter)
        #expect(abs(wide.ev100 - metered.ev100) < 1e-9)
        // Three stops wider (f/8 → f/2.8 is 3.02 stops) → about 1/1000 s.
        #expect(Exposure.nearest(wide.shutter, on: Exposure.shutterScale) == 1.0 / 1000)
        let iso = Exposure.equivalent(to: metered, fixed: ExposureSettings(aperture: 8, shutter: 1.0 / 500, iso: 0), solving: .iso)
        #expect(abs(iso.iso - 400) < 1e-6)
        let ap = Exposure.equivalent(to: metered, fixed: ExposureSettings(aperture: 0, shutter: 1.0 / 30, iso: 100), solving: .aperture)
        #expect(Exposure.nearest(ap.aperture, on: Exposure.apertureScale) == 16)
    }

    @Test func ndFilters() {
        #expect(abs(NDFilter(opticalDensity: 0.9).stops - 2.99) < 0.01)
        #expect(abs(NDFilter(opticalDensity: 3.0).stops - 9.97) < 0.01)
        #expect(abs(NDFilter(factor: 8).stops - 3) < 1e-12)
        #expect(abs(NDFilter(factor: 1000).stops - 9.966) < 0.001)
        #expect(NDFilter(stops: 10).label == "10 stops · ND1000 · 3.0")
        #expect(NDFilter(stops: 6).label == "6 stops · ND64 · 1.8")
        // 1/30 s through 10 stops: 34 s.
        #expect(abs(Exposure.withFilters(shutter: 1.0 / 30, stops: 10) - 34.13) < 0.01)
        #expect(NDFilter.common.count == 22 && NDFilter.common.last?.stops == 20)
    }

    @Test func shutterLabels() {
        #expect(Exposure.shutterLabel(1.0 / 250) == "1/250")
        #expect(Exposure.shutterLabel(0.6) == "0.6\"")
        #expect(Exposure.shutterLabel(2) == "2\"")
        #expect(Exposure.shutterLabel(34.13) == "34\"")
        #expect(Exposure.shutterLabel(90) == "1m 30s")
        #expect(Exposure.shutterLabel(2 * 3600 + 300) == "2h 05m")
    }
}

struct DepthOfFieldTests {
    @Test func wikipediaHyperfocal() {
        let h = DepthOfField.hyperfocal(focalLength: 50, aperture: 8, coc: 0.03)
        let approx = 50.0 * 50 / (8 * 0.03)
        #expect(abs(approx - 10_417) < 1)
        #expect(abs((h - approx) / approx - 0.0048) < 0.0005)
        // Focused at H, sharp from about H/2 (5.2 m) to infinity.
        let r = DepthOfField.compute(DoFInput(focalLength: 50, aperture: 8, distance: h, coc: 0.03))
        #expect(r.isFarInfinite)
        #expect(abs(r.near - 5233) < 1)
    }

    @Test func bobAtkinsExamples() {
        // 24 mm f/8: 2.88 m with f²/(Nc) and c = 0.025; within 1% with the + f term.
        let h = DepthOfField.hyperfocal(focalLength: 24, aperture: 8, coc: 0.025)
        #expect(abs(h - 2880) / 2880 < 0.01)
        let r = DepthOfField.compute(DoFInput(focalLength: 24, aperture: 8, distance: h, coc: 0.025))
        #expect(abs(r.near - 1440) / 1440 < 0.01)
        // 50 mm f/11 at 3 m: about 0.7 m in front and 1.4 m behind (twice as much behind).
        let s = DepthOfField.compute(DoFInput(focalLength: 50, aperture: 11, distance: 3000, coc: 0.025))
        #expect(abs(s.inFront - 735) < 10 && abs(s.behind - 1441) < 10)
        #expect(abs(s.behind / s.inFront - 1.96) < 0.05)
    }

    @Test func greenleafIdentities() {
        // Focused at s, near and far are harmonic about s: 1/near + 1/far = 2/s for f ≪ s.
        for (f, n, s) in [(24.0, 5.6, 2000.0), (85, 1.8, 3000), (200, 4, 15_000)] {
            let r = DepthOfField.compute(DoFInput(focalLength: f, aperture: n, distance: s, coc: 0.03))
            #expect(r.near < s && r.far > s)
            let h = r.hyperfocal
            // Exact Greenleaf: near = s(H−f)/(H+s−2f).
            #expect(abs(r.near - s * (h - f) / (h + s - 2 * f)) < 1e-9)
            // The approximate form (H ≈ f²/Nc, near = Hs/(H+s)) used by other calculators: within 1%.
            let ha = f * f / (n * 0.03)
            #expect(abs(r.near - ha * s / (ha + s)) / r.near < 0.01)
        }
    }

    @Test func teleconverter() {
        // A 1.4× converter on 100 mm f/4 behaves like 140 mm f/5.6.
        let tc = DepthOfField.compute(DoFInput(focalLength: 100, aperture: 4, distance: 5000, coc: 0.03, teleconverter: 1.4))
        let bare = DepthOfField.compute(DoFInput(focalLength: 140, aperture: 5.6, distance: 5000, coc: 0.03))
        #expect(abs(tc.near - bare.near) < 1e-6 && abs(tc.far - bare.far) < 1e-6)
    }

    @Test func diffraction() {
        #expect(abs(DepthOfField.airyDisc(aperture: 2) * 1000 - 2.7) < 0.05)
        #expect(abs(DepthOfField.airyDisc(aperture: 22) * 1000 - 30) < 0.5)
        #expect(abs(DepthOfField.airyDisc(aperture: 32) * 1000 - 43) < 0.5)
        // A 4.35 µm sensor (e.g. 42 MP full frame) becomes diffraction-limited around f/6.5.
        let limit = DepthOfField.diffractionLimitedAperture(pixelPitchMicrons: 4.35)
        #expect(abs(limit - 6.48) < 0.05)
        #expect(!DepthOfField.isDiffractionLimited(aperture: 5.6, pixelPitchMicrons: 4.35))
        #expect(DepthOfField.isDiffractionLimited(aperture: 8, pixelPitchMicrons: 4.35))
    }

    @Test func printBasedCoC() {
        // 8×10 in (325.3 mm diagonal) at 250 mm (~10 in), 5 lp/mm: 0.2 mm on the print.
        let c = DepthOfField.coc(sensorDiagonal: Sensor.fullFrameDiagonalMM, printDiagonal: 325.3)
        #expect(abs(c - 0.0266) < 0.0002)
        // Bob Atkins: 8× enlargement → 0.025 mm.
        let eight = DepthOfField.coc(sensorDiagonal: 10, printDiagonal: 80)
        #expect(abs(eight - 0.025) < 1e-12)
        // Twice the viewing distance doubles the allowed blur (0.05 mm for 8×10 at 20 in).
        let far = DepthOfField.coc(sensorDiagonal: 10, printDiagonal: 80, viewingDistance: 500)
        #expect(abs(far - 0.05) < 1e-12)
    }

    @Test func tables() {
        let rows = DepthOfField.table(focalLength: 35, coc: 0.03, apertures: [2.8, 8, 16], distances: [1000, 3000, 10_000])
        #expect(rows.count == 3 && rows[0].cells.count == 3)
        // Depth grows with f-number at every distance.
        for column in 0..<3 { #expect(rows[0].cells[column].total < rows[2].cells[column].total) }
        let hyper = DepthOfField.hyperfocalTable(focalLengths: [14, 24, 50], apertures: [2.8, 8], coc: 0.03)
        #expect(hyper[0][0] < hyper[2][0] && hyper[1][1] < hyper[1][0])
    }
}

struct FieldOfViewTests {
    @Test func fiftyOnFullFrame() {
        let r = FieldOfView.compute(sensor: .fullFrame, focalLength: 50, distance: 10_000)
        #expect(abs(r.horizontal - 39.6) < 0.05)
        #expect(abs(r.vertical - 27.0) < 0.05)
        #expect(abs(r.diagonal - 46.8) < 0.05)
        #expect(abs(r.frameWidth - 7200) < 1e-9 && abs(r.frameHeight - 4800) < 1e-9)
        #expect(abs(r.equivalentFocalLength - 50) < 1e-9)
        #expect(abs(r.magnification - 50.0 / 9950) < 1e-12)
        let d24 = FieldOfView.compute(sensor: .fullFrame, focalLength: 24, distance: 1000).diagonal
        #expect(abs(d24 - 84.1) < 0.05)
    }

    @Test func portraitAndCrop() {
        let apsc = Sensor(widthMM: 23.5, heightMM: 15.6, pixelsWide: 6000, pixelsHigh: 4000)
        #expect(abs(apsc.cropFactor - 1.53) < 0.01)
        let p = FieldOfView.compute(sensor: apsc, focalLength: 35, distance: 5000, orientation: .portrait)
        #expect(p.horizontal < p.vertical)
        #expect(abs(p.equivalentFocalLength - 35 * apsc.cropFactor) < 1e-9)
    }

    @Test func inverse() {
        // Frame a 2 m wide subject from 5 m on full frame: 90 mm.
        let f = FieldOfView.focalLength(forFrameWidth: 2000, distance: 5000, sensor: .fullFrame)
        #expect(abs(f - 90) < 1e-9)
        let d = FieldOfView.distance(forFrameWidth: 2000, focalLength: 90, sensor: .fullFrame)
        #expect(abs(d - 5000) < 1e-9)
        #expect(abs(FieldOfView.focalLength(forAngle: 39.5978, dimension: 36) - 50) < 0.001)
    }
}

struct NightSkyTests {
    static let d750 = Sensor(widthMM: 35.9, heightMM: 24.0, pixelsWide: 6016, pixelsHigh: 4016)

    @Test func lightStalkingNPF() {
        let pitch = Self.d750.pixelPitchMicrons!
        #expect(abs(pitch - 5.97) < 0.005)
        #expect(abs(SpotStars.npf(aperture: 2.8, pixelPitchMicrons: pitch, focalLength: 24) - 11.54) < 0.01)
        #expect(abs(SpotStars.rule(focalLength: 24, cropFactor: 1) - 21) < 0.5)
        #expect(abs(Self.d750.cropFactor - 1.002) < 0.001)
        #expect(abs(SpotStars.rule(constant: 600, focalLength: 24, cropFactor: 1) - 25) < 1e-12)
    }

    @Test func npfDeclinationAndAccurate() {
        let equator = SpotStars.npf(aperture: 2.8, pixelPitchMicrons: 5.97, focalLength: 24)
        let sixty = SpotStars.npf(aperture: 2.8, pixelPitchMicrons: 5.97, focalLength: 24, declination: 60)
        #expect(abs(sixty - 2 * equator) < 1e-9)
        let accurate = SpotStars.npfAccurate(aperture: 2.8, pixelPitchMicrons: 5.97, focalLength: 24)
        // (16.856·2.8 + 0.0997·24 + 13.713·5.97) / 24
        #expect(abs(accurate - (16.856 * 2.8 + 0.0997 * 24 + 13.713 * 5.97) / 24) < 1e-12)
        #expect(accurate < equator)
        #expect(SpotStars.npf(aperture: 2.8, pixelPitchMicrons: 5.97, focalLength: 24, declination: 90).isFinite)
    }

    @Test func starTrails() {
        // A full circle around the pole takes one sidereal day, 86 164 s.
        #expect(abs(StarTrails.seconds(forArc: 360) - 86_164) < 2)
        // 30 s at the equator: 0.1253° of sky.
        let r = StarTrails.compute(seconds: 30, focalLength: 24, sensor: Self.d750)
        #expect(abs(r.angle - 0.12534) < 1e-4)
        #expect(abs(r.lengthMM - r.angle * .pi / 180 * 24) < 1e-12)
        #expect(abs(r.lengthPixels! - r.lengthMM / (35.9 / 6016)) < 1e-9)
        let back = StarTrails.seconds(forPixels: r.lengthPixels!, focalLength: 24, pixelPitchMicrons: Self.d750.pixelPitchMicrons!)
        #expect(abs(back - 30) < 1e-9)
        #expect(StarTrails.compute(seconds: 30, focalLength: 24, sensor: Self.d750, declination: 89).angle < r.angle / 50)
    }
}

struct TimeLapseTests {
    @Test func solveEachUnknown() {
        // 20 minutes every 5 s at 24 fps → 240 frames, a 10 s clip.
        let plan = TimeLapsePlan(duration: 1200, interval: 5, fps: 24, clipLength: 10)
        for unknown in TimeLapse.Unknown.allCases {
            var blank = plan
            switch unknown {
            case .duration: blank.duration = 0
            case .interval: blank.interval = 0
            case .fps: blank.fps = 0
            case .clipLength: blank.clipLength = 0
            }
            let solved = TimeLapse.solve(blank, for: unknown)
            #expect(abs(solved.duration - 1200) < 1e-9 && abs(solved.interval - 5) < 1e-9)
            #expect(abs(solved.fps - 24) < 1e-9 && abs(solved.clipLength - 10) < 1e-9)
        }
        #expect(plan.photos == 241)
        #expect(plan.speedUp == 120)
    }

    @Test func memoryBatteryWarnings() {
        let plan = TimeLapsePlan(duration: 3 * 3600, interval: 25, fps: 25, clipLength: 17.28)
        #expect(plan.photos == 433)
        #expect(abs(TimeLapse.memoryMB(photos: plan.photos, fileSizeMB: 50) - 21_650) < 1e-9)
        #expect(TimeLapse.batteries(photos: plan.photos, shotsPerCharge: 300) == 2)
        #expect(TimeLapse.warnings(plan, shutter: 25, shotsPerCharge: 300) == [.intervalTooShort, .needsBatterySwap])
        #expect(TimeLapse.warnings(plan, shutter: 20).isEmpty)
    }
}

struct SensorTests {
    @Test func fullFrameDefaults() {
        #expect(abs(Sensor.fullFrame.defaultCoC - 0.02884) < 1e-5)
        #expect(abs(Sensor.fullFrame.cropFactor - 1) < 1e-12)
        #expect(Sensor.fullFrame.pixelPitchMicrons == nil)
        let r = NightSkyTests.d750.rotated
        #expect(r.widthMM == 24 && r.pixelsWide == 4016)
        #expect(abs(NightSkyTests.d750.megapixels - 24.16) < 0.01)
    }
}
