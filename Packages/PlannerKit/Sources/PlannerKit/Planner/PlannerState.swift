// Packages/PlannerKit/Sources/PlannerKit/Planner/PlannerState.swift
//
// Observable state of one Planner screen. Place and time live in the shared PillSession, so
// the Planner and the Sun/Moon tools always agree. This adds the map style, the selected
// panel, the time zone toggle and the latest snapshot, which is computed off the main actor
// by `PlannerEngine`. Requests are coalesced: while one computation runs, newer requests
// replace each other and only the latest is computed next, so a fast scrub never queues up
// stale work.

import AstroCore
import Foundation
import GeoCore
import Observation

public enum PlannerMapStyle: String, Sendable, CaseIterable, Codable, Identifiable {
    case standard, satellite, hybrid, terrain
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: "Standard"
        case .satellite: "Satellite"
        case .hybrid: "Hybrid"
        case .terrain: "Terrain"
        }
    }
}

@MainActor
@Observable
public final class PlannerState {
    public let session: PillSession
    public private(set) var snapshot: PlannerSnapshot?
    public var mapStyle: PlannerMapStyle = .standard
    public var selectedPanel: PlannerPanelKind = .pin
    public var useDeviceTimeZone = false
    /// Bumped when the place changes from outside the map (search, picker), so the map
    /// recentres on the pin. Dragging the pin does not bump it.
    public private(set) var recenterToken = 0
    /// True while a dropped pin's name and time zone are being looked up.
    public private(set) var resolvingPin = false

    @ObservationIgnored private let engine: PlannerEngine
    @ObservationIgnored private let placeLookup: PlaceLookup
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var pending: Request?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var pinGeneration = 0
    @ObservationIgnored private var prefetched: PlannerDay?

    struct Request: Equatable {
        let location: PillLocation
        let instant: Date
        let thresholds: SolarThresholds
    }

    /// - Parameter lookup: reverse geocoder for dropped pins (name and time zone); nil in tests.
    public init(session: PillSession, engine: PlannerEngine = PlannerEngine(),
                lookup: PlaceLookup.Lookup? = nil, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.engine = engine
        self.placeLookup = PlaceLookup(lookup: lookup ?? { _, _ in nil })
        self.clock = clock
    }

    // MARK: Computation

    /// Schedules a recomputation for the session's current place and instant.
    public func refresh() {
        let request = Request(location: session.location, instant: session.instant, thresholds: session.thresholds)
        if let snapshot, snapshot.location == request.location,
           abs(snapshot.instant.timeIntervalSince(request.instant)) < 30, pending == nil {
            return
        }
        pending = request
        guard worker == nil else { return }
        worker = Task { [engine] in
            while let next = self.pending {
                self.pending = nil
                let result = await engine.snapshot(location: next.location, instant: next.instant, thresholds: next.thresholds)
                self.snapshot = result
                if self.pending == nil, self.prefetched != result.day {
                    self.prefetched = result.day
                    await engine.prefetchNeighbours(of: result.day.day, location: next.location, thresholds: next.thresholds)
                }
            }
            self.worker = nil
        }
    }

    /// Waits until no computation is pending (tests and UI-test hooks).
    public func settle() async {
        while let worker { await worker.value }
    }

    public func panels(options: PlannerDisplayOptions) -> [PlannerPanel] {
        guard let snapshot else { return [] }
        return PlannerPanels.all(snapshot: snapshot, instant: session.instant, options: options)
    }

    // MARK: Place

    /// A place chosen from search or the picker: recentres the map.
    public func select(_ location: PillLocation) {
        session.select(location)
        recenterToken += 1
        refresh()
    }

    /// The pin was dropped or dragged on the map. The place moves at once (with a cached
    /// or longitude-based zone), then its name and time zone are looked up and applied if
    /// the pin has not moved again in the meantime.
    public func movePin(latitude: Double, longitude: Double) async {
        let lat = max(-90, min(90, latitude))
        let lon = Geodesy.normalizeLongitude(longitude)
        pinGeneration += 1
        let generation = pinGeneration
        let fallbackName = Formatting.coordinate(latitude: lat, longitude: lon, style: .decimal)
        let cached = await placeLookup.cached(latitude: lat, longitude: lon)
        guard generation == pinGeneration else { return }
        session.move(to: PillLocation(
            name: cached?.name ?? "Dropped pin", latitude: lat, longitude: lon, elevation: 0,
            timeZoneIdentifier: cached?.timeZoneIdentifier ?? PlaceLookup.nauticalZone(longitude: lon).identifier))
        refresh()
        guard cached == nil else { return }
        resolvingPin = true
        let resolved = await placeLookup.resolve(latitude: lat, longitude: lon)
        guard generation == pinGeneration else { return }
        resolvingPin = false
        session.move(to: PillLocation(name: resolved.name ?? fallbackName, latitude: lat, longitude: lon, elevation: 0,
                                      timeZoneIdentifier: resolved.timeZoneIdentifier))
        refresh()
    }

    // MARK: Time

    /// Moves the time by whole minutes (time bar drag).
    public func scrub(minutes: Int) {
        guard minutes != 0 else { return }
        session.scrub(minutes: Double(minutes))
        refresh()
    }

    public func shift(days: Int) {
        session.shift(days: days)
        refresh()
    }

    /// Jumps to the next matching event of the day; returns false when there is none.
    @discardableResult
    public func jump(_ jump: PlannerJump) -> Bool {
        guard let day = snapshot?.day else {
            if jump == .now { session.resetToNow(); refresh(); return true }
            return false
        }
        guard let target = jump.target(from: session.instant, day: day, now: clock()) else { return false }
        session.instant = target
        refresh()
        return true
    }

    /// Whether the day has any event for `jump` (to disable its button).
    public func canJump(_ jump: PlannerJump) -> Bool {
        guard jump != .now else { return true }
        guard let day = snapshot?.day else { return false }
        return !jump.candidates(in: day).isEmpty
    }
}
