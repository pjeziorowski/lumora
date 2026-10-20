// App/Sources/Planner/PlannerToolsViews.swift
//
// Planner tool sheets (Phase 6): the target pin and obstacle height, field and depth of
// field on the map, and Find (Sun, Moon or Milky Way core at an azimuth and/or elevation
// over a date range). Results jump the Planner to the matching moment.

import CameraCatalog
import GeoCore
import OpticsCore
import PlannerKit
import SwiftUI

struct PlannerTargetSheet: View {
    @Environment(PlannerState.self) private var state
    @Environment(CameraStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.unitSystem) private var units: UnitSystem = .metric
    @AppStorage(PlannerOpticsKeys.camera) private var cameraID = ""

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            Form {
                Section {
                    if let target = state.target {
                        LabeledContent("Position", value: Formatting.coordinate(latitude: target.point.latitude,
                                                                                longitude: target.point.longitude, style: .decimal))
                        LabeledContent("Ground", value: target.groundElevation.map { Formatting.height(meters: $0, units: units) }
                                       ?? (state.resolvingTarget ? String(localized: "Looking up…") : String(localized: "Unknown")))
                        NumberRow(label: "Object height", value: Binding(get: { target.objectHeight },
                                                                         set: { state.setObjectHeight($0) }),
                                  unit: "m", step: 5, range: 0...2000)
                        Button("Remove target pin", role: .destructive) {
                            Task { await state.setTarget(nil) }
                        }
                    } else {
                        Button {
                            Task { await state.addTarget() }
                        } label: {
                            Label("Add target pin toward the Sun", systemImage: "scope")
                        }
                        .accessibilityIdentifier("planner.addTarget")
                    }
                    NumberRow(label: "Eye height", value: $state.eyeHeight, unit: "m", step: 0.1, range: 0...500, decimals: 1)
                } header: {
                    Text("Target pin")
                } footer: {
                    Text("Drag the black pin onto a ridge, building or landmark. Panels 6 and 7 show the distance, the angle "
                         + "to its top with curvature and refraction, and whether the Sun or Moon clears it.")
                }
                Section {
                    Toggle("Field of view", isOn: $state.mapOptics.showFieldOfView)
                        .accessibilityIdentifier("planner.optics.fov")
                    Toggle("Depth of field", isOn: $state.mapOptics.showDepthOfField)
                        .accessibilityIdentifier("planner.optics.dof")
                    CameraRow(cameraID: $cameraID)
                    NumberRow(label: "Focal length", value: $state.mapOptics.focalLength, unit: "mm", step: 1, range: 4...1200)
                    ScalePicker(label: "Aperture", value: $state.mapOptics.aperture, scale: Exposure.apertureScale,
                                format: OpticsFormat.aperture)
                    Picker("Orientation", selection: $state.mapOptics.orientation) {
                        Text("Landscape").tag(Orientation.landscape)
                        Text("Portrait").tag(Orientation.portrait)
                    }
                    if state.target != nil {
                        Toggle("Focus on the target", isOn: $state.mapOptics.focusOnTarget)
                    }
                    if state.target == nil || !state.mapOptics.focusOnTarget {
                        NumberRow(label: "Focus distance", value: $state.mapOptics.focusDistance, unit: "m", step: 1, range: 0.3...100_000)
                    }
                    if state.target == nil {
                        NumberRow(label: "Bearing", value: $state.mapOptics.bearing, unit: "°", step: 1, range: 0...359)
                    }
                } header: {
                    Text("On the map")
                } footer: {
                    Text("The wedge is the horizontal angle of view along the target's bearing; arcs mark the near limit, "
                         + "the focus distance and the far limit of acceptable sharpness.")
                }
            }
            .navigationTitle("Target and optics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { if cameraID.isEmpty { cameraID = store.defaultCamera.id } }
        }
    }
}

enum PlannerOpticsKeys {
    static let camera = "planner.optics.camera"
}

