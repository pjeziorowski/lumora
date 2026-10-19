// App/Sources/Optics/DepthOfFieldView.swift
//
// Depth of field tool: classic DoF with a diagram of the sharp zone, advanced mode with
// diffraction and a print-based circle of confusion, a DoF table (apertures × distances)
// and a hyperfocal table (focal lengths × apertures).

import CameraCatalog
import OpticsCore
import PlannerKit
import SwiftUI

struct DepthOfFieldView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case classic, advanced, table, hyperfocal
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .classic: "Classic"
            case .advanced: "Advanced"
            case .table: "Table"
            case .hyperfocal: "Hyperfocal"
            }
        }
    }

    @Environment(CameraStore.self) private var store
    @AppStorage(SettingsKeys.unitSystem) private var units: UnitSystem = .metric
    @State private var mode: Mode = .classic
    @State private var cameraID = ""
    @State private var focalLength = 24.0
    @State private var aperture = 8.0
    @State private var distance = 3000.0
    @State private var teleconverter = 1.0
    // Advanced
    @State private var printDiagonal = 325.3
    @State private var viewingDistance = 250.0
    @State private var acuity = 5.0

    private var camera: Camera { store.camera(id: cameraID) ?? store.defaultCamera }

    private var coc: Double {
        mode == .advanced
            ? DepthOfField.coc(sensorDiagonal: camera.sensor.diagonalMM, printDiagonal: printDiagonal,
                               viewingDistance: viewingDistance, acuity: acuity)
            : camera.coc
    }

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $mode) { ForEach(Mode.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("dof.mode")
                CameraRow(cameraID: $cameraID)
                NumberRow(label: "Focal length", value: $focalLength, unit: "mm", step: 1, range: 4...1200)
                if mode != .hyperfocal {
                    ScalePicker(label: "Aperture", value: $aperture, scale: Exposure.apertureScale, format: OpticsFormat.aperture)
                }
                if mode == .classic || mode == .advanced {
                    DistanceRow(label: "Subject distance", millimetres: $distance, units: units)
                    Picker("Teleconverter", selection: $teleconverter) {
                        Text("None").tag(1.0)
                        Text("1.4×").tag(1.4)
                        Text("2×").tag(2.0)
                    }
                }
            }
            switch mode {
            case .classic: classic
            case .advanced: advanced
            case .table: table
            case .hyperfocal: hyperfocalTable
            }
        }
        .navigationTitle("Depth of field")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if cameraID.isEmpty { cameraID = store.defaultCamera.id } }
    }

    private var input: DoFInput {
        DoFInput(focalLength: focalLength, aperture: aperture, distance: distance, coc: coc, teleconverter: teleconverter)
    }

    @ViewBuilder private var classic: some View {
        let r = DepthOfField.compute(input)
        results(r)
    }

    @ViewBuilder
    private func results(_ r: DoFResult) -> some View {
        Section {
            DoFDiagram(result: r, distance: distance)
                .frame(height: 70)
                .padding(.vertical, 6)
            ResultRow(label: "Near limit", value: OpticsFormat.length(mm: r.near, units: units))
            ResultRow(label: "Far limit", value: OpticsFormat.length(mm: r.far, units: units))
            ResultRow(label: "Depth of field", value: OpticsFormat.length(mm: r.total, units: units), emphasised: true)
            ResultRow(label: "In front / behind", value: "\(OpticsFormat.length(mm: r.inFront, units: units)) / "
                      + OpticsFormat.length(mm: r.behind, units: units))
            ResultRow(label: "Hyperfocal", value: OpticsFormat.length(mm: r.hyperfocal, units: units))
        } header: {
            Text("Sharp zone")
        } footer: {
            Text("Circle of confusion \(String(format: "%.4f", coc)) mm"
                 + (teleconverter > 1
                    ? ", effective \(Int(focalLength * teleconverter)) mm \(OpticsFormat.aperture(aperture * teleconverter))"
                    : "")
                 + ".")
        }
    }

    @ViewBuilder private var advanced: some View {
        Section {
            Picker("Print size", selection: $printDiagonal) {
                Text("10 × 15 cm (4 × 6 in)").tag(180.3)
                Text("20 × 25 cm (8 × 10 in)").tag(325.3)
                Text("A3 (29.7 × 42 cm)").tag(514.4)
                Text("A2 (42 × 59.4 cm)").tag(727.5)
                Text("60 × 90 cm").tag(1081.7)
            }
            NumberRow(label: "Viewing distance", value: Binding(get: { viewingDistance / 10 }, set: { viewingDistance = $0 * 10 }),
                      unit: "cm", step: 5, range: 10...1000)
            NumberRow(label: "Visual acuity", value: $acuity, unit: "lp/mm", step: 1, range: 1...15)
        } header: {
            Text("Viewing conditions")
        }
        let r = DepthOfField.compute(input)
        results(r)
        let pitch = camera.pixelPitchMicrons
        let airy = DepthOfField.airyDisc(aperture: aperture * teleconverter) * 1000
        Section {
            ResultRow(label: "Airy disc", value: String(format: "%.1f µm", airy))
            ResultRow(label: "Pixel pitch", value: String(format: "%.2f µm", pitch))
            ResultRow(label: "Diffraction visible from", value: OpticsFormat.aperture(
                Exposure.nearest(DepthOfField.diffractionLimitedAperture(pixelPitchMicrons: pitch), on: Exposure.apertureScale)))
            Label(DepthOfField.isDiffractionLimited(aperture: aperture * teleconverter, pixelPitchMicrons: pitch)
                  ? "Diffraction softens detail at this aperture" : "Not diffraction-limited",
                  systemImage: DepthOfField.isDiffractionLimited(aperture: aperture * teleconverter, pixelPitchMicrons: pitch)
                  ? "exclamationmark.triangle" : "checkmark.circle")
        } header: {
            Text("Diffraction")
        } footer: {
            Text("Airy disc 2.44 · λ · N with λ = 550 nm; limited when it exceeds 2 × the pixel pitch.")
        }
    }

    private var tableApertures: [Double] { [1.4, 2, 2.8, 4, 5.6, 8, 11, 16, 22] }
    private var tableDistances: [Double] {
        units == .metric ? [1000, 2000, 3000, 5000, 10_000] : [3, 6, 10, 15, 30].map { $0 * 304.8 }
    }

    @ViewBuilder private var table: some View {
        let rows = DepthOfField.table(focalLength: focalLength, coc: coc, apertures: tableApertures, distances: tableDistances)
        Section {
            Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    ForEach(tableDistances, id: \.self) { Text(OpticsFormat.length(mm: $0, units: units)).bold() }
                }
                .font(.caption2)
                ForEach(rows) { row in
                    GridRow {
                        Text(OpticsFormat.aperture(row.aperture)).bold()
                        ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(OpticsFormat.length(mm: cell.near, units: units))
                                Text(OpticsFormat.length(mm: cell.far, units: units)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.caption2.monospacedDigit())
                }
            }
            .accessibilityIdentifier("dof.table")
        } header: {
            Text("Near / far limits")
        } footer: {
            Text("Columns: focus distance. Rows: aperture. CoC \(String(format: "%.4f", coc)) mm.")
        }
    }

    @ViewBuilder private var hyperfocalTable: some View {
        let focals: [Double] = [14, 16, 20, 24, 28, 35, 50, 85]
        let apertures: [Double] = [2.8, 4, 5.6, 8, 11, 16]
        let table = DepthOfField.hyperfocalTable(focalLengths: focals, apertures: apertures, coc: coc)
        Section {
            Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    ForEach(apertures, id: \.self) { Text(OpticsFormat.aperture($0)).bold() }
                }
                ForEach(Array(focals.enumerated()), id: \.offset) { index, focal in
                    GridRow {
                        Text("\(Int(focal)) mm").bold()
                        ForEach(Array(table[index].enumerated()), id: \.offset) { _, h in
                            Text(OpticsFormat.length(mm: h, units: units))
                        }
                    }
                }
            }
            .font(.caption2.monospacedDigit())
            .accessibilityIdentifier("dof.hyperfocal")
        } header: {
            Text("Hyperfocal distance")
        } footer: {
            Text("Focus here and everything from half this distance to infinity is acceptably sharp.")
        }
    }
}

