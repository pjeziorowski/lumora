// App/Sources/AR/ARSensors.swift
//
// Inputs for the AR views: device attitude from Core Motion (true north when available),
// the back camera's preview and its field of view. Without motion sensors (the simulator,
// or screenshot runs with `-arView <az>,<el>,<roll>`) the attitude is fixed and can be
// dragged, and a drawn sky stands in for the camera.

@preconcurrency import AVFoundation
@preconcurrency import CoreMotion
import PlannerKit
import SwiftUI

@MainActor
@Observable
final class ARMotion {
    enum Source: Equatable {
        case trueNorth, magneticNorth, fixed
    }

    private(set) var attitude: ARAttitude
    private(set) var source: Source = .fixed
    /// Simulated look direction, used and dragged when there are no sensors.
    var fixedAzimuth: Double
    var fixedElevation: Double
    var fixedRoll: Double

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private let forcedFixed: Bool

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        var az = 180.0, el = 10.0, roll = 0.0
        if let index = arguments.firstIndex(of: "-arView"), index + 1 < arguments.count {
            let parts = arguments[index + 1].split(separator: ",").compactMap { Double($0) }
            if parts.count >= 2 { az = parts[0]; el = parts[1] }
            if parts.count >= 3 { roll = parts[2] }
        }
        fixedAzimuth = az
        fixedElevation = el
        fixedRoll = roll
        forcedFixed = arguments.contains("-arView") || arguments.contains("-fixedDate")
        attitude = ARAttitude(azimuth: az, elevation: el, roll: roll)
    }

    var usesSensors: Bool { source != .fixed }

    func start() {
        guard !forcedFixed, manager.isDeviceMotionAvailable else { return }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical : .xMagneticNorthZVertical
        source = frame == .xTrueNorthZVertical ? .trueNorth : .magneticNorth
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] motion, _ in
            guard let m = motion?.attitude.rotationMatrix else { return }
            let attitude = ARAttitude.fromCoreMotion(m11: m.m11, m12: m.m12, m13: m.m13, m21: m.m21, m22: m.m22, m23: m.m23,
                                                     m31: m.m31, m32: m.m32, m33: m.m33)
            MainActor.assumeIsolated { self?.attitude = attitude }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    /// Pans the simulated view (degrees).
    func look(azimuth: Double, elevation: Double) {
        fixedAzimuth = ARAngles.wrap(azimuth)
        fixedElevation = max(-80, min(85, elevation))
        attitude = ARAttitude(azimuth: fixedAzimuth, elevation: fixedElevation, roll: fixedRoll)
    }
}

/// The back camera's live preview, filling its frame.
@MainActor
final class ARCamera {
    let session = AVCaptureSession()
    /// Horizontal field of view across the long side of the sensor, degrees.
    private(set) var fieldOfView: Double = 69.4
    private(set) var running = false

    func start() async -> Bool {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            || (await AVCaptureDevice.requestAccess(for: .video)) else { return false }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        fieldOfView = Double(device.activeFormat.videoFieldOfView)
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        let session = session
        await Task.detached { session.startRunning() }.value
        running = true
        return true
    }

    func stop() {
        let session = session
        Task.detached { session.stopRunning() }
        running = false
    }
}

struct ARCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer } // swiftlint:disable:this force_cast
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        guard let connection = view.previewLayer.connection else { return }
        let angle: CGFloat = switch view.window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: 180
        case .landscapeRight: 0
        case .portraitUpsideDown: 270
        default: 90
        }
        if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
    }
}

extension ARScreenOrientation {
    @MainActor
    static func current(in size: CGSize) -> ARScreenOrientation {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        switch scene?.interfaceOrientation {
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        case .portraitUpsideDown: return .portraitUpsideDown
        case .portrait: return .portrait
        default: return size.width > size.height ? .landscapeRight : .portrait
        }
    }
}