struct FindView: View {
    @Environment(PlannerState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.clockStyle) private var clock: ClockStyle = .twentyFourHour
    @State private var findBody: FindBody = .sun
    @State private var useAzimuth = true
    @State private var azimuth = 0.0
    @State private var azimuthTolerance = 0.5
    @State private var useElevation = true
    @State private var elevation = 0.5
    @State private var elevationTolerance = 0.5
    @State private var start = Date()
    @State private var days = 90.0
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var results: [FindMatch]?
    private static let resultsID = "find.results"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        Picker("Body", selection: $findBody) {
                            ForEach(FindBody.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("find.body")
                    }
                    Section {
                        Toggle("Azimuth", isOn: $useAzimuth)
                        if useAzimuth {
                            NumberRow(label: "Target", value: $azimuth, unit: "°", step: 0.1, range: 0...359.9, decimals: 1)
                            NumberRow(label: "Tolerance", value: $azimuthTolerance, unit: "±°", step: 0.1, range: 0.1...45, decimals: 1)
                            if let line = state.targetLine {
                                Button("Use the target's bearing (\(Formatting.azimuth(line.initialBearing)))") {
                                    azimuth = (line.initialBearing * 10).rounded() / 10
                                }
                            }
                        }
                        Toggle("Elevation", isOn: $useElevation)
                        if useElevation {
                            NumberRow(label: "Target", value: $elevation, unit: "°", step: 0.1, range: -18...90, decimals: 1)
                            NumberRow(label: "Tolerance", value: $elevationTolerance, unit: "±°", step: 0.1, range: 0.1...45, decimals: 1)
                            if let obstacle = state.obstacle {
                                Button("Use the angle to the target's top (\(Formatting.degrees(obstacle.geodetics.topAngle, decimals: 2)))") {
                                    elevation = (obstacle.geodetics.topAngle * 100).rounded() / 100
                                }
                            }
                        }
                    } header: {
                        Text("Position")
                    } footer: {
                        Text("Elevation is the apparent (refracted) height above the horizon; 0.5° puts the Sun's disc just on it.")
                    }
                    Section("Dates") {
                        DatePicker("From", selection: $start, displayedComponents: .date)
                            .environment(\.timeZone, state.session.timeZone)
                        NumberRow(label: "Days", value: $days, step: 30, range: 1...730)
                    }
                    Section {
                        Button {
                            search()
                        } label: {
                            HStack {
                                Text("Find")
                                if searching { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(searching || (!useAzimuth && !useElevation))
                        .accessibilityIdentifier("find.search")
                    }
                    if let results {
                        Section {
                            if results.isEmpty {
                                Text("No moments match. Widen a tolerance or the date range.").foregroundStyle(.secondary)
                            }
                            ForEach(results) { match in
                                Button {
                                    state.show(match)
                                    dismiss()
                                } label: {
                                    MatchRow(match: match, zone: state.session.timeZone, clock: clock)
                                }
                                .accessibilityIdentifier("find.result")
                            }
                        } header: {
                            Text("\(results.count) matches")
                        }
                        .id(Self.resultsID)
                    }
                }
                // Results appear below the form: bring them into view.
                .onChange(of: results?.count) { if results != nil { withAnimation { proxy.scrollTo(Self.resultsID, anchor: .top) } } }
            }
            .navigationTitle("Find")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onAppear(perform: prefill)
            .onDisappear { searchTask?.cancel() }
        }
    }

    /// Starts from the target's bearing when there is one, else the body's azimuth now.
    private func prefill() {
        start = state.session.day.start
        if let line = state.targetLine {
            azimuth = (line.initialBearing * 10).rounded() / 10
        } else if let sun = state.snapshot?.sun {
            azimuth = (sun.azimuth * 10).rounded() / 10
        }
    }

    private func search() {
        searching = true
        let query = FindQuery(body: findBody, azimuth: useAzimuth ? azimuth : nil, azimuthTolerance: azimuthTolerance,
                              elevation: useElevation ? elevation : nil, elevationTolerance: elevationTolerance,
                              start: start, end: start.addingTimeInterval(days * 86_400))
        searchTask?.cancel()
        searchTask = Task {
            let found = await state.find(query)
            guard !Task.isCancelled else { return }
            results = found
            searching = false
        }
    }
}

private struct MatchRow: View {
    let match: FindMatch
    let zone: TimeZone
    let clock: ClockStyle

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(match.time.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: zone)))
                    .foregroundStyle(.primary)
                Text(Formatting.clockTime(match.time, timeZone: zone, style: clock))
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("az \(Formatting.azimuth(match.azimuth, decimals: 2))").monospacedDigit()
                Text("el \(Formatting.degrees(match.elevation, decimals: 2))").monospacedDigit()
                if let moon = match.moonIllumination {
                    Text("Moon \(Int((moon * 100).rounded()))%").font(.caption).foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
