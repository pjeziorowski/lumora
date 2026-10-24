// App/Sources/AR/SkyARView.swift
//
// The AR viewer: the camera preview (or a drawn sky without one) with the Sun and Moon
// paths, the Milky Way, the night sky's poles and circles, or the selected lens's frame and
// depth of field drawn over it. Time can be scrubbed; compass and horizon are calibrated
// with sliders or by centring a known object. Geometry comes from PlannerKit's ARProjector
// and ARSky.

import CameraCatalog
import OpticsCore
import PlannerKit
import SwiftUI

enum ARKeys {
    static let heading = "ar.calibration.heading"
    static let pitch = "ar.calibration.pitch"
}

extension ARMode {
    var title: LocalizedStringKey {
        switch self {
        case .sunMoon: "Sun & Moon"
        case .milkyWay: "Milky Way"
        case .night: "Night"
        case .frame: "Frame"
        }
    }
}

struct SkyARView: View {
    @Environment(PillSession.self) private var session
    @Environment(CameraStore.self) private var cameras
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.clockStyle) private var clock: ClockStyle = .twentyFourHour
    @AppStorage(SettingsKeys.unitSystem) private var units: UnitSystem = .metric
    @AppStorage(ARKeys.heading) private var heading = 0.0
    @AppStorage(ARKeys.pitch) private var pitch = 0.0
    @State private var mode: ARMode
    @State private var motion = ARMotion()
    @State private var camera = ARCamera()
    @State private var cameraLive = false
    @State private var offsetMinutes = 0.0
    @State private var sky: ARSky?
    @State private var showingCalibration = false
    @State private var dragStart: (azimuth: Double, elevation: Double)?
    // Frame mode
    @State private var focalLength = 50.0
    @State private var aperture = 8.0
    @State private var focusMetres = 5.0
    let showsClose: Bool

    init(mode: ARMode = .sunMoon, showsClose: Bool = false) {
        _mode = State(initialValue: mode)
        self.showsClose = showsClose
    }

    private var instant: Date { session.instant.addingTimeInterval(offsetMinutes * 60) }
    private var calibration: ARCalibration { ARCalibration(heading: heading, pitch: pitch) }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let projector = makeProjector(size: size)
            ZStack {
                if cameraLive {
                    ARCameraPreview(session: camera.session)
                } else {
                    SimulatedSky(projector: projector, sunElevation: sky?.sunElevation ?? 30)
                }
                if let sky {
                    AROverlay(projector: projector, sky: sky, frame: mode == .frame ? lensFrame(projector.orientation) : nil)
                        .allowsHitTesting(false)
                }
                Crosshair()
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(motion.usesSensors ? nil : lookAround(projector: projector))
            .overlay(alignment: .top) { topBar(projector: projector) }
            .overlay(alignment: .bottom) { bottomBar }
        }
        .ignoresSafeArea(edges: .horizontal)
        .background(.black)
        .navigationTitle("AR")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsClose {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCalibration = true
                } label: {
                    Label("Calibrate", systemImage: "scope")
                }
                .accessibilityIdentifier("ar.calibrate")
            }
        }
        .sheet(isPresented: $showingCalibration) {
            ARCalibrationSheet(heading: $heading, pitch: $pitch, mode: mode, motion: motion, sky: sky)
                .presentationDetents([.medium])
        }
        .task(id: SkyKey(location: session.location, instant: instant, mode: mode, clock: clock, focus: focusLines)) {
            let key = SkyKey(location: session.location, instant: instant, mode: mode, clock: clock, focus: focusLines)
            let next = await Task.detached(priority: .userInitiated) {
                ARSky.compute(location: key.location, instant: key.instant, mode: key.mode, clock: key.clock, focus: key.focus)
            }.value
            // A newer key restarted this task: keep the newer sky.
            guard !Task.isCancelled else { return }
            sky = next
        }
        .task {
            motion.start()
            if motion.usesSensors { cameraLive = await camera.start() }
        }
        .onDisappear {
            motion.stop()
            camera.stop()
        }
    }

    // MARK: Projection

    private func makeProjector(size: CGSize) -> ARProjector {
        let w = Double(size.width), h = Double(size.height)
        let orientation: ARScreenOrientation = motion.usesSensors ? .current(in: size) : .portrait
        let focal = ARLens.focalPoints(cameraFieldOfView: cameraLive ? camera.fieldOfView : 69.4, width: w, height: h)
        return ARProjector(attitude: motion.attitude, orientation: orientation, calibration: calibration,
                           focal: focal, width: w, height: h)
    }

    private func lookAround(projector: ARProjector) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = dragStart ?? (motion.fixedAzimuth, motion.fixedElevation)
                if dragStart == nil { dragStart = start }
                let degreesPerPoint = projector.horizontalFieldOfView / projector.width
                motion.look(azimuth: start.azimuth - Double(value.translation.width) * degreesPerPoint,
                            elevation: start.elevation + Double(value.translation.height) * degreesPerPoint)
            }
            .onEnded { _ in dragStart = nil }
    }

    // MARK: Frame mode

    private var lensCamera: Camera { cameras.defaultCamera }

    private var focusLines: ARFocusLines? {
        guard mode == .frame else { return nil }
        let r = DepthOfField.compute(DoFInput(focalLength: focalLength, aperture: aperture, distance: focusMetres * 1000,
                                              coc: lensCamera.coc))
        return ARFocusLines(near: r.near / 1000, focus: focusMetres, far: r.isFarInfinite ? nil : r.far / 1000)
    }

    /// The selected lens held the way the phone is held (landscape screen, landscape frame).
    private func lensFrame(_ screen: ARScreenOrientation) -> LensFrame {
        let fov = FieldOfView.compute(sensor: lensCamera.sensor, focalLength: focalLength, distance: focusMetres * 1000,
                                      orientation: screen.sensorOrientation)
        return LensFrame(horizontal: fov.horizontal, vertical: fov.vertical,
                         label: "\(lensCamera.name) · \(Int(focalLength)) mm")
    }

    // MARK: Bars

    private func topBar(projector: ARProjector) -> some View {
        VStack(spacing: 8) {
            Picker("Mode", selection: $mode) {
                ForEach(ARMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("ar.mode")
            HStack {
                Text("Az \(Formatting.azimuth(projector.viewAzimuth)) · El \(Formatting.degrees(projector.viewElevation))")
                    .monospacedDigit()
                Spacer()
                Text(sourceLabel)
            }
            .font(.caption)
            .foregroundStyle(.white)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ar.heading")
        }
        .padding(10)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        // Controls sit on the camera image, so they always use dark-mode colours.
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var sourceLabel: LocalizedStringKey {
        switch motion.source {
        case .trueNorth: heading == 0 && pitch == 0 ? "True north" : "Calibrated"
        case .magneticNorth: "Magnetic north"
        case .fixed: "Preview · drag to look"
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            if mode == .frame {
                HStack {
                    Stepper("\(Int(focalLength)) mm", value: $focalLength, in: 8...800, step: focalLength < 50 ? 1 : 5)
                        .accessibilityIdentifier("ar.focal")
                    Stepper(OpticsFormat.aperture(aperture), value: $aperture, in: 1.4...22, step: 1)
                }
                Stepper("Focus \(OpticsFormat.length(mm: focusMetres * 1000, units: units))", value: $focusMetres,
                        in: 0.5...100, step: focusMetres < 10 ? 0.5 : 5)
                if let focus = focusLines {
                    Text("Sharp from \(OpticsFormat.length(mm: focus.near * 1000, units: units)) to "
                         + (focus.far.map { OpticsFormat.length(mm: $0 * 1000, units: units) } ?? "∞"))
                        .font(.caption)
                }
            } else {
                HStack {
                    let zone = session.timeZone
                    Text(instant.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: zone)) + " "
                         + Formatting.clockTime(instant, timeZone: zone, style: clock))
                        .monospacedDigit()
                        .accessibilityIdentifier("ar.time")
                    Spacer()
                    if offsetMinutes != 0 {
                        Button("Reset") { offsetMinutes = 0 }
                    }
                }
                Slider(value: $offsetMinutes, in: -720...720, step: 5) { Text("Time") }
                    .accessibilityIdentifier("ar.timeSlider")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .tint(.orange)
        .padding(12)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

private struct SkyKey: Equatable, Sendable {
    let location: PillLocation
    let instant: Date
    let mode: ARMode
    let clock: ClockStyle
    let focus: ARFocusLines?
}

struct LensFrame: Equatable {
    let horizontal: Double
    let vertical: Double
    let label: String
}

// MARK: - Drawing

private struct AROverlay: View {
    let projector: ARProjector
    let sky: ARSky
    let frame: LensFrame?

    var body: some View {
        Canvas { context, _ in
            for line in sky.lines {
                let style = Self.style(line.kind)
                for run in projector.polylines(line.points) {
                    var path = Path()
                    path.addLines(run.map { CGPoint(x: $0.x, y: $0.y) })
                    context.stroke(path, with: .color(style.color), style: style.stroke)
                }
                if let label = line.label, line.kind == .elevationGrid || line.kind == .starTrail,
                   let p = labelPoint(line.points) {
                    context.draw(Text(label).font(.caption2).foregroundStyle(style.color), at: p)
                }
            }
            for marker in sky.markers {
                guard let p = projector.project(marker.direction), projector.isOnScreen(p, margin: 20) else { continue }
                draw(marker, at: CGPoint(x: p.x, y: p.y), in: &context)
            }
            if let frame { drawFrame(frame, in: &context) }
        }
    }

    /// Where a line crosses the left part of the screen, for its label.
    private func labelPoint(_ points: [ARVector]) -> CGPoint? {
        for v in points {
            if let p = projector.project(v), p.x > 30, p.x < 90, p.y > 120, p.y < projector.height - 140 {
                return CGPoint(x: p.x, y: p.y - 8)
            }
        }
        return nil
    }

    private func draw(_ marker: ARMarker, at p: CGPoint, in context: inout GraphicsContext) {
        func dot(_ radius: CGFloat, _ color: Color, stroke: Color? = nil) {
            let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color))
            if let stroke { context.stroke(Path(ellipseIn: rect), with: .color(stroke), lineWidth: 1.5) }
        }
        func label(_ text: String, dy: CGFloat, font: Font = .caption2, color: Color = .white) {
            // Slide labels in from the screen edges so they are never cut off.
            let resolved = context.resolve(Text(text).font(font).foregroundStyle(color))
            let half = resolved.measure(in: CGSize(width: 400, height: 100)).width / 2 + 4
            let bounds = context.clipBoundingRect
            let x = min(max(p.x, bounds.minX + half), max(bounds.minX + half, bounds.maxX - half))
            context.draw(resolved, at: CGPoint(x: x, y: p.y + dy))
        }
        switch marker.kind {
        case .sun:
            dot(14, .yellow, stroke: .orange)
            label(marker.label, dy: -26, font: .caption.bold(), color: .yellow)
        case .moon:
            dot(12, Color(white: 0.92), stroke: .gray)
            label(marker.label, dy: -24, font: .caption.bold())
        case .sunHour:
            dot(3.5, .orange)
            label(marker.label, dy: 11, color: .orange)
        case .moonHour:
            dot(3, Color(red: 0.6, green: 0.75, blue: 1))
            label(marker.label, dy: 11, color: Color(red: 0.6, green: 0.75, blue: 1))
        case .galacticCenter:
            dot(9, .purple.opacity(0.9), stroke: .white)
            label(marker.label, dy: -20, font: .caption.bold(), color: Color(red: 0.85, green: 0.7, blue: 1))
        case .coreHour:
            dot(3, .purple)
            label(marker.label, dy: 11, color: Color(red: 0.85, green: 0.7, blue: 1))
        case .polaris:
            dot(4, .white)
            label(marker.label, dy: -14)
        case .celestialPole:
            var cross = Path()
            cross.move(to: CGPoint(x: p.x - 8, y: p.y)); cross.addLine(to: CGPoint(x: p.x + 8, y: p.y))
            cross.move(to: CGPoint(x: p.x, y: p.y - 8)); cross.addLine(to: CGPoint(x: p.x, y: p.y + 8))
            context.stroke(cross, with: .color(.cyan), lineWidth: 1.5)
            label(marker.label, dy: 16, color: .cyan)
        case .cardinal:
            label(marker.label, dy: -12, font: .headline, color: .green)
        case .gridLabel:
            label(marker.label, dy: 0)
        }
    }

    private func drawFrame(_ frame: LensFrame, in context: inout GraphicsContext) {
        let r = projector.lensFrame(horizontalFieldOfView: frame.horizontal, verticalFieldOfView: frame.vertical)
        let rect = CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
        // Darken what the lens will not see.
        var outside = Path(CGRect(x: 0, y: 0, width: projector.width, height: projector.height))
        outside.addRect(rect)
        context.fill(outside, with: .color(.black.opacity(0.35)), style: FillStyle(eoFill: true))
        context.stroke(Path(rect), with: .color(.white), lineWidth: 2)
        // Rule-of-thirds guides.
        var thirds = Path()
        for i in 1...2 {
            let x = rect.minX + rect.width * CGFloat(i) / 3, y = rect.minY + rect.height * CGFloat(i) / 3
            thirds.move(to: CGPoint(x: x, y: rect.minY)); thirds.addLine(to: CGPoint(x: x, y: rect.maxY))
            thirds.move(to: CGPoint(x: rect.minX, y: y)); thirds.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        context.stroke(thirds, with: .color(.white.opacity(0.35)), lineWidth: 0.75)
        let top = max(rect.minY, 110) + 12
        context.draw(Text(frame.label).font(.caption.bold()).foregroundStyle(.white),
                     at: CGPoint(x: projector.width / 2, y: top))
        if rect.width > projector.width {
            context.draw(Text("Wider than the phone's camera").font(.caption).foregroundStyle(.yellow),
                         at: CGPoint(x: projector.width / 2, y: top + 18))
        }
    }

    struct LineStyle {
        let color: Color
        let stroke: StrokeStyle
    }

    static func style(_ kind: ARLineKind) -> LineStyle {
        switch kind {
        case .horizon: LineStyle(color: .green, stroke: StrokeStyle(lineWidth: 2))
        case .azimuthGrid, .elevationGrid: LineStyle(color: .white.opacity(0.22), stroke: StrokeStyle(lineWidth: 0.75))
        case .sunPath: LineStyle(color: .orange, stroke: StrokeStyle(lineWidth: 3, lineCap: .round))
        case .moonPath: LineStyle(color: Color(red: 0.6, green: 0.75, blue: 1), stroke: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        case .galacticPlane: LineStyle(color: .purple.opacity(0.8), stroke: StrokeStyle(lineWidth: 6, lineCap: .round))
        case .corePath: LineStyle(color: Color(red: 0.85, green: 0.7, blue: 1), stroke: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        case .celestialEquator: LineStyle(color: .cyan, stroke: StrokeStyle(lineWidth: 1.5, dash: [8, 5]))
        case .starTrail: LineStyle(color: .white.opacity(0.55), stroke: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        case .focusNear: LineStyle(color: .red, stroke: StrokeStyle(lineWidth: 2))
        case .focus: LineStyle(color: .white, stroke: StrokeStyle(lineWidth: 2.5))
        case .focusFar: LineStyle(color: .blue, stroke: StrokeStyle(lineWidth: 2))
        }
    }
}

/// Stand-in for the camera: a sky coloured by the Sun's elevation above a dark ground.
private struct SimulatedSky: View {
    let projector: ARProjector
    let sunElevation: Double

    private var colors: (top: Color, bottom: Color) {
        switch sunElevation {
        case 6...: (Color(red: 0.25, green: 0.5, blue: 0.9), Color(red: 0.65, green: 0.8, blue: 0.95))
        case 0..<6: (Color(red: 0.3, green: 0.4, blue: 0.7), Color(red: 0.98, green: 0.7, blue: 0.4))
        case -6..<0: (Color(red: 0.12, green: 0.18, blue: 0.4), Color(red: 0.85, green: 0.5, blue: 0.45))
        case -12 ..< -6: (Color(red: 0.04, green: 0.07, blue: 0.2), Color(red: 0.15, green: 0.22, blue: 0.45))
        default: (Color(red: 0.01, green: 0.02, blue: 0.06), Color(red: 0.04, green: 0.06, blue: 0.14))
        }
    }

    var body: some View {
        Canvas { context, size in
            let c = colors
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [c.top, c.bottom]), startPoint: .zero,
                                               endPoint: CGPoint(x: 0, y: size.height)))
            // Ground: quads from the horizon down, in 10° steps, wherever they are in front.
            let ground = Color(red: 0.07, green: 0.09, blue: 0.07)
            for az in stride(from: 0.0, to: 360, by: 10) {
                for el in stride(from: 0.0, to: 80, by: 10) {
                    let corners = [(az, -el), (az + 10, -el), (az + 10, -el - 10), (az, -el - 10)]
                        .compactMap { projector.project(azimuth: $0.0, elevation: $0.1) }
                    guard corners.count == 4 else { continue }
                    var quad = Path()
                    quad.addLines(corners.map { CGPoint(x: $0.x, y: $0.y) })
                    quad.closeSubpath()
                    context.fill(quad, with: .color(ground))
                    context.stroke(quad, with: .color(ground), lineWidth: 1)
                }
            }
        }
    }
}

private struct Crosshair: View {
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.8), lineWidth: 1.5).frame(width: 22, height: 22)
            Rectangle().fill(.white.opacity(0.8)).frame(width: 1.5, height: 10)
            Rectangle().fill(.white.opacity(0.8)).frame(width: 10, height: 1.5)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Calibration

struct ARCalibrationSheet: View {
    @Binding var heading: Double
    @Binding var pitch: Double
    let mode: ARMode
    let motion: ARMotion
    let sky: ARSky?
    @Environment(\.dismiss) private var dismiss

    /// The object to centre for one-tap calibration in this mode.
    private var reference: ARMarker? {
        let kinds: [ARMarkerKind] = switch mode {
        case .sunMoon, .frame: [.sun, .moon]
        case .milkyWay: [.galacticCenter]
        case .night: [.polaris, .galacticCenter]
        }
        return kinds.lazy.compactMap { kind in self.sky?.markers.first { $0.kind == kind && $0.direction.elevation > -1 } }.first
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Compass", value: String(format: "%+.1f°", heading))
                    Slider(value: $heading, in: -180...180, step: 0.1) { Text("Compass") }
                        .accessibilityIdentifier("ar.calibration.heading")
                    LabeledContent("Horizon", value: String(format: "%+.1f°", pitch))
                    Slider(value: $pitch, in: -30...30, step: 0.1) { Text("Horizon") }
                } footer: {
                    SectionLabel {
                        Text("Compass turns the overlay left or right; horizon raises or lowers it. "
                             + "Line up the green horizon or a known object.")
                    }
                }
                if let reference {
                    Section {
                        Button("Align on \(reference.label)") { align(on: reference) }
                            .accessibilityIdentifier("ar.calibration.align")
                    } footer: {
                        SectionLabel {
                            Text("Put \(reference.label) in the centre circle, then tap.")
                        }
                    }
                }
                Section {
                    Button("Reset", role: .destructive) {
                        heading = 0
                        pitch = 0
                    }
                }
            }
            .navigationTitle("Calibrate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func align(on marker: ARMarker) {
        // The raw view direction, before any calibration.
        let raw = ARProjector(attitude: motion.attitude, focal: 1000, width: 400, height: 800)
        let next = ARCalibration.none.aligning(view: (raw.viewAzimuth, raw.viewElevation),
                                               to: (marker.direction.azimuth, marker.direction.elevation))
        heading = (next.heading * 10).rounded() / 10
        pitch = (next.pitch * 10).rounded() / 10
        dismiss()
    }
}
