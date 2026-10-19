// App/Sources/Optics/FieldOfViewView.swift
//
// Field of view tool: angles of view, frame size at the subject, magnification and 35 mm
// equivalent; the inverse mode solves the focal length or the distance for a frame width.

import CameraCatalog
import OpticsCore
import PlannerKit
import SwiftUI

struct FieldOfViewView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case forward, focalLength, distance
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .forward: "Field of view"
            case .focalLength: "Find focal"
            case .distance: "Find distance"
            }
        }
    }

    @Environment(CameraStore.self) private var store
    @AppStorage(SettingsKeys.unitSystem) private var units: UnitSystem = .metric
    @State private var mode: Mode = .forward
    @State private var cameraID = ""
    @State private var focalLength = 35.0
    @State private var distance = 10_000.0
    @State private var frameWidth = 5000.0
    @State private var orientation: Orientation = .landscape

    private var camera: Camera { store.camera(id: cameraID) ?? store.defaultCamera }

    var body: some View {
        let sensor = camera.sensor
        let focal: Double = mode == .focalLength
            ? FieldOfView.focalLength(forFrameWidth: frameWidth, distance: distance, sensor: sensor, orientation: orientation)
            : focalLength
        let dist: Double = mode == .distance
            ? FieldOfView.distance(forFrameWidth: frameWidth, focalLength: focalLength, sensor: sensor, orientation: orientation)
            : distance
        let r = FieldOfView.compute(sensor: sensor, focalLength: focal, distance: dist, orientation: orientation)
        Form {
            Section {
                Picker("Mode", selection: $mode) { ForEach(Mode.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("fov.mode")
                CameraRow(cameraID: $cameraID)
                Picker("Orientation", selection: $orientation) {
                    Text("Landscape").tag(Orientation.landscape)
                    Text("Portrait").tag(Orientation.portrait)
                }
                if mode != .focalLength {
                    NumberRow(label: "Focal length", value: $focalLength, unit: "mm", step: 1, range: 4...1200)
                }
                if mode != .distance {
                    DistanceRow(label: "Subject distance", millimetres: $distance, units: units)
                }
                if mode != .forward {
                    DistanceRow(label: "Frame width", millimetres: $frameWidth, units: units)
                }
            }
            Section {
                if mode == .focalLength {
                    ResultRow(label: "Focal length", value: String(format: "%.0f mm", focal), emphasised: true)
                }
                if mode == .distance {
                    ResultRow(label: "Distance", value: OpticsFormat.length(mm: dist, units: units), emphasised: true)
                }
                FrameDiagram(horizontal: r.horizontal, vertical: r.vertical)
                    .frame(height: 120)
                ResultRow(label: "Horizontal", value: Formatting.degrees(r.horizontal), emphasised: mode == .forward)
                ResultRow(label: "Vertical", value: Formatting.degrees(r.vertical))
                ResultRow(label: "Diagonal", value: Formatting.degrees(r.diagonal))
                ResultRow(label: "Frame at subject", value: "\(OpticsFormat.length(mm: r.frameWidth, units: units)) × "
                          + OpticsFormat.length(mm: r.frameHeight, units: units))
                ResultRow(label: "Magnification", value: r.magnification.isFinite ? String(format: "1:%.0f", 1 / r.magnification) : "—")
                ResultRow(label: "35 mm equivalent", value: String(format: "%.0f mm", r.equivalentFocalLength))
            } header: {
                Text("Result")
            } footer: {
                let crop = String(format: "%.2f", camera.cropFactor)
                Text("Thin-lens approximation focused at the subject; \(camera.formatName), crop \(crop)×.")
            }
        }
        .navigationTitle("Field of view")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if cameraID.isEmpty { cameraID = store.defaultCamera.id } }
    }
}

/// The frame as a wedge seen from above, with the angle written inside.
private struct FrameDiagram: View {
    let horizontal: Double
    let vertical: Double

    var body: some View {
        Canvas { context, size in
            let apex = CGPoint(x: size.width / 2, y: size.height - 6)
            let half = min(horizontal, 170) / 2 * .pi / 180
            let length = size.height - 12
            let dx = sin(half) * length, dy = cos(half) * length
            var wedge = Path()
            wedge.move(to: apex)
            wedge.addLine(to: CGPoint(x: apex.x - dx, y: apex.y - dy))
            wedge.addLine(to: CGPoint(x: apex.x + dx, y: apex.y - dy))
            wedge.closeSubpath()
            context.fill(wedge, with: .color(.accentColor.opacity(0.25)))
            context.stroke(wedge, with: .color(.accentColor), lineWidth: 1.5)
            context.draw(Text(String(format: "%.1f°", horizontal)).font(.headline), at: CGPoint(x: apex.x, y: apex.y - length * 0.45))
        }
        .accessibilityHidden(true)
    }
}
