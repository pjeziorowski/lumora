// Packages/PlannerKit/Sources/PlannerKit/SkyPath.swift
//
// Elevation/azimuth samples of the Sun or Moon across a local day, for the Sun pill's
// elevation graph and the Moon pill's path graph.

import AstroCore
import Foundation

public struct SkySample: Sendable, Hashable, Identifiable {
    public let time: Date
    public let azimuth: Double
    /// Refracted elevation in degrees.
    public let altitude: Double
    public var id: Date { time }
}

public struct SkyPath: Sendable, Hashable {
    public let body: Body
    public let samples: [SkySample]

    public var highest: SkySample? { samples.max { $0.altitude < $1.altitude } }
    public var lowest: SkySample? { samples.min { $0.altitude < $1.altitude } }

    /// Samples every `stepMinutes` from local midnight to the next, both ends included.
    /// A 23 h or 25 h DST day simply has fewer or more samples.
    public static func compute(_ body: Body, location: PillLocation, day: LocalDay, stepMinutes: Int = 5) -> SkyPath {
        let observer = location.observer
        let step = TimeInterval(max(1, stepMinutes) * 60)
        var samples: [SkySample] = []
        var t = day.start
        while t <= day.end {
            let h = Ephemeris.horizontal(body, at: AstroTime(t), observer: observer)
            samples.append(SkySample(time: t, azimuth: h.azimuth, altitude: h.altitude))
            t = t.addingTimeInterval(step)
        }
        return SkyPath(body: body, samples: samples)
    }
}
