// Packages/PlannerKit/Sources/PlannerKit/PillLocation.swift
//
// The place the Sun and Moon pills compute for: coordinates, height and the IANA time zone
// that times are shown in. Shared by the location picker and every pill screen.

import AstroCore
import Foundation
import GeoCore

public struct PillLocation: Sendable, Hashable, Codable, Identifiable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    /// Metres above sea level.
    public var elevation: Double
    /// IANA identifier, e.g. "Europe/Warsaw".
    public var timeZoneIdentifier: String

    public init(name: String, latitude: Double, longitude: Double, elevation: Double = 0, timeZoneIdentifier: String) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public var id: String { "\(name)|\(latitude)|\(longitude)" }

    public var observer: Observer { Observer(latitude: latitude, longitude: longitude, height: elevation) }

    /// Falls back to a whole-hour zone from the longitude if the identifier is unknown.
    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? Self.nauticalTimeZone(longitude: longitude)
    }

    /// Southern-hemisphere observers see the Moon's lit side mirrored and have seasons swapped.
    public var isSouthern: Bool { latitude < 0 }

    /// UTC offset of the 15°-wide nautical zone containing `longitude` (±12 h). Used only when
    /// no real time zone is known, e.g. coordinates typed for the open sea.
    public static func nauticalTimeZone(longitude: Double) -> TimeZone {
        PlaceLookup.nauticalZone(longitude: longitude)
    }

    public var geoPoint: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }

    /// Places used by the acceptance tests and offered as quick picks in the location picker.
    public static let samples: [PillLocation] = [
        PillLocation(name: "Warsaw", latitude: 52.2297, longitude: 21.0122, elevation: 100, timeZoneIdentifier: "Europe/Warsaw"),
        PillLocation(name: "New York", latitude: 40.7128, longitude: -74.0060, elevation: 10, timeZoneIdentifier: "America/New_York"),
        PillLocation(name: "Sydney", latitude: -33.8688, longitude: 151.2093, elevation: 20, timeZoneIdentifier: "Australia/Sydney"),
        PillLocation(name: "Quito", latitude: -0.1807, longitude: -78.4678, elevation: 2850, timeZoneIdentifier: "America/Guayaquil"),
        PillLocation(name: "Tromsø", latitude: 69.6492, longitude: 18.9553, elevation: 10, timeZoneIdentifier: "Europe/Oslo"),
        PillLocation(name: "Cape Town", latitude: -33.9249, longitude: 18.4241, elevation: 10, timeZoneIdentifier: "Africa/Johannesburg"),
        // Planner edge cases: on the antimeridian, and high Arctic (midnight sun / polar night).
        PillLocation(name: "Taveuni", latitude: -16.8000, longitude: 179.9990, elevation: 5, timeZoneIdentifier: "Pacific/Fiji"),
        PillLocation(name: "Longyearbyen", latitude: 78.2232, longitude: 15.6267, elevation: 10,
                     timeZoneIdentifier: "Arctic/Longyearbyen"),
    ]
}

/// Parses coordinates typed by the user. Accepts decimal degrees ("52.2297, 21.0122",
/// "-33.87 151.21"), hemisphere letters ("52.23N 21.01E", "N 52.23 E 21.01") and
/// degrees-minutes-seconds ("52°13'47\"N 21°00'44\"E", "52 13 47 N, 21 0 44 E").
public enum CoordinateParser {
    private typealias Group = (numbers: [Double], hemisphere: Character?)

    public static func parse(_ text: String) -> (latitude: Double, longitude: Double)? {
        // Normalise symbols to spaces and split hemisphere letters into their own tokens.
        var cleaned = ""
        for ch in text.uppercased() {
            switch ch {
            case "°", "'", "\"", "′", "″", "’", "”", ",", ";", "\t", "\n":
                cleaned.append(" ")
            case "N", "S", "E", "W":
                cleaned.append(" \(ch) ")
            default:
                cleaned.append(ch)
            }
        }
        let tokens = cleaned.split(separator: " ").map(String.init)
        guard let first = tokens.first else { return nil }
        let isLetter: (String) -> Bool = { $0.count == 1 && "NSEW".contains($0) }

        var groups: [Group] = []
        if tokens.contains(where: isLetter) {
            if isLetter(first) {
                // Prefix form: "N 52 13 47 E 21 0 44".
                for token in tokens {
                    if isLetter(token) {
                        groups.append(([], Character(token)))
                    } else if let v = Double(token), !groups.isEmpty {
                        groups[groups.count - 1].numbers.append(v)
                    } else {
                        return nil
                    }
                }
            } else {
                // Suffix form: "52 13 47 N 21 0 44 E" (a trailing group may omit its letter).
                var current: [Double] = []
                for token in tokens {
                    if isLetter(token) {
                        guard !current.isEmpty else { return nil }
                        groups.append((current, Character(token)))
                        current = []
                    } else if let v = Double(token) {
                        current.append(v)
                    } else {
                        return nil
                    }
                }
                if !current.isEmpty { groups.append((current, nil)) }
            }
        } else {
            // No letters: split evenly (2 decimals, or 4 / 6 numbers of DM / DMS).
            var numbers: [Double] = []
            for token in tokens {
                guard let v = Double(token) else { return nil }
                numbers.append(v)
            }
            guard [2, 4, 6].contains(numbers.count) else { return nil }
            let half = numbers.count / 2
            groups = [(Array(numbers[..<half]), nil), (Array(numbers[half...]), nil)]
        }
        guard groups.count == 2, var lat = value(groups[0]), var lon = value(groups[1]) else { return nil }
        // Letters may come in either order ("21E 52N").
        if let h0 = groups[0].hemisphere, let h1 = groups[1].hemisphere {
            guard "NS".contains(h0) != "NS".contains(h1) else { return nil }
            if "EW".contains(h0) { swap(&lat, &lon) }
        }
        guard abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return (lat, lon)
    }

    private static func value(_ group: Group) -> Double? {
        let n = group.numbers
        guard (1...3).contains(n.count) else { return nil }
        if n.count > 1 {
            guard n[0] == n[0].rounded(), (0..<60).contains(n[1]) else { return nil }
        }
        if n.count == 3 {
            guard n[1] == n[1].rounded(), (0..<60).contains(n[2]) else { return nil }
        }
        let magnitude = abs(n[0]) + (n.count > 1 ? n[1] / 60 : 0) + (n.count > 2 ? n[2] / 3600 : 0)
        let negative = n[0].sign == .minus || group.hemisphere == "S" || group.hemisphere == "W"
        return negative ? -magnitude : magnitude
    }
}
