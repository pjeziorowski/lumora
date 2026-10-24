// App/Sources/Optics/OpticsComponents.swift
//
// Inputs shared by the photography calculators: the camera row, numeric fields, scale
// pickers (apertures, shutter speeds, ISO), distances in the user's units, and a few
// formatters. Calculations come from OpticsCore; this file only lays out inputs.

import CameraCatalog
import OpticsCore
import PlannerKit
import SwiftUI

/// Selected camera row that opens the picker.
struct CameraRow: View {
    @Environment(CameraStore.self) private var store
    @Binding var cameraID: String

    var body: some View {
        let camera = store.camera(id: cameraID) ?? store.defaultCamera
        NavigationLink {
            CameraPickerView(selection: $cameraID)
        } label: {
            LabeledContent {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(camera.name).lineLimit(1)
                    Text("\(camera.formatName) · CoC \(String(format: "%.3f", camera.coc)) mm")
                        .font(.caption)
                        .foregroundStyle(.subdued)
                }
            } label: {
                Label("Camera", systemImage: "camera")
            }
        }
        .accessibilityIdentifier("optics.camera")
    }
}

/// A labelled number field with a unit and a stepper.
struct NumberRow: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    var unit: String = ""
    var step: Double = 1
    var range: ClosedRange<Double> = 0...1_000_000
    var decimals: Int = 0

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                TextField("", value: $value, format: .number.precision(.fractionLength(0...max(decimals, 2))))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 90)
                if !unit.isEmpty { Text(unit).foregroundStyle(.subdued) }
                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
            }
        } label: {
            Text(label)
        }
    }
}

/// Picks a value from a marked scale (apertures, shutter speeds, ISO).
struct ScalePicker: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    let scale: [Double]
    let format: (Double) -> String

    var body: some View {
        Picker(label, selection: Binding(
            get: { Exposure.nearest(value, on: scale) },
            set: { value = $0 }
        )) {
            ForEach(scale, id: \.self) { Text(format($0)).tag($0) }
        }
    }
}

enum OpticsFormat {
    static func aperture(_ n: Double) -> String {
        n == n.rounded() ? "f/\(Int(n))" : "f/\(String(format: "%.1f", n))"
    }

    static func iso(_ value: Double) -> String { "ISO \(Int(value.rounded()))" }

    /// Millimetres as metres/centimetres, or feet/inches.
    static func length(mm: Double, units: UnitSystem) -> String {
        if mm.isInfinite { return "∞" }
        switch units {
        case .metric:
            if mm < 1000 { return String(format: "%.1f cm", mm / 10) }
            return String(format: mm < 10_000 ? "%.2f m" : "%.1f m", mm / 1000)
        case .imperial:
            let inches = mm / 25.4
            if inches < 24 { return String(format: "%.1f in", inches) }
            return String(format: inches < 1200 ? "%.2f ft" : "%.0f ft", inches / 12)
        }
    }

    static func seconds(_ s: Double) -> String {
        s < 60 ? String(format: "%.1f s", s) : Exposure.shutterLabel(s)
    }
}

/// Distance input in metres or feet, stored in millimetres.
struct DistanceRow: View {
    let label: LocalizedStringKey
    @Binding var millimetres: Double
    let units: UnitSystem

    var body: some View {
        let factor = units == .metric ? 1000.0 : 304.8
        let range = 0.01...100_000.0
        NumberRow(label: label, value: Binding(
            get: { (millimetres / factor * 100).rounded() / 100 },
            set: { millimetres = min(max(range.lowerBound, $0), range.upperBound) * factor }
        ), unit: units == .metric ? "m" : "ft", step: units == .metric ? 0.5 : 1, range: range, decimals: 2)
    }
}

/// Result row with a highlighted value.
struct ResultRow: View {
    let label: LocalizedStringKey
    let value: String
    var emphasised = false

    var body: some View {
        LabeledContent {
            Text(value)
                .monospacedDigit()
                .fontWeight(emphasised ? .semibold : .regular)
                .foregroundStyle(emphasised ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        } label: {
            Text(label)
        }
        .accessibilityElement(children: .combine)
    }
}
