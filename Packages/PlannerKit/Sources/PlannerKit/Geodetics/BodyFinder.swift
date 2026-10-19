// Packages/PlannerKit/Sources/PlannerKit/Geodetics/BodyFinder.swift
//
// Find: moments in a date range when the Sun, the Moon or the galactic core stands at a
// target azimuth and/or elevation, within tolerances. Used for alignments such as the Sun
// setting down a street, or the Moon rising behind a landmark seen from the observer pin.
//
// Method: the body is sampled every 5 minutes; crossings of the target azimuth (and of the
// target elevation) are bracketed and refined by bisection to under a second. A crossing
// is a match when the other coordinate is within its tolerance. Matches closer than an hour
// are merged, keeping the one with the smallest normalised error.

import AstroCore
import Foundation

public enum FindBody: String, Sendable, Hashable, CaseIterable, Codable, Identifiable {
    case sun, moon, galacticCenter
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sun: "Sun"
        case .moon: "Moon"
        case .galacticCenter: "Milky Way core"
        }
    }

    func horizontal(at date: Date, observer: Observer) -> Horizontal {
        let t = AstroTime(date)
        switch self {
        case .sun: return Ephemeris.horizontal(.sun, at: t, observer: observer)
        case .moon: return Ephemeris.horizontal(.moon, at: t, observer: observer)
        case .galacticCenter: return MilkyWay.center(at: t, observer: observer)
        }
    }
}

public struct FindQuery: Sendable, Hashable, Codable {
    public var body: FindBody
    /// Target azimuth (degrees east of true north), or nil for any.
    public var azimuth: Double?
    public var azimuthTolerance: Double
    /// Target (refracted) elevation in degrees, or nil for "above the horizon".
    public var elevation: Double?
    public var elevationTolerance: Double
    public var start: Date
    public var end: Date

    public init(body: FindBody, azimuth: Double?, azimuthTolerance: Double = 1, elevation: Double?,
                elevationTolerance: Double = 1, start: Date, end: Date) {
        self.body = body
        self.azimuth = azimuth
        self.azimuthTolerance = max(0.01, azimuthTolerance)
        self.elevation = elevation
        self.elevationTolerance = max(0.01, elevationTolerance)
        self.start = start
        self.end = end
    }
}

public struct FindMatch: Sendable, Hashable, Identifiable {
    public let time: Date
    public let azimuth: Double
    public let elevation: Double
    /// Signed differences from the target (degrees); 0 for an unconstrained coordinate.
    public let azimuthError: Double
    public let elevationError: Double
    /// Moon illumination at the time (for the Moon and the core), else nil.
    public let moonIllumination: Double?
    public var id: Date { time }
}

public enum BodyFinder {
    static let step: TimeInterval = 300
    /// Lowest elevation counted as "above the horizon" when no elevation is given.
    static let horizon = -0.8

    /// Longest range searched in one call, to keep the search well under a second per month.
    public static let maximumDays = 732.0

    public static func find(_ query: FindQuery, observer: Observer) -> [FindMatch] {
        guard query.azimuth != nil || query.elevation != nil else { return [] }
        let end = min(query.end, query.start.addingTimeInterval(maximumDays * 86_400))
        guard end > query.start else { return [] }
        var candidates: [Date] = []

        var t = query.start
        var prev = sample(query, at: t, observer: observer)
        while t < end {
            let next = min(t.addingTimeInterval(step), end)
            let cur = sample(query, at: next, observer: observer)
            if let a0 = prev.az, let a1 = cur.az, a0 * a1 <= 0, a0 != a1, abs(a1 - a0) < 90 {
                candidates.append(refine(from: t, to: next, f0: a0, query: query, observer: observer, coordinate: \.az))
            }
            if let e0 = prev.el, let e1 = cur.el, e0 * e1 <= 0, e0 != e1 {
                candidates.append(refine(from: t, to: next, f0: e0, query: query, observer: observer, coordinate: \.el))
            }
            prev = cur
            t = next
        }

        let matches = candidates.compactMap { evaluate(query, at: $0, observer: observer) }.sorted { $0.time < $1.time }
        // Merge matches within an hour (an azimuth and an elevation crossing of the same pass).
        var merged: [FindMatch] = []
        for match in matches {
            if let last = merged.last, match.time.timeIntervalSince(last.time) < 3600 {
                if score(match, query) < score(last, query) { merged[merged.count - 1] = match }
            } else {
                merged.append(match)
            }
        }
        return merged
    }

    /// The matches of a single local day for one body at one azimuth: when it crosses
    /// `azimuth` while above the horizon (alignment with a bearing).
    public static func alignments(_ body: FindBody, azimuth: Double, observer: Observer, from start: Date, to end: Date) -> [FindMatch] {
        find(FindQuery(body: body, azimuth: azimuth, azimuthTolerance: 0.5, elevation: nil, start: start, end: end),
             observer: observer)
    }

    // MARK: Internals

    struct Sample {
        /// Signed difference from the target azimuth in (−180, 180], or nil when unconstrained.
        var az: Double?
        var el: Double?
    }

    static func sample(_ q: FindQuery, at date: Date, observer: Observer) -> Sample {
        let h = q.body.horizontal(at: date, observer: observer)
        return Sample(az: q.azimuth.map { wrap(h.azimuth - $0) }, el: q.elevation.map { h.altitude - $0 })
    }

    static func refine(from a: Date, to b: Date, f0: Double, query: FindQuery, observer: Observer,
                       coordinate: KeyPath<Sample, Double?>) -> Date {
        var lo = a, hi = b, flo = f0
        while hi.timeIntervalSince(lo) > 0.5 {
            let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
            guard let fm = sample(query, at: mid, observer: observer)[keyPath: coordinate] else { break }
            if (flo <= 0) == (fm <= 0) { lo = mid; flo = fm } else { hi = mid }
        }
        return lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
    }

    static func evaluate(_ q: FindQuery, at date: Date, observer: Observer) -> FindMatch? {
        let h = q.body.horizontal(at: date, observer: observer)
        let dAz = q.azimuth.map { wrap(h.azimuth - $0) } ?? 0
        let dEl = q.elevation.map { h.altitude - $0 } ?? 0
        guard abs(dAz) <= q.azimuthTolerance + 1e-6, abs(dEl) <= q.elevationTolerance + 1e-6 else { return nil }
        if q.elevation == nil && h.altitude < horizon { return nil }
        let moon = q.body == .sun ? nil : Lunar.illumination(at: AstroTime(date)).fraction
        return FindMatch(time: date, azimuth: h.azimuth, elevation: h.altitude, azimuthError: dAz, elevationError: dEl,
                         moonIllumination: moon)
    }

    static func score(_ m: FindMatch, _ q: FindQuery) -> Double {
        abs(m.azimuthError) / q.azimuthTolerance + abs(m.elevationError) / q.elevationTolerance
    }

    static func wrap(_ x: Double) -> Double {
        var v = x.truncatingRemainder(dividingBy: 360)
        if v > 180 { v -= 360 }
        if v <= -180 { v += 360 }
        return v
    }
}
