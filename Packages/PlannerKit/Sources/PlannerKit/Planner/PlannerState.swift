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
    /// Bodies drawn on the map.
    public var layers: PlannerLayers = .all
    /// Bumped when the place changes from outside the map (search, picker), so the map
    /// recentres on the pin. Dragging the pin does not bump it.
    public private(set) var recenterToken = 0
    /// True while a dropped pin's name and time zone are being looked up.
    public private(set) var resolvingPin = false
    /// The second pin (distance, bearing, obstacles), with its ground elevation once known.
    public private(set) var target: TargetPin?
    /// Observer eye height above the ground at the pin (m).
    public var eyeHeight = 1.7 { didSet { updateObstacle() } }
    /// Field and depth of field drawn on the map.
    public var mapOptics = MapOptics()
    /// Geodetics and Sun/Moon alignments for the target pin on the snapshot's day.
    public private(set) var obstacle: ObstacleReport?
    /// Meteor showers and eclipses for the pin's night (panels 8 and 9).
    public private(set) var events: PlannerEvents?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    /// True while the target's ground elevation is being looked up.
    public private(set) var resolvingTarget = false

    @ObservationIgnored private let engine: PlannerEngine
    @ObservationIgnored private let placeLookup: PlaceLookup
    @ObservationIgnored private let clock: (@Sendable () -> Date)?
    @ObservationIgnored private var pending: Request?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var pinGeneration = 0
    @ObservationIgnored private var prefetched: PlannerDay?
    @ObservationIgnored private let elevations: ElevationService
    @ObservationIgnored private var obstacleKey: ObstacleKey?
    @ObservationIgnored private var eventsKey: EventsKey?

    private struct EventsKey: Equatable {
        let location: PillLocation
        let night: LocalDay
    }
    @ObservationIgnored private var targetGeneration = 0

    struct ObstacleKey: Equatable {
        let location: PillLocation
        let day: LocalDay
        let target: TargetPin
        let eyeHeight: Double
    }

    struct Request: Equatable {
        let location: PillLocation
        let instant: Date
        let thresholds: SolarThresholds
    }

    /// - Parameters:
    ///   - lookup: reverse geocoder for dropped pins (name and time zone); nil in tests.
    ///   - clock: source of "now" for the Now jump; nil uses the session's clock.
    ///   - elevation: ground elevation service for pins; nil in tests (elevation unknown).
    public init(session: PillSession, engine: PlannerEngine = PlannerEngine(),
                lookup: PlaceLookup.Lookup? = nil, clock: (@Sendable () -> Date)? = nil,
                elevation: ElevationService.Fetch? = nil) {
        self.session = session
        self.engine = engine
        self.placeLookup = PlaceLookup(lookup: lookup ?? { _, _ in nil })
        self.clock = clock
        self.elevations = ElevationService(fetch: elevation ?? { _, _ in nil })
    }

    // MARK: Computation

    /// Schedules a recomputation for the session's current place and instant.
    public func refresh() {
        let request = Request(location: session.location, instant: session.instant, thresholds: session.thresholds)
        if let snapshot, snapshot.location == request.location,
           abs(snapshot.instant.timeIntervalSince(request.instant)) < 30, pending == nil, worker == nil {
            // An in-flight computation for another instant would overwrite this snapshot.
            return
        }
        pending = request
        guard worker == nil else { return }
        worker = Task { [engine] in
            while let next = self.pending {
                self.pending = nil
                let result = await engine.snapshot(location: next.location, instant: next.instant, thresholds: next.thresholds)
                self.snapshot = result
                self.updateObstacle()
                self.updateEvents()
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
        return PlannerPanels.all(snapshot: snapshot, instant: session.instant, options: options, obstacle: obstacle,
                                 events: events)
    }

    // MARK: Place

    /// A place chosen from search or the picker: recentres the map.
    /// A place without a known elevation (0) gets its ground elevation looked up, as a
    /// dropped pin does, so the observer height does not depend on how the place was chosen.
    public func select(_ location: PillLocation) async {
        pinGeneration += 1
        let generation = pinGeneration
        resolvingPin = false
        session.select(location)
        recenterToken += 1
        refresh()
        guard location.elevation == 0 else { return }
        await applyGroundElevation(latitude: location.latitude, longitude: location.longitude, generation: generation)
    }

    /// The pin was dropped or dragged on the map. The place moves at once (with a cached
    /// or longitude-based zone), then its name and time zone are looked up and applied if
    /// the pin has not moved again in the meantime.
    public func movePin(latitude: Double, longitude: Double) async {
        let lat = max(-90, min(90, latitude))
        let lon = Geodesy.normalizeLongitude(longitude)
        pinGeneration += 1
        let generation = pinGeneration
        // A superseded lookup never clears the badge itself.
        resolvingPin = false
        let fallbackName = Formatting.coordinate(latitude: lat, longitude: lon, style: .decimal)
        let cached = await placeLookup.cached(latitude: lat, longitude: lon)
        guard generation == pinGeneration else { return }
        session.move(to: PillLocation(
            name: cached?.name ?? "Dropped pin", latitude: lat, longitude: lon, elevation: 0,
            timeZoneIdentifier: cached?.timeZoneIdentifier ?? PlaceLookup.nauticalZone(longitude: lon).identifier))
        refresh()
        if cached == nil {
            resolvingPin = true
            let resolved = await placeLookup.resolve(latitude: lat, longitude: lon)
            guard generation == pinGeneration else { return }
            resolvingPin = false
            session.move(to: PillLocation(name: resolved.name ?? fallbackName, latitude: lat, longitude: lon, elevation: 0,
                                          timeZoneIdentifier: resolved.timeZoneIdentifier))
            refresh()
        }
        await applyGroundElevation(latitude: lat, longitude: lon, generation: generation)
    }

    /// Ground elevation of the observer's spot, applied unless the place changed meanwhile.
    private func applyGroundElevation(latitude: Double, longitude: Double, generation: Int) async {
        guard let ground = await elevations.elevation(latitude: latitude, longitude: longitude),
              generation == pinGeneration else { return }
        var placed = session.location
        placed.elevation = ground
        session.move(to: placed)
        refresh()
        updateObstacle()
    }

    // MARK: Target pin

    /// Places the target pin, or removes it with nil, then looks up its ground elevation.
    public func setTarget(_ point: GeoPoint?, objectHeight: Double? = nil) async {
        targetGeneration += 1
        let generation = targetGeneration
        guard let point else {
            target = nil
            obstacle = nil
            obstacleKey = nil
            return
        }
        let safe = GeoPoint(latitude: max(-90, min(90, point.latitude)), longitude: Geodesy.normalizeLongitude(point.longitude))
        let height = objectHeight ?? target?.objectHeight ?? 0
        let known = await elevations.cached(latitude: safe.latitude, longitude: safe.longitude)
        guard generation == targetGeneration else { return }
        target = TargetPin(point: safe, groundElevation: known, objectHeight: height)
        updateObstacle()
        guard known == nil else { return }
        resolvingTarget = true
        let ground = await elevations.elevation(latitude: safe.latitude, longitude: safe.longitude)
        guard generation == targetGeneration else { return }
        resolvingTarget = false
        target?.groundElevation = ground
        updateObstacle()
    }

    /// Adds a target pin 1 km from the observer along the Sun's current azimuth.
    public func addTarget() async {
        let bearing = snapshot?.sun.azimuth ?? 0
        await setTarget(Geodesy.destination(from: session.location.geoPoint, bearing: bearing, distance: 1000).normalized)
    }

    public func setObjectHeight(_ height: Double) {
        guard target != nil else { return }
        target?.objectHeight = max(0, height)
        updateObstacle()
    }

    /// Recomputes the obstacle report when the place, day, target or eye height changed.
    func updateObstacle() {
        guard let target, let day = snapshot?.day.day, snapshot?.location == session.location else {
            if target == nil { obstacle = nil }
            return
        }
        let key = ObstacleKey(location: session.location, day: day, target: target, eyeHeight: eyeHeight)
        guard key != obstacleKey else { return }
        obstacleKey = key
        obstacle = ObstacleReport.compute(observer: key.location, eyeHeight: eyeHeight, target: target, day: day)
    }

    /// Recomputes meteor showers and eclipses when the place or night changed.
    func updateEvents() {
        let location = session.location
        let night = MeteorShowerCalendar.night(containing: session.instant, timeZone: location.timeZone)
        if let events, events.location == location, events.night == night { return }
        if eventsTask != nil, eventsKey == EventsKey(location: location, night: night) { return }
        eventsKey = EventsKey(location: location, night: night)
        eventsTask?.cancel()
        let instant = session.instant
        eventsTask = Task {
            let result = await Task.detached(priority: .utility) { PlannerEvents.compute(location: location, instant: instant) }.value
            guard !Task.isCancelled, self.eventsKey == EventsKey(location: location, night: night) else { return }
            self.events = result
            self.eventsTask = nil
        }
    }

    /// Waits for the meteor and eclipse computation (tests).
    public func settleEvents() async {
        if let eventsTask { await eventsTask.value }
    }

    /// Bearing and distance used for the map's field of view: the target's, if any.
    public var targetLine: GeodesicLine? {
        target.map { Geodesy.inverse(session.location.geoPoint, $0.point) }
    }

    // MARK: Plans

    /// The current Planner state as a plan.
    public func plan(named name: String, notes: String = "", cameraID: String? = nil, reminderMinutes: Int? = nil,
                     now: Date = Date()) -> Plan {
        Plan(name: name, notes: notes, created: now, location: session.location, instant: session.instant, target: target,
             eyeHeight: eyeHeight, mapOptics: mapOptics, cameraID: cameraID, layers: layers, mapStyle: mapStyle,
             panel: selectedPanel.rawValue, reminderMinutes: reminderMinutes)
    }

    /// Restores a saved plan: place (recentring the map), moment, target, optics and display.
    public func apply(_ plan: Plan) async {
        session.select(plan.location)
        session.instant = plan.instant
        eyeHeight = plan.eyeHeight
        mapOptics = plan.mapOptics
        layers = plan.layers
        mapStyle = plan.mapStyle
        selectedPanel = PlannerPanelKind(rawValue: plan.panel) ?? .pin
        recenterToken += 1
        refresh()
        if let t = plan.target {
            targetGeneration += 1
            target = t
            updateObstacle()
        } else {
            await setTarget(nil)
        }
    }

    // MARK: Find

    /// Runs a Find search for the current place off the main actor. Cancelling the calling
    /// task stops the search (it then returns no matches).
    public func find(_ query: FindQuery) async -> [FindMatch] {
        let observer = session.location.observer
        let search = Task.detached(priority: .userInitiated) { BodyFinder.find(query, observer: observer) }
        return await withTaskCancellationHandler { await search.value } onCancel: { search.cancel() }
    }

    /// Moves the Planner to a Find result.
    public func show(_ match: FindMatch) {
        session.instant = match.time
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
        guard let target = jump.target(from: session.instant, day: day, now: clock?() ?? session.now) else { return false }
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
