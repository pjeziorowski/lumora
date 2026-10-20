// App/Sources/SettingsView.swift

import CameraCatalog
import PlannerKit
import SwiftUI

enum SettingsKeys {
    static let unitSystem = "settings.unitSystem"
    static let clockStyle = "settings.clockStyle"
    static let coordinateStyle = "settings.coordinateStyle"
}

struct SettingsView: View {
    @AppStorage(SettingsKeys.unitSystem) private var units: UnitSystem = .metric
    @AppStorage(SettingsKeys.clockStyle) private var clock: ClockStyle = .twentyFourHour
    @AppStorage(SettingsKeys.coordinateStyle) private var coordinates: CoordinateStyle = .decimal
    @Environment(CameraStore.self) private var cameras

    var body: some View {
        Form {
            Picker("Units", selection: $units) {
                Text("Metric").tag(UnitSystem.metric)
                Text("Imperial").tag(UnitSystem.imperial)
            }
            Picker("Clock", selection: $clock) {
                Text("24-hour").tag(ClockStyle.twentyFourHour)
                Text("12-hour").tag(ClockStyle.twelveHour)
            }
            Picker("Coordinates", selection: $coordinates) {
                Text("Decimal degrees").tag(CoordinateStyle.decimal)
                Text("Degrees, minutes, seconds").tag(CoordinateStyle.degreesMinutesSeconds)
            }
            Section("Camera") {
                NavigationLink {
                    CameraManagerView()
                        .navigationTitle("Default camera")
                } label: {
                    LabeledContent("Default camera", value: cameras.defaultCamera.name)
                }
                .accessibilityIdentifier("settings.camera")
            }
            Section("Widgets") {
                NavigationLink {
                    WidgetGalleryView()
                } label: {
                    Label("Widgets", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("settings.widgets")
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.shortVersion)
                Text("Astronomy calculations are ported from Astronomy Engine by Don Cross (MIT licence).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }
}
