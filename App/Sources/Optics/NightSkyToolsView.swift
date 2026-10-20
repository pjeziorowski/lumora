// App/Sources/Optics/NightSkyToolsView.swift
//
// Spot stars (longest exposure before stars trail: 500/600 rule, NPF and accurate NPF)
// and star trails (trail length for an exposure, and the exposure for a trail length),
// with a sketch of the trails around the pole.

import CameraCatalog
import OpticsCore
import PlannerKit
import SwiftUI

struct SpotStarsView: View {
    @Environment(CameraStore.self) private var store
    @State private var cameraID = ""
    @State private var focalLength = 20.0
    @State private var aperture = 2.8
    @State private var declination = 0.0
    @State private var ruleConstant = 500.0

    private var camera: Camera { store.camera(id: cameraID) ?? store.defaultCamera }

    var body: some View {
        let pitch = camera.pixelPitchMicrons
        let rule = SpotStars.rule(constant: ruleConstant, focalLength: focalLength, cropFactor: camera.cropFactor)
        let npf = SpotStars.npf(aperture: aperture, pixelPitchMicrons: pitch, focalLength: focalLength, declination: declination)
        let accurate = SpotStars.npfAccurate(aperture: aperture, pixelPitchMicrons: pitch, focalLength: focalLength,
                                             declination: declination)
        Form {
            Section {
                CameraRow(cameraID: $cameraID)
                NumberRow(label: "Focal length", value: $focalLength, unit: "mm", step: 1, range: 4...800)
                ScalePicker(label: "Aperture", value: $aperture, scale: Exposure.apertureScale, format: OpticsFormat.aperture)
                VStack(alignment: .leading) {
                    LabeledContent("Declination", value: String(format: "%.0f°", declination))
                    Slider(value: $declination, in: -89...89, step: 1)
                        .accessibilityIdentifier("spotstars.declination")
                    Text(declinationHint).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                ResultRow(label: "NPF rule", value: OpticsFormat.seconds(npf), emphasised: true)
                ResultRow(label: "NPF accurate", value: OpticsFormat.seconds(accurate))
                ResultRow(label: "\(Int(ruleConstant)) rule", value: OpticsFormat.seconds(rule))
                Picker("Simple rule", selection: $ruleConstant) {
                    Text("500").tag(500.0)
                    Text("400").tag(400.0)
                    Text("300").tag(300.0)
                    Text("600").tag(600.0)
                }
            } header: {
                Text("Longest exposure for pinpoint stars")
            } footer: {
                Text("NPF: (35·N + 30·p) ÷ (f · cos δ), with pixel pitch p = \(String(format: "%.2f", pitch)) µm. "
                     + "Accurate: (16.856·N + 0.0997·f + 13.713·p) ÷ (f · cos δ). The simple rule ignores pixels and "
                     + "trails on high-resolution sensors.")
            }
        }
        .navigationTitle("Spot stars")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if cameraID.isEmpty { cameraID = store.defaultCamera.id } }
    }

    private var declinationHint: String {
        switch abs(declination) {
        case ..<15: String(localized: "Celestial equator: stars move fastest (Orion's belt, the ecliptic).")
        case ..<45: String(localized: "Mid declinations, e.g. the galactic core at −29°.")
        case ..<75: String(localized: "Toward the pole: stars move more slowly.")
        default: String(localized: "Near the pole: stars barely move.")
        }
    }
}

struct StarTrailsView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case length, time
        var id: Self { self }
    }

    @Environment(CameraStore.self) private var store
    @State private var mode: Mode = .length
    @State private var cameraID = ""
    @State private var focalLength = 16.0
    @State private var minutes = 60.0
    @State private var declination = 45.0
    @State private var targetPixels = 200.0

    private var camera: Camera { store.camera(id: cameraID) ?? store.defaultCamera }

    var body: some View {
        let seconds = mode == .length
            ? minutes * 60
            : StarTrails.seconds(forPixels: targetPixels, focalLength: focalLength, pixelPitchMicrons: camera.pixelPitchMicrons,
                                 declination: declination)
        let r = StarTrails.compute(seconds: seconds, focalLength: focalLength, sensor: camera.sensor, declination: declination)
        Form {
            Section {
                Picker("Mode", selection: $mode) {
                    Text("Trail length").tag(Mode.length)
                    Text("Exposure time").tag(Mode.time)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("startrails.mode")
                CameraRow(cameraID: $cameraID)
                NumberRow(label: "Focal length", value: $focalLength, unit: "mm", step: 1, range: 4...800)
                if mode == .length {
                    NumberRow(label: "Total exposure", value: $minutes, unit: "min", step: 5, range: 1...720)
                } else {
                    NumberRow(label: "Trail length", value: $targetPixels, unit: "px", step: 10, range: 1...20_000)
                }
                VStack(alignment: .leading) {
                    LabeledContent("Declination", value: String(format: "%.0f°", declination))
                    Slider(value: $declination, in: -89...89, step: 1)
                }
            }
            Section {
                if mode == .time {
                    ResultRow(label: "Exposure time", value: Formatting.duration(seconds: seconds), emphasised: true)
                }
                ResultRow(label: "Arc swept", value: String(format: "%.2f°", r.angle), emphasised: mode == .length)
                ResultRow(label: "On the sensor", value: String(format: "%.2f mm", r.lengthMM))
                ResultRow(label: "In pixels", value: r.lengthPixels.map { String(format: "%.0f px", $0) } ?? "—")
                ResultRow(label: "Of frame width", value: String(format: "%.1f %%", r.fractionOfWidth * 100))
                TrailSketch(degrees: StarTrails.siderealRate * seconds / 3600)
                    .frame(height: 200)
                    .padding(.vertical, 6)
            } header: {
                Text("Trails")
            } footer: {
                Text("Stars turn 15.04″ per second around the celestial pole; trails shorten by cos δ toward it. "
                     + "A full circle takes 23 h 56 min.")
            }
        }
        .navigationTitle("Star trails")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if cameraID.isEmpty { cameraID = store.defaultCamera.id } }
    }
}

/// Concentric arcs around the pole, each sweeping `degrees`.
private struct TrailSketch: View {
    let degrees: Double

    var body: some View {
        Canvas { context, size in
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 12), with: .color(.black))
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let sweep = Angle(degrees: min(degrees, 360))
            var generator = SystemRandomNumberGenerator()
            for index in 1...28 {
                let radius = CGFloat(index) * min(size.width, size.height) / 58
                let start = Angle(degrees: Double.random(in: 0..<360, using: &generator))
                var arc = Path()
                arc.addArc(center: center, radius: radius, startAngle: start, endAngle: start + sweep, clockwise: true)
                context.stroke(arc, with: .color(.white.opacity(0.4 + Double(index % 3) * 0.2)), lineWidth: 1.2)
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)), with: .color(.white))
        }
        .accessibilityHidden(true)
    }
}
