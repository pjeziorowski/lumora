// Packages/PlannerKit/Sources/PlannerKit/Planner/PlannerEngine.swift
//
// Computes Planner snapshots off the main actor and memoizes them. The time scrubber asks
// for a new instant many times per second, so results are cached per (place, minute) and
// the expensive day-level searches per (place, local day).

import AstroCore
import Foundation

/// Small least-recently-inserted cache.
struct BoundedCache<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]
    private var order: [Key] = []
    let capacity: Int

    init(capacity: Int) { self.capacity = capacity }

    subscript(key: Key) -> Value? {
        get { storage[key] }
        set {
            guard let newValue else {
                storage[key] = nil
                order.removeAll { $0 == key }
                return
            }
            if storage.updateValue(newValue, forKey: key) == nil {
                order.append(key)
                if order.count > capacity { storage[order.removeFirst()] = nil }
            }
        }
    }

    var count: Int { storage.count }
}

public actor PlannerEngine {
    /// Place key: coordinates to 1e-6° (~10 cm), height to the decimetre, and the zone.
    struct PlaceKey: Hashable {
        let lat: Int64
        let lon: Int64
        let height: Int64
        let zone: String

        init(_ location: PillLocation) {
            lat = Int64((location.latitude * 1e6).rounded())
            lon = Int64((location.longitude * 1e6).rounded())
            height = Int64((location.elevation * 10).rounded())
            zone = location.timeZoneIdentifier
        }
    }

    struct DayKey: Hashable {
        let place: PlaceKey
        let year: Int, month: Int, day: Int
        let thresholds: SolarThresholds
    }

    struct InstantKey: Hashable {
        let place: PlaceKey
        /// Whole minutes since 1970.
        let minute: Int64
        let thresholds: SolarThresholds
    }

    private var days = BoundedCache<DayKey, PlannerDay>(capacity: 24)
    private var snapshots = BoundedCache<InstantKey, PlannerSnapshot>(capacity: 2048)
    public private(set) var dayComputations = 0
    public private(set) var snapshotComputations = 0

    public init() {}

    /// The snapshot for `instant` rounded to the nearest minute (the scrubber's resolution).
    public func snapshot(location: PillLocation, instant: Date, thresholds: SolarThresholds = .standard) -> PlannerSnapshot {
        let minute = Int64((instant.timeIntervalSince1970 / 60).rounded())
        let place = PlaceKey(location)
        let key = InstantKey(place: place, minute: minute, thresholds: thresholds)
        if let hit = snapshots[key] { return hit }
        let rounded = Date(timeIntervalSince1970: Double(minute) * 60)
        let localDay = LocalDay(containing: rounded, timeZone: location.timeZone)
        let day = plannerDay(location: location, day: localDay, place: place, thresholds: thresholds)
        let snap = PlannerSnapshot.compute(location: location, instant: rounded, day: day, thresholds: thresholds)
        snapshotComputations += 1
        snapshots[key] = snap
        return snap
    }

    /// Computes the days either side of `day` ahead of time, so scrubbing across midnight
    /// does not wait for the day-level searches.
    public func prefetchNeighbours(of day: LocalDay, location: PillLocation, thresholds: SolarThresholds = .standard) {
        let place = PlaceKey(location)
        for offset in [1, -1] {
            _ = plannerDay(location: location, day: day.adding(days: offset), place: place, thresholds: thresholds)
        }
    }

    public func day(location: PillLocation, day: LocalDay, thresholds: SolarThresholds = .standard) -> PlannerDay {
        plannerDay(location: location, day: day, place: PlaceKey(location), thresholds: thresholds)
    }

    private func plannerDay(location: PillLocation, day: LocalDay, place: PlaceKey, thresholds: SolarThresholds) -> PlannerDay {
        let key = DayKey(place: place, year: day.year, month: day.month, day: day.day, thresholds: thresholds)
        if let hit = days[key] { return hit }
        let computed = PlannerDay.compute(location: location, day: day, thresholds: thresholds)
        dayComputations += 1
        days[key] = computed
        return computed
    }
}
