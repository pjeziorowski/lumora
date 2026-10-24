// App/Sources/Optics/TimeLapseView.swift
//
// Time-lapse planner: solve any one of event duration, interval, frame rate and clip
// length from the other three; photos, storage and batteries; warnings; presets.

import OpticsCore
import PlannerKit
import SwiftUI

struct TimeLapseView: View {
    @State private var solving: TimeLapse.Unknown = .clipLength
    @State private var plan = TimeLapsePlan(duration: 2 * 3600, interval: 5, fps: 25, clipLength: 0)
    @State private var shutter = 1.0
    @State private var fileSizeMB = 30.0
    @State private var shotsPerCharge = 500.0

    var body: some View {
        let solved = TimeLapse.solve(plan, for: solving)
        let warnings = TimeLapse.warnings(solved, shutter: shutter, shotsPerCharge: Int(shotsPerCharge))
        Form {
            Section {
                Picker("Solve for", selection: $solving) {
                    Text("Clip").tag(TimeLapse.Unknown.clipLength)
                    Text("Interval").tag(TimeLapse.Unknown.interval)
                    Text("Duration").tag(TimeLapse.Unknown.duration)
                    Text("FPS").tag(TimeLapse.Unknown.fps)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("timelapse.solve")
                if solving != .duration {
                    NumberRow(label: "Event duration", value: Binding(get: { plan.duration / 60 }, set: { plan.duration = $0 * 60 }),
                              unit: "min", step: 5, range: 1...10_000)
                }
                if solving != .interval {
                    NumberRow(label: "Interval", value: $plan.interval, unit: "s", step: 1, range: 0.5...3600, decimals: 1)
                }
                if solving != .fps {
                    Picker("Frame rate", selection: $plan.fps) {
                        ForEach([24.0, 25, 30, 50, 60], id: \.self) { Text("\(Int($0)) fps").tag($0) }
                    }
                }
                if solving != .clipLength {
                    NumberRow(label: "Clip length", value: $plan.clipLength, unit: "s", step: 1, range: 1...3600)
                }
            }
            Section {
                switch solving {
                case .clipLength: ResultRow(label: "Clip length", value: String(format: "%.1f s", solved.clipLength), emphasised: true)
                case .interval: ResultRow(label: "Interval", value: String(format: "%.1f s", solved.interval), emphasised: true)
                case .duration: ResultRow(label: "Event duration", value: Formatting.duration(seconds: solved.duration), emphasised: true)
                case .fps: ResultRow(label: "Frame rate", value: String(format: "%.1f fps", solved.fps), emphasised: true)
                }
                ResultRow(label: "Photos", value: "\(solved.photos)")
                ResultRow(label: "Speed-up", value: String(format: "%.0f×", solved.speedUp))
                ResultRow(label: "Storage", value: storage(TimeLapse.memoryMB(photos: solved.photos, fileSizeMB: fileSizeMB)))
                ResultRow(label: "Batteries", value: "\(TimeLapse.batteries(photos: solved.photos, shotsPerCharge: Int(shotsPerCharge)))")
                ForEach(warnings, id: \.self) { warning in
                    Label(text(warning), systemImage: "exclamationmark.triangle").foregroundStyle(.caution)
                }
            } header: {
                SectionLabel {
                    Text("Result")
                }
            }
            TitledSection("Camera") {
                NumberRow(label: "Shutter", value: $shutter, unit: "s", step: 0.5, range: 0.0001...600, decimals: 2)
                NumberRow(label: "File size", value: $fileSizeMB, unit: "MB", step: 5, range: 1...500)
                NumberRow(label: "Shots per battery", value: $shotsPerCharge, step: 50, range: 50...5000)
            }
            TitledSection("Presets") {
                ForEach(TimeLapse.presets) { preset in
                    Button {
                        plan.interval = preset.interval
                        if solving == .interval { solving = .clipLength }
                    } label: {
                        LabeledContent {
                            Text("\(Int(preset.interval)) s").monospacedDigit()
                        } label: {
                            VStack(alignment: .leading) {
                                Text(preset.name)
                                Text(preset.note).font(.caption).foregroundStyle(.subdued)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Time lapse")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func storage(_ mb: Double) -> String {
        mb >= 1000 ? String(format: "%.1f GB", mb / 1000) : String(format: "%.0f MB", mb)
    }

    private func text(_ warning: TimeLapse.Warning) -> String {
        switch warning {
        case .intervalTooShort: String(localized: "Interval shorter than the exposure plus write time")
        case .clipTooShort: String(localized: "Clip shorter than 2 seconds")
        case .needsBatterySwap: String(localized: "Needs a battery swap or external power")
        }
    }
}
