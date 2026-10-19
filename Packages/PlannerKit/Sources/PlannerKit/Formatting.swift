// Packages/PlannerKit/Sources/PlannerKit/Formatting.swift
//
// Display-agnostic formatting of the values the Planner and Pills show: angles, compass
// points, coordinates, distances, durations and clock times in the pin's time zone.
// Output is deterministic (ASCII digits, no locale grouping) so it can be unit tested;
// the app layer may wrap these for full localisation later.

import Foundation

public enum UnitSystem: String, Sendable, CaseIterable, Codable {
    case metric
    case imperial
}

public enum ClockStyle: String, Sendable, CaseIterable, Codable {
    case twentyFourHour
    case twelveHour
}

public enum CoordinateStyle: String, Sendable, CaseIterable, Codable {
    /// 52.22970° N, 21.01220° E
    case decimal
    /// 52°13'46.9" N, 21°00'43.9" E
    case degreesMinutesSeconds
}

public enum Formatting {
    // MARK: Angles

    /// "123.4°"
    public static func degrees(_ value: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f°", value)
    }

    private static let compassNames = [
        "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
        "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW",
    ]

    /// 16-point compass name for an azimuth in degrees east of north.
    public static func compassPoint(azimuth: Double) -> String {
        var a = azimuth.truncatingRemainder(dividingBy: 360)
        if a < 0 { a += 360 }
        let index = Int((a / 22.5).rounded()) % 16
        return compassNames[index]
    }

    /// "123.4° SE"
    public static func azimuth(_ value: Double, decimals: Int = 1) -> String {
        var a = value.truncatingRemainder(dividingBy: 360)
        if a < 0 { a += 360 }
        return "\(degrees(a, decimals: decimals)) \(compassPoint(azimuth: a))"
    }

    // MARK: Coordinates

    public static func coordinate(latitude: Double, longitude: Double, style: CoordinateStyle) -> String {
        let ns = latitude >= 0 ? "N" : "S"
        let ew = longitude >= 0 ? "E" : "W"
        switch style {
        case .decimal:
            return String(format: "%.5f° %@, %.5f° %@", abs(latitude), ns, abs(longitude), ew)
        case .degreesMinutesSeconds:
            return "\(dms(abs(latitude), degreeDigits: 2)) \(ns), \(dms(abs(longitude), degreeDigits: 3)) \(ew)"
        }
    }

    private static func dms(_ value: Double, degreeDigits: Int) -> String {
        // Round to 0.1" first so 59.96" carries into the minutes.
        let tenths = Int((value * 36_000).rounded())
        let d = tenths / 36_000
        let m = (tenths % 36_000) / 600
        let s = Double(tenths % 600) / 10
        return String(format: "%0\(degreeDigits)d°%02d'%04.1f\"", d, m, s)
    }

    // MARK: Distances

    /// Short distances in m / ft, long ones in km / mi.
    public static func distance(meters: Double, units: UnitSystem) -> String {
        switch units {
        case .metric:
            if meters < 1000 { return String(format: "%.0f m", meters) }
            return String(format: meters < 10_000 ? "%.2f km" : "%.1f km", meters / 1000)
        case .imperial:
            let feet = meters / 0.3048
            if feet < 1000 { return String(format: "%.0f ft", feet) }
            let miles = meters / 1609.344
            return String(format: miles < 10 ? "%.2f mi" : "%.1f mi", miles)
        }
    }

    /// Heights/elevations: always m or ft.
    public static func height(meters: Double, units: UnitSystem) -> String {
        switch units {
        case .metric: return String(format: "%.0f m", meters)
        case .imperial: return String(format: "%.0f ft", meters / 0.3048)
        }
    }

    // MARK: Time

    /// "12h 07m" (rounded to the minute), "45m 10s" or "8s". Negative durations get a leading minus.
    public static func duration(seconds: Double) -> String {
        let sign = seconds < 0 ? "-" : ""
        let total = Int(abs(seconds).rounded())
        if total >= 3600 - 30 {
            let minutes = Int((abs(seconds) / 60).rounded())
            return String(format: "%@%dh %02dm", sign, minutes / 60, minutes % 60)
        }
        let m = total / 60, s = total % 60
        if m > 0 { return String(format: "%@%dm %02ds", sign, m, s) }
        return "\(sign)\(s)s"
    }

    /// Clock time of `date` in `timeZone` (the pin's zone, not the device's), to the minute.
    /// Rounds to the nearest minute, as almanacs do.
    public static func clockTime(_ date: Date, timeZone: TimeZone, style: ClockStyle) -> String {
        let rounded = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: rounded)
        let hour = c.hour ?? 0, minute = c.minute ?? 0
        switch style {
        case .twentyFourHour:
            return String(format: "%02d:%02d", hour, minute)
        case .twelveHour:
            let h12 = hour % 12 == 0 ? 12 : hour % 12
            return String(format: "%d:%02d %@", h12, minute, hour < 12 ? "AM" : "PM")
        }
    }

    /// UTC offset label for the zone at `date`, e.g. "UTC+2", "UTC-9:30".
    public static func utcOffset(_ timeZone: TimeZone, at date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let h = abs(seconds) / 3600, m = (abs(seconds) % 3600) / 60
        return m == 0 ? "UTC\(sign)\(h)" : String(format: "UTC%@%d:%02d", sign, h, m)
    }
}
