// Packages/GeoCore/Sources/GeoCore/PlaceLookup.swift
//
// Coordinate → (place name, IANA time zone) with a cache. The actual lookup (reverse
// geocoding) is injected by the app, so this package stays free of CoreLocation and is
// testable on Linux. Results are cached per ~1 km grid cell; failed lookups fall back to
// the nautical time zone for the longitude and are not cached, so a later online attempt
// can still succeed.

import Foundation

public struct PlaceInfo: Sendable, Hashable, Codable {
    public var name: String?
    public var timeZoneIdentifier: String?

    public init(name: String?, timeZoneIdentifier: String?) {
        self.name = name
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

public struct ResolvedPlace: Sendable, Hashable {
    public let name: String?
    public let timeZoneIdentifier: String
    /// True when the zone is the longitude-based nautical zone (lookup failed or offline).
    public let isFallbackZone: Bool
}

public actor PlaceLookup {
    public typealias Lookup = @Sendable (_ latitude: Double, _ longitude: Double) async -> PlaceInfo?

    /// Grid cell size in degrees (0.01° ≈ 1.1 km of latitude).
    public static let cellSize = 0.01

    private let lookup: Lookup
    private var cache: [Cell: PlaceInfo] = [:]
    private var order: [Cell] = []
    private let capacity: Int
    public private(set) var lookupCount = 0

    struct Cell: Hashable {
        let lat: Int
        let lon: Int

        init(latitude: Double, longitude: Double) {
            lat = Int((latitude / PlaceLookup.cellSize).rounded())
            lon = Int((Geodesy.normalizeLongitude(longitude) / PlaceLookup.cellSize).rounded())
        }
    }

    public init(capacity: Int = 256, lookup: @escaping Lookup) {
        self.capacity = capacity
        self.lookup = lookup
    }

    /// Cached info for the cell, without calling the lookup.
    public func cached(latitude: Double, longitude: Double) -> ResolvedPlace? {
        cache[Cell(latitude: latitude, longitude: longitude)].map { Self.resolve($0, longitude: longitude) }
    }

    public func resolve(latitude: Double, longitude: Double) async -> ResolvedPlace {
        let cell = Cell(latitude: latitude, longitude: longitude)
        if let hit = cache[cell] { return Self.resolve(hit, longitude: longitude) }
        lookupCount += 1
        let info = await lookup(latitude, longitude)
        if let info, info.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) != nil {
            store(info, for: cell)
            return Self.resolve(info, longitude: longitude)
        }
        return Self.resolve(info ?? PlaceInfo(name: nil, timeZoneIdentifier: nil), longitude: longitude)
    }

    private func store(_ info: PlaceInfo, for cell: Cell) {
        if cache[cell] == nil { order.append(cell) }
        cache[cell] = info
        if order.count > capacity {
            cache[order.removeFirst()] = nil
        }
    }

    static func resolve(_ info: PlaceInfo, longitude: Double) -> ResolvedPlace {
        if let id = info.timeZoneIdentifier, TimeZone(identifier: id) != nil {
            return ResolvedPlace(name: info.name, timeZoneIdentifier: id, isFallbackZone: false)
        }
        return ResolvedPlace(name: info.name, timeZoneIdentifier: nauticalZone(longitude: longitude).identifier,
                             isFallbackZone: true)
    }

    /// The 15°-wide nautical zone containing `longitude` (UTC−12…UTC+12). Used when no real
    /// zone is known, e.g. over the open sea or offline.
    public static func nauticalZone(longitude: Double) -> TimeZone {
        let lon = Geodesy.normalizeLongitude(longitude)
        // −180 and +180 are the same meridian; the dateline half-zone east of it is UTC−12.
        let hours = lon <= -172.5 ? -12 : Int((lon / 15).rounded())
        return TimeZone(secondsFromGMT: max(-12, min(12, hours)) * 3600) ?? TimeZone(identifier: "UTC")!
    }
}
