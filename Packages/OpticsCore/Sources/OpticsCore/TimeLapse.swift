// Packages/OpticsCore/Sources/OpticsCore/TimeLapse.swift
//
// Time-lapse planning (brief §2.12, §3.2): photos = duration / interval, clip = photos / fps,
// memory = photos × file size. Any one of event duration, clip length, frame rate and
// interval can be solved from the other three.

import Foundation

public struct TimeLapsePlan: Sendable, Hashable, Codable {
    /// Seconds of real time shot.
    public var duration: Double
    /// Seconds between frames.
    public var interval: Double
    public var fps: Double
    /// Clip length in seconds.
    public var clipLength: Double

    public init(duration: Double, interval: Double, fps: Double, clipLength: Double) {
        self.duration = duration
        self.interval = interval
        self.fps = fps
        self.clipLength = clipLength
    }

    public var photos: Int { Int((duration / interval).rounded(.down)) + 1 }
    public var speedUp: Double { interval * fps }
}

public enum TimeLapse {
    public enum Unknown: String, Sendable, CaseIterable { case duration, interval, fps, clipLength }

    /// Solves `unknown` from the other three fields of `plan`.
    public static func solve(_ plan: TimeLapsePlan, for unknown: Unknown) -> TimeLapsePlan {
        var p = plan
        switch unknown {
        case .duration: p.duration = p.clipLength * p.fps * p.interval
        case .interval: p.interval = p.duration / (p.clipLength * p.fps)
        case .fps: p.fps = p.duration / (p.interval * p.clipLength)
        case .clipLength: p.clipLength = p.duration / p.interval / p.fps
        }
        return p
    }

    /// Storage in megabytes for `photos` frames of `fileSizeMB` each.
    public static func memoryMB(photos: Int, fileSizeMB: Double) -> Double {
        Double(photos) * fileSizeMB
    }

    /// Batteries needed, given shots per charge (CIPA rating or the user's own figure).
    public static func batteries(photos: Int, shotsPerCharge: Int) -> Int {
        shotsPerCharge > 0 ? Int((Double(photos) / Double(shotsPerCharge)).rounded(.up)) : 0
    }

    public enum Warning: String, Sendable, Hashable {
        /// The interval is shorter than the exposure plus the time the camera needs to save.
        case intervalTooShort
        /// Fewer than 2 seconds of clip.
        case clipTooShort
        /// The shoot runs longer than one battery lasts.
        case needsBatterySwap
    }

    public static func warnings(_ plan: TimeLapsePlan, shutter: Double, writeTime: Double = 0.5,
                                shotsPerCharge: Int = 0) -> [Warning] {
        var list: [Warning] = []
        if plan.interval < shutter + writeTime { list.append(.intervalTooShort) }
        if plan.clipLength < 2 { list.append(.clipTooShort) }
        if shotsPerCharge > 0 && plan.photos > shotsPerCharge { list.append(.needsBatterySwap) }
        return list
    }

    public struct Preset: Sendable, Hashable, Identifiable {
        public let name: String
        public let interval: Double
        public let note: String
        public var id: String { name }
    }

    /// Typical intervals (widely used starting points, not rules).
    public static let presets: [Preset] = [
        Preset(name: "Fast clouds", interval: 1, note: "Wind-driven clouds, crowds"),
        Preset(name: "Slow clouds", interval: 4, note: "Fair-weather cumulus"),
        Preset(name: "Traffic", interval: 1, note: "Cars and city lights"),
        Preset(name: "Sunset", interval: 3, note: "Changing light, use a holy-grail ramp"),
        Preset(name: "Stars", interval: 25, note: "Night sky, exposure of 20 s or so"),
        Preset(name: "Construction", interval: 300, note: "Building sites, plants growing"),
    ]
}
