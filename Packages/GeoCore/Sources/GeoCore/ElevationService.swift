// Packages/GeoCore/Sources/GeoCore/ElevationService.swift
//
// Ground elevation for a coordinate, with a cache. The network lookup (an elevation web
// service) is injected by the app so this package stays free of networking and testable
// offline. Results are cached per ~11 m cell (0.0001°); failures are not cached so a later
// online attempt can still succeed.

import Foundation

public actor ElevationService {
    public typealias Fetch = @Sendable (_ latitude: Double, _ longitude: Double) async -> Double?

    /// Cell size in degrees (0.0001° ≈ 11 m of latitude).
    public static let cellSize = 0.0001

    struct Cell: Hashable {
        let lat: Int
        let lon: Int

        init(latitude: Double, longitude: Double) {
            lat = Int((latitude / ElevationService.cellSize).rounded())
            lon = Int((Geodesy.normalizeLongitude(longitude) / ElevationService.cellSize).rounded())
        }
    }

    private let fetch: Fetch
    private var cache: [Cell: Double] = [:]
    private var order: [Cell] = []
    private let capacity: Int
    public private(set) var fetchCount = 0

    public init(capacity: Int = 512, fetch: @escaping Fetch) {
        self.capacity = capacity
        self.fetch = fetch
    }

    public func cached(latitude: Double, longitude: Double) -> Double? {
        cache[Cell(latitude: latitude, longitude: longitude)]
    }

    /// Elevation in metres above sea level, or nil when the service cannot answer.
    public func elevation(latitude: Double, longitude: Double) async -> Double? {
        let cell = Cell(latitude: latitude, longitude: longitude)
        if let hit = cache[cell] { return hit }
        fetchCount += 1
        guard let value = await fetch(latitude, longitude), value.isFinite, value > -500, value < 9000 else { return nil }
        if cache[cell] == nil {
            cache[cell] = value
            order.append(cell)
            if order.count > capacity { cache[order.removeFirst()] = nil }
        }
        return value
    }
}