/// Camera at the left, the sharp zone shaded, the subject marked; the far end shows ∞.
private struct DoFDiagram: View {
    let result: DoFResult
    let distance: Double

    var body: some View {
        Canvas { context, size in
            let maxDistance = result.isFarInfinite ? max(distance * 2, result.near * 3) : result.far * 1.25
            func x(_ d: Double) -> CGFloat { 24 + CGFloat(min(d, maxDistance) / maxDistance) * (size.width - 40) }
            let mid = size.height / 2
            var axis = Path()
            axis.move(to: CGPoint(x: 24, y: mid))
            axis.addLine(to: CGPoint(x: size.width - 8, y: mid))
            context.stroke(axis, with: .color(.secondary), lineWidth: 1)
            let zone = CGRect(x: x(result.near), y: mid - 18, width: x(result.far) - x(result.near), height: 36)
            context.fill(Path(roundedRect: zone, cornerRadius: 6), with: .color(.accentColor.opacity(0.3)))
            let subject = CGRect(x: x(distance) - 2, y: mid - 24, width: 4, height: 48)
            context.fill(Path(subject), with: .color(.accentColor))
            context.draw(Text(Image(systemName: "camera.fill")), at: CGPoint(x: 10, y: mid))
            if result.isFarInfinite {
                context.draw(Text("∞").font(.headline), at: CGPoint(x: size.width - 12, y: mid - 14))
            }
        }
        .accessibilityHidden(true)
    }
}
