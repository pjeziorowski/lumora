// App/Sources/Planner/PlannerView.swift
//
// The Planner: information panels on top, the map with the observer pin and Sun/Moon
// overlays in the middle, the time bar and jump buttons below. Place search, map style,
// current location and the pin/device time toggle live in the toolbar.

import CameraCatalog
import GeoCore
import OpticsCore
import PlannerKit
import SwiftUI

struct PlannerView: View {
    @Environment(PlannerState.self) private var state
    @Environment(CameraStore.self) private var cameras
    @AppStorage(PlannerOpticsKeys.camera) private var opticsCameraID = ""
    @AppStorage(SettingsKeys.unitSystem) private var units: UnitSystem = .metric
    @AppStorage(SettingsKeys.clockStyle) private var clock: ClockStyle = .twentyFourHour
    @AppStorage(SettingsKeys.coordinateStyle) private var coordinates: CoordinateStyle = .decimal
    @State private var showingSearch = false
    @State private var locating = false
    @State private var locationError: String?
    @State private var showingTargetSheet = false
    @State private var showingFind = false

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            PlannerPanelsView(state: state, options: options)
                .frame(height: 236)
                .background(.bar)
            PlannerMapView(
                pin: state.session.location,
                snapshot: state.snapshot,
                style: state.mapStyle,
                layers: state.layers,
                target: state.target,
                optics: state.mapOptics.isVisible ? MapOpticsInput(settings: state.mapOptics, sensor: opticsCamera.sensor,
                                                                   coc: opticsCamera.coc) : nil,
                recenterToken: state.recenterToken,
                onPinMoved: { coordinate in
                    Task { await state.movePin(latitude: coordinate.latitude, longitude: coordinate.longitude) }
                },
                onTargetMoved: { coordinate in
                    Task { await state.setTarget(GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)) }
                }
            )
            .overlay(alignment: .topLeading) { mapBadges }
            .ignoresSafeArea(.keyboard)
            TimeBarView(state: state, zone: displayZone, clock: clock)
                .background(.bar)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSearch = true
                } label: {
                    Label("Search places", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("planner.search")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingFind = true
                } label: {
                    Label("Find", systemImage: "scope")
                }
                .accessibilityIdentifier("planner.find")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    useCurrentLocation()
                } label: {
                    if locating {
                        ProgressView()
                    } else {
                        Label("Current location", systemImage: "location")
                    }
                }
                .disabled(locating)
                Menu {
                    Picker("Map style", selection: $state.mapStyle) {
                        ForEach(PlannerMapStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    Button {
                        state.useDeviceTimeZone.toggle()
                    } label: {
                        Label(state.useDeviceTimeZone ? "Show pin time" : "Show device time",
                              systemImage: state.useDeviceTimeZone ? "mappin" : "iphone")
                    }
                    .accessibilityIdentifier("planner.timezoneToggle")
                    Button {
                        showingTargetSheet = true
                    } label: {
                        Label("Target pin and optics…", systemImage: "ruler")
                    }
                    .accessibilityIdentifier("planner.targetOptions")
                    Section("Layers") {
                        layerToggle("Sun", .sun, id: "sun")
                        layerToggle("Moon", .moon, id: "moon")
                        layerToggle("Milky Way", .milkyWay, id: "milkyWay")
                    }
                } label: {
                    Label("Map options", systemImage: "map")
                }
                .accessibilityIdentifier("planner.options")
            }
        }
        .sheet(isPresented: $showingSearch) {
            LocationPickerView { place in state.select(place) }
        }
        .sheet(isPresented: $showingTargetSheet) {
            PlannerTargetSheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingFind) {
            FindView()
        }
        .alert("Location unavailable", isPresented: Binding(get: { locationError != nil }, set: { if !$0 { locationError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(locationError ?? "")
        }
        .task { state.refresh() }
        .onChange(of: state.session.location) { state.refresh() }
        .onChange(of: state.session.instant) { state.refresh() }
    }

    private func layerToggle(_ title: LocalizedStringKey, _ layer: PlannerLayers, id: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { state.layers.contains(layer) },
            set: { on in if on { state.layers.insert(layer) } else { state.layers.remove(layer) } }
        ))
        .accessibilityIdentifier("planner.layer.\(id)")
    }

    private var options: PlannerDisplayOptions {
        PlannerDisplayOptions(clock: clock, units: units, coordinates: coordinates,
                              useDeviceTimeZone: state.useDeviceTimeZone, deviceTimeZone: .current)
    }

    private var opticsCamera: Camera { cameras.camera(id: opticsCameraID) ?? cameras.defaultCamera }

    private var displayZone: TimeZone { state.useDeviceTimeZone ? .current : state.session.timeZone }

    @ViewBuilder private var mapBadges: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let light = state.snapshot?.lightPhase {
                Label(light.label, systemImage: "circle.fill")
                    .labelStyle(BadgeLabelStyle(tint: light.color))
            }
            if state.useDeviceTimeZone {
                Label("Device time", systemImage: "iphone")
                    .labelStyle(BadgeLabelStyle(tint: .secondary))
            }
            if state.mapOptics.isVisible {
                Label(opticsSummary, systemImage: "camera.viewfinder")
                    .labelStyle(BadgeLabelStyle(tint: .blue))
            }
            if state.resolvingPin {
                Label("Finding time zone…", systemImage: "globe")
                    .labelStyle(BadgeLabelStyle(tint: .secondary))
            }
        }
        .font(.caption.weight(.medium))
        .padding(8)
    }

    /// "50 mm f/8 · 39.6° · sharp 10.4 m – ∞"
    private var opticsSummary: String {
        let o = state.mapOptics
        let line = state.targetLine
        let g = MapOpticsGeometry.compute(o, sensor: opticsCamera.sensor, coc: opticsCamera.coc, targetDistance: line?.distance,
                                          targetBearing: line?.initialBearing, radius: 0)
        let far = g.far.map { Formatting.distance(meters: $0, units: units) } ?? "∞"
        return "\(Int(o.focalLength)) mm \(OpticsFormat.aperture(o.aperture)) · \(Formatting.degrees(g.horizontalAngle)) · "
            + "\(Formatting.distance(meters: g.near, units: units)) – \(far)"
    }

    private func useCurrentLocation() {
        locating = true
        Task {
            defer { locating = false }
            do {
                state.select(try await PlaceSearch.currentLocation())
            } catch {
                locationError = error.localizedDescription
            }
        }
    }
}

private struct BadgeLabelStyle<Tint: ShapeStyle>: LabelStyle {
    let tint: Tint

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
                .foregroundStyle(tint)
                .imageScale(.small)
            configuration.title
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
    }
}
