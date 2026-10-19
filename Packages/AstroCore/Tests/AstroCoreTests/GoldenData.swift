// Packages/AstroCore/Tests/AstroCoreTests/GoldenData.swift
//
// Loaders for the golden reference tables in Golden/. See Golden/README.md for provenance.

import Foundation
@testable import AstroCore

enum Golden {
    static func url(_ name: String, _ ext: String) -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Golden") else {
            fatalError("Missing golden file \(name).\(ext)")
        }
        return url
    }

    static func lines(_ name: String) -> [String] {
        let text = (try? String(contentsOf: url(name, "txt"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// Parses "2025-03-20T09:01Z", "2025-03-20T09:01:00Z" or "...:00.000Z" as UTC.
    static func time(_ text: String) -> AstroTime {
        var s = text
        if s.hasSuffix("Z") { s.removeLast() }
        let dateTime = s.split(separator: "T")
        let ymd = dateTime[0].split(separator: "-").compactMap { Int($0) }
        var hour = 0, minute = 0, second = 0.0
        if dateTime.count > 1 {
            let hms = dateTime[1].split(separator: ":")
            hour = Int(hms[0]) ?? 0
            minute = Int(hms[1]) ?? 0
            if hms.count > 2 { second = Double(hms[2]) ?? 0 }
        }
        return AstroTime(year: ymd[0], month: ymd[1], day: ymd[2], hour: hour, minute: minute, second: second)
    }

    // MARK: cities.json (Skyfield + JPL DE421, USNO definitions)

    struct CityFile: Decodable {
        let source: String
        let rows: [CityRow]
    }

    struct CityRow: Decodable {
        let city: String
        let latitude: Double
        let longitude: Double
        let timeZone: String
        let localDate: String
        let sunRise: [String]
        let sunSet: [String]
        let moonRise: [String]
        let moonSet: [String]
        let twilight: [String: TwilightPair]
        let sunAltitudeAtLocalNoon: Double
        let samples: [Sample]

        var observer: Observer { Observer(latitude: latitude, longitude: longitude, height: 0) }

        /// UTC instants of local midnight at the start and end of `localDate` in `timeZone`.
        var localDayWindow: (AstroTime, AstroTime) {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: timeZone)!
            let parts = localDate.split(separator: "-").compactMap { Int($0) }
            let start = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            return (AstroTime(start), AstroTime(end))
        }
    }

    struct TwilightPair: Decodable {
        let dawn: [String]
        let dusk: [String]
    }

    struct Sample: Decodable {
        let body: String
        let utc: String
        let azimuth: Double?
        let altitudeAirless: Double?
        let altitudeRefracted: Double?
        let distanceKm: Double?
        let fraction: Double?
    }

    static let cities: CityFile = {
        do {
            let data = try Data(contentsOf: url("cities", "json"))
            return try JSONDecoder().decode(CityFile.self, from: data)
        } catch {
            fatalError("Cannot load golden cities.json: \(error)")
        }
    }()
}

/// Accumulates absolute errors for an accuracy report.
struct ErrorStats: CustomStringConvertible {
    let name: String
    let unit: String
    private(set) var values: [Double] = []
    private(set) var worst = ""

    init(_ name: String, unit: String) {
        self.name = name
        self.unit = unit
    }

    mutating func add(_ error: Double, _ label: @autoclosure () -> String) {
        if error > (values.max() ?? -1) { worst = label() }
        values.append(error)
    }

    var count: Int { values.count }
    var max: Double { values.max() ?? 0 }
    var mean: Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }

    var description: String {
        String(format: "%@: n=%d  mean=%.3f %@  max=%.3f %@  (worst: %@)", name, count, mean, unit, max, unit, worst)
    }
}

enum Report {
    /// Prints a line prefixed so it is easy to grep from `swift test` output.
    static func line(_ s: CustomStringConvertible) {
        print("ACCURACY | \(s)")
    }
}

func angleDiff(_ a: Double, _ b: Double) -> Double {
    abs(longitudeOffset(a - b))
}
