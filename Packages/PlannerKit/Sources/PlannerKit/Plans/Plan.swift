// Packages/PlannerKit/Sources/PlannerKit/Plans/Plan.swift
//
// A saved Planner state: place, moment, target pin, map optics and display choices, plus the
// user's name, notes and reminder. Plans are plain Codable values; the app stores them with
// SwiftData and exchanges them as JSON (`PlanArchive`), so a plan round-trips unchanged
// through export and import.

import Foundation
import GeoCore

public struct Plan: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var notes: String
    public var created: Date
    public var modified: Date
    public var location: PillLocation
    public var instant: Date
    public var target: TargetPin?
    public var eyeHeight: Double
    public var mapOptics: MapOptics
    public var cameraID: String?
    public var layers: PlannerLayers
    public var mapStyle: PlannerMapStyle
    public var panel: String
    /// Minutes before `instant` to send a reminder, nil for none.
    public var reminderMinutes: Int?

    public init(id: UUID = UUID(), name: String, notes: String = "", created: Date = Date(), modified: Date? = nil,
                location: PillLocation, instant: Date, target: TargetPin? = nil, eyeHeight: Double = 1.7,
                mapOptics: MapOptics = MapOptics(), cameraID: String? = nil, layers: PlannerLayers = .all,
                mapStyle: PlannerMapStyle = .standard, panel: String = PlannerPanelKind.pin.rawValue,
                reminderMinutes: Int? = nil) {
        self.id = id
        self.name = name
        self.notes = notes
        self.created = created
        self.modified = modified ?? created
        self.location = location
        self.instant = instant
        self.target = target
        self.eyeHeight = eyeHeight
        self.mapOptics = mapOptics
        self.cameraID = cameraID
        self.layers = layers
        self.mapStyle = mapStyle
        self.panel = panel
        self.reminderMinutes = reminderMinutes
    }

    /// A copy with a new id and "copy" appended to the name.
    public func duplicated(now: Date = Date()) -> Plan {
        var copy = self
        copy.id = UUID()
        copy.name = "\(name) copy"
        copy.created = now
        copy.modified = now
        return copy
    }

    /// When the reminder fires, if any.
    public var reminderDate: Date? {
        reminderMinutes.map { instant.addingTimeInterval(-Double($0) * 60) }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, notes, created, modified, location, instant, target, eyeHeight, mapOptics, cameraID, layers
        case mapStyle, panel, reminderMinutes
    }

    /// Only id, name, location and instant are required, so plans stored by an older version
    /// (with fewer fields) still open; anything missing takes its default.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Plan(name: "", location: try c.decode(PillLocation.self, forKey: .location),
                            instant: try c.decode(Date.self, forKey: .instant))
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        location = defaults.location
        instant = defaults.instant
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? defaults.notes
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? instant
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? created
        target = try c.decodeIfPresent(TargetPin.self, forKey: .target)
        eyeHeight = try c.decodeIfPresent(Double.self, forKey: .eyeHeight) ?? defaults.eyeHeight
        mapOptics = try c.decodeIfPresent(MapOptics.self, forKey: .mapOptics) ?? defaults.mapOptics
        cameraID = try c.decodeIfPresent(String.self, forKey: .cameraID)
        layers = try c.decodeIfPresent(PlannerLayers.self, forKey: .layers) ?? defaults.layers
        mapStyle = try c.decodeIfPresent(PlannerMapStyle.self, forKey: .mapStyle) ?? defaults.mapStyle
        panel = try c.decodeIfPresent(String.self, forKey: .panel) ?? defaults.panel
        reminderMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderMinutes)
    }
}

/// A saved place (point of interest), independent of plans.
public struct SavedPlace: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var location: PillLocation
    public var notes: String
    public var created: Date

    public init(id: UUID = UUID(), location: PillLocation, notes: String = "", created: Date = Date()) {
        self.id = id
        self.location = location
        self.notes = notes
        self.created = created
    }

    enum CodingKeys: String, CodingKey { case id, location, notes, created }

    /// Notes and creation date are optional in stored data (older versions).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        location = try c.decode(PillLocation.self, forKey: .location)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date(timeIntervalSinceReferenceDate: 0)
    }
}

/// JSON exchange format for plans and places. Versioned so later releases can migrate.
public struct PlanArchive: Sendable, Hashable, Codable {
    public static let currentVersion = 1

    public var format = "lumora.plans"
    public var version = PlanArchive.currentVersion
    public var plans: [Plan]
    public var places: [SavedPlace]

    public init(plans: [Plan], places: [SavedPlace] = []) {
        self.plans = plans
        self.places = places
    }

    public enum ImportError: Error, Equatable {
        case notAPlanFile
        case newerVersion(Int)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            // Full precision: ISO 8601 with fractional seconds would round sub-millisecond parts.
            var c = encoder.singleValueContainer()
            try c.encode(date.timeIntervalSinceReferenceDate)
        }
        return try encoder.encode(self)
    }

    /// What importing this archive into a library changes. Plans are matched by id: an
    /// imported plan replaces the stored one with the same id (the file is the newer copy);
    /// places already stored are kept. Within the archive the last copy of an id wins for
    /// plans and the first for places.
    public struct Merge: Sendable, Hashable {
        public var added: [Plan] = []
        public var replaced: [Plan] = []
        public var addedPlaces: [SavedPlace] = []
        public var count: Int { added.count + replaced.count + addedPlaces.count }
    }

    public func merge(intoPlans existing: Set<UUID>, places existingPlaces: Set<UUID>) -> Merge {
        var result = Merge()
        var lastCopy: [UUID: Plan] = [:]
        var order: [UUID] = []
        for plan in plans {
            if lastCopy[plan.id] == nil { order.append(plan.id) }
            lastCopy[plan.id] = plan
        }
        for id in order {
            guard let plan = lastCopy[id] else { continue }
            if existing.contains(id) { result.replaced.append(plan) } else { result.added.append(plan) }
        }
        var seenPlaces = existingPlaces
        for place in places where !seenPlaces.contains(place.id) {
            seenPlaces.insert(place.id)
            result.addedPlaces.append(place)
        }
        return result
    }

    public static func decode(_ data: Data) throws -> PlanArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            Date(timeIntervalSinceReferenceDate: try decoder.singleValueContainer().decode(Double.self))
        }
        struct Header: Decodable {
            let format: String?
            let version: Int?
        }
        guard let header = try? decoder.decode(Header.self, from: data), header.format == "lumora.plans" else {
            throw ImportError.notAPlanFile
        }
        if let v = header.version, v > currentVersion { throw ImportError.newerVersion(v) }
        return try decoder.decode(PlanArchive.self, from: data)
    }
}

extension Plan {
    /// Plain-text summary for sharing: name, place, local time, Sun and Moon details.
    public func shareText(clock: ClockStyle = .twentyFourHour, units: UnitSystem = .metric) -> String {
        let zone = location.timeZone
        var lines = [
            name,
            "\(PlannerPanels.stamp(instant, zone: zone, clock: clock)) (\(Formatting.utcOffset(zone, at: instant)))",
            "\(location.name) · \(Formatting.coordinate(latitude: location.latitude, longitude: location.longitude, style: .decimal))",
        ]
        if let target {
            let line = Geodesy.inverse(location.geoPoint, target.point)
            lines.append("Target \(Formatting.distance(meters: line.distance, units: units)) at \(Formatting.azimuth(line.initialBearing))")
        }
        if !notes.isEmpty { lines.append(notes) }
        return lines.joined(separator: "\n")
    }
}
