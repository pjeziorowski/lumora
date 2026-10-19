// App/Sources/Optics/ExposureView.swift
//
// Exposure tool: equivalent exposures (change one of aperture, shutter, ISO; solve
// another), ND filters with the long-exposure result, and a countdown timer for bulb
// exposures with a sound and haptic at the end.

import AudioToolbox
import OpticsCore
import SwiftUI

struct ExposureView: View {
    @State private var metered = ExposureSettings(aperture: 8, shutter: 1.0 / 125, iso: 100)
    @State private var target = ExposureSettings(aperture: 2.8, shutter: 1.0 / 125, iso: 100)
    @State private var solving: Exposure.Unknown = .shutter
    @State private var filterStops = 10.0
    @State private var timer = CountdownTimer()

    var body: some View {
        let result = Exposure.equivalent(to: metered, fixed: target, solving: solving)
        let longExposure = Exposure.withFilters(shutter: result.shutter, stops: filterStops)
        Form {
            Section {
                ScalePicker(label: "Aperture", value: $metered.aperture, scale: Exposure.apertureScale, format: OpticsFormat.aperture)
                ScalePicker(label: "Shutter", value: $metered.shutter, scale: Exposure.shutterScale, format: Exposure.shutterLabel)
                ScalePicker(label: "ISO", value: $metered.iso, scale: Exposure.isoScale, format: OpticsFormat.iso)
                ResultRow(label: "Exposure value", value: String(format: "EV %.1f", metered.ev100))
            } header: {
                Text("Metered exposure")
            }
            Section {
                Picker("Solve for", selection: $solving) {
                    Text("Shutter").tag(Exposure.Unknown.shutter)
                    Text("Aperture").tag(Exposure.Unknown.aperture)
                    Text("ISO").tag(Exposure.Unknown.iso)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("exposure.solve")
                if solving != .aperture {
                    ScalePicker(label: "Aperture", value: $target.aperture, scale: Exposure.apertureScale, format: OpticsFormat.aperture)
                }
                if solving != .shutter {
                    ScalePicker(label: "Shutter", value: $target.shutter, scale: Exposure.shutterScale, format: Exposure.shutterLabel)
                }
                if solving != .iso {
                    ScalePicker(label: "ISO", value: $target.iso, scale: Exposure.isoScale, format: OpticsFormat.iso)
                }
                ResultRow(label: "Equivalent", value: label(result, solving), emphasised: true)
            } header: {
                Text("Equivalent exposure")
            } footer: {
                Text("Exact value \(exact(result, solving)); nearest marked setting shown.")
            }
            Section {
                Picker("ND filter", selection: $filterStops) {
                    Text("None").tag(0.0)
                    ForEach(NDFilter.common) { Text($0.label).tag($0.stops) }
                }
                ResultRow(label: "With filter", value: Exposure.shutterLabel(longExposure), emphasised: true)
                TimerControls(timer: timer, duration: longExposure)
            } header: {
                Text("Long exposure")
            } footer: {
                Text("Shutter × 2^stops. Stops, brand factor (ND1000) and optical density (3.0) are shown for each filter.")
            }
        }
        .navigationTitle("Exposure")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { timer.stop() }
    }

    private func label(_ s: ExposureSettings, _ unknown: Exposure.Unknown) -> String {
        switch unknown {
        case .shutter: Exposure.shutterLabel(Exposure.nearest(s.shutter, on: Exposure.shutterScale))
        case .aperture: OpticsFormat.aperture(Exposure.nearest(s.aperture, on: Exposure.apertureScale))
        case .iso: OpticsFormat.iso(Exposure.nearest(s.iso, on: Exposure.isoScale))
        }
    }

    private func exact(_ s: ExposureSettings, _ unknown: Exposure.Unknown) -> String {
        switch unknown {
        case .shutter: s.shutter < 1 ? String(format: "1/%.0f s", 1 / s.shutter) : String(format: "%.2f s", s.shutter)
        case .aperture: String(format: "f/%.2f", s.aperture)
        case .iso: String(format: "ISO %.0f", s.iso)
        }
    }
}

/// Counts a bulb exposure down, then plays a sound and a haptic.
@MainActor
@Observable
final class CountdownTimer {
    private(set) var remaining: Double = 0
    private(set) var total: Double = 0
    private(set) var finishedCount = 0
    private var task: Task<Void, Never>?

    var isRunning: Bool { task != nil }

    func start(_ seconds: Double) {
        stop()
        total = seconds
        remaining = seconds
        let end = Date().addingTimeInterval(seconds)
        task = Task { [weak self] in
            while !Task.isCancelled {
                let left = end.timeIntervalSinceNow
                guard let self else { return }
                if left <= 0 {
                    self.remaining = 0
                    self.finishedCount += 1
                    self.task = nil
                    AudioServicesPlaySystemSound(1005)
                    return
                }
                self.remaining = left
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

private struct TimerControls: View {
    let timer: CountdownTimer
    let duration: Double

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: timer.total > 0 ? timer.remaining / timer.total : 0)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Exposure.shutterLabel(timer.isRunning ? timer.remaining : duration))
                    .font(.caption.monospacedDigit())
            }
            .frame(width: 64, height: 64)
            Button(timer.isRunning ? "Stop" : "Start timer") {
                if timer.isRunning { timer.stop() } else { timer.start(duration) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(duration < 1)
            .accessibilityIdentifier("exposure.timer")
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.success, trigger: timer.finishedCount)
    }
}
