// Packages/PlannerKit/Sources/PlannerKit/PillSession.swift
//
// Shared state for the Sun and Moon pills: the chosen place and instant. Both pills read
// the same session, so switching between them keeps the location and date. The selected
// location and a short list of recent places persist in UserDefaults.

import AstroCore
import Foundation
import Observation

@MainActor
@Observable
public final class PillSession {
    public private(set) var location: PillLocation
    /// The selected instant. Its calendar day in the location's zone is the day shown.
    public var instant: Date
    /// Most recent first, without duplicates; at most `maxRecents`.
    public private(set) var recents: [PillLocation]

    public var thresholds: SolarThresholds = .standard
    public var supermoonRule: SupermoonRule = .standard

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let clock: @Sendable () -> Date
    public static let maxRecents = 8
    static let locationKey = "pills.location"
    static let recentsKey = "pills.recents"

    /// - Parameters:
    ///   - defaults: where to persist the location; nil keeps everything in memory (tests, previews).
    ///   - clock: source of "now".
    public init(defaults: UserDefaults? = .standard, fallback: PillLocation = PillLocation.samples[0],
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.clock = clock
        let decoder = JSONDecoder()
        location = defaults?.data(forKey: Self.locationKey).flatMap { try? decoder.decode(PillLocation.self, from: $0) }
            ?? fallback
        recents = defaults?.data(forKey: Self.recentsKey).flatMap { try? decoder.decode([PillLocation].self, from: $0) }
            ?? []
        instant = clock()
    }

    public var timeZone: TimeZone { location.timeZone }
    public var day: LocalDay { LocalDay(containing: instant, timeZone: timeZone) }
    /// The session's "now" (fixed in screenshots and tests).
    public var now: Date { clock() }
    public var isToday: Bool { day == LocalDay(containing: clock(), timeZone: timeZone) }

    /// Switches place, keeping the same wall-clock date and time at the new place.
    public func select(_ newLocation: PillLocation) {
        var oldCal = Calendar(identifier: .gregorian)
        oldCal.timeZone = timeZone
        let wall = oldCal.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
        location = newLocation
        var newCal = Calendar(identifier: .gregorian)
        newCal.timeZone = newLocation.timeZone
        if let moved = newCal.date(from: wall) { instant = moved }
        recents.removeAll { $0.id == newLocation.id }
        recents.insert(newLocation, at: 0)
        if recents.count > Self.maxRecents { recents.removeLast(recents.count - Self.maxRecents) }
        persist()
    }

    /// Moves the place without adding it to the recents (the Planner pin being dragged or
    /// renamed once its time zone resolves). Keeps the wall-clock time, like `select`.
    public func move(to newLocation: PillLocation) {
        guard newLocation != location else { return }
        var oldCal = Calendar(identifier: .gregorian)
        oldCal.timeZone = timeZone
        let wall = oldCal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)
        location = newLocation
        var newCal = Calendar(identifier: .gregorian)
        newCal.timeZone = newLocation.timeZone
        if let moved = newCal.date(from: wall) { instant = moved }
        persist()
    }

    /// Moves the instant by `minutes` (the Planner time bar).
    public func scrub(minutes: Double) {
        instant = instant.addingTimeInterval(minutes * 60)
    }

    /// Moves by whole local days, keeping the wall-clock time (DST-safe).
    public func shift(days: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        if let moved = cal.date(byAdding: .day, value: days, to: instant) { instant = moved }
    }

    /// Moves by `months` calendar months, keeping the day of month (clamped) and the wall-clock time.
    public func shift(months: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        if let moved = cal.date(byAdding: .month, value: months, to: instant) { instant = moved }
    }

    public func resetToNow() { instant = clock() }

    private func persist() {
        guard let defaults else { return }
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(location) { defaults.set(data, forKey: Self.locationKey) }
        if let data = try? encoder.encode(recents) { defaults.set(data, forKey: Self.recentsKey) }
    }
}
