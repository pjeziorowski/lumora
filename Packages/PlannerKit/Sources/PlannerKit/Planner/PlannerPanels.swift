// Packages/PlannerKit/Sources/PlannerKit/Planner/PlannerPanels.swift
//
// The Planner's information panels as ready-to-display rows. Phase 3 ships panels 1–4
// (pin, Sun, Moon, twilights); later phases append Milky Way, geodetics and so on. Times
// are shown in the pin's zone unless the user switches to device time.

import AstroCore
import Foundation

public enum PlannerPanelKind: String, Sendable, Hashable, CaseIterable, Identifiable {
    case pin, sun, moon, twilights
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pin: "Pin"
        case .sun: "Sun"
        case .moon: "Moon"
        case .twilights: "Twilights"
        }
    }
}

public struct PanelRow: Sendable, Hashable, Identifiable {
    public let label: String
    public let value: String
    public var id: String { label }

    public init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

public struct PlannerPanel: Sendable, Hashable, Identifiable {
    public let kind: PlannerPanelKind
    public let rows: [PanelRow]
    public var id: PlannerPanelKind { kind }
}

public struct PlannerDisplayOptions: Sendable, Hashable {
    public var clock: ClockStyle
    public var units: UnitSystem
    public var coordinates: CoordinateStyle
    /// Show times in the device's zone instead of the pin's.
    public var useDeviceTimeZone: Bool
    public var deviceTimeZone: TimeZone

    public init(clock: ClockStyle = .twentyFourHour, units: UnitSystem = .metric, coordinates: CoordinateStyle = .decimal,
                useDeviceTimeZone: Bool = false, deviceTimeZone: TimeZone = .current) {
        self.clock = clock
        self.units = units
        self.coordinates = coordinates
        self.useDeviceTimeZone = useDeviceTimeZone
        self.deviceTimeZone = deviceTimeZone
    }
}

public enum PlannerPanels {
    public static func panel(_ kind: PlannerPanelKind, snapshot s: PlannerSnapshot, instant: Date,
                             options o: PlannerDisplayOptions) -> PlannerPanel {
        let zone = o.useDeviceTimeZone ? o.deviceTimeZone : s.location.timeZone
        func time(_ d: Date) -> String { Formatting.clockTime(d, timeZone: zone, style: o.clock) }
        func event(_ e: SkyEvent) -> String { "\(time(e.time)) · \(Formatting.azimuth(e.azimuth))" }
        func events(_ list: [SkyEvent], _ state: PolarState, _ body: String) -> String {
            if !list.isEmpty { return list.map(event).joined(separator: ", ") }
            switch state {
            case .alwaysAbove: return "\(body) up all day"
            case .alwaysBelow: return "\(body) down all day"
            case .normal: return "None today"
            }
        }
        func spans(_ list: [DateInterval]) -> String {
            list.isEmpty ? "—" : list.map { "\(time($0.start))–\(time($0.end))" }.joined(separator: ", ")
        }
        func times(_ list: [Date]) -> String { list.isEmpty ? "—" : list.map(time).joined(separator: ", ") }
        func position(_ b: BodyNow) -> String {
            "\(Formatting.azimuth(b.azimuth)) · el \(Formatting.degrees(b.altitude))"
        }

        let day = s.day
        var rows: [PanelRow]
        switch kind {
        case .pin:
            let pinZone = s.location.timeZone
            rows = [
                PanelRow("Place", s.location.name),
                PanelRow("Coordinates", Formatting.coordinate(latitude: s.location.latitude, longitude: s.location.longitude,
                                                              style: o.coordinates)),
                PanelRow("Elevation", Formatting.height(meters: s.location.elevation, units: o.units)),
                PanelRow("Time zone", "\(s.location.timeZoneIdentifier) (\(Formatting.utcOffset(pinZone, at: instant)))"),
                PanelRow("Pin time", stamp(instant, zone: pinZone, clock: o.clock)),
            ]
            let device = o.deviceTimeZone
            if o.useDeviceTimeZone || device.secondsFromGMT(for: instant) != pinZone.secondsFromGMT(for: instant) {
                rows.append(PanelRow("Device time",
                                     "\(stamp(instant, zone: device, clock: o.clock)) (\(Formatting.utcOffset(device, at: instant)))"))
            }
        case .sun:
            rows = [
                PanelRow("Position", position(s.sun)),
                PanelRow("Light", s.lightPhase.label),
                PanelRow("Sunrise", events(day.sunRises, day.sunState, "Sun")),
                PanelRow("Sunset", events(day.sunSets, day.sunState, "Sun")),
                PanelRow("Solar noon", day.solarNoon.map { "\(time($0.time)) · el \(Formatting.degrees($0.altitude))" } ?? "—"),
                PanelRow("Daylight", Formatting.duration(seconds: day.daylightSeconds)),
                PanelRow("Shadow ratio",
                         s.shadowRatio.map { $0 > 99 ? "> 99 : 1" : String(format: "%.2f : 1", $0) } ?? "Sun down"),
                PanelRow("Distance", String(format: "%.4f AU", s.sun.distanceKm / AstroConstants.kmPerAU)),
            ]
        case .moon:
            let m = s.moon
            rows = [
                PanelRow("Position", position(m.position)),
                PanelRow("Phase", "\(m.phaseName.displayName), \(Int((m.illumination * 100).rounded()))% lit"),
                PanelRow("Age", String(format: "%.1f days", m.ageDays)),
                PanelRow("Moonrise", events(day.moonRises, day.moonState, "Moon")),
                PanelRow("Moonset", events(day.moonSets, day.moonState, "Moon")),
                PanelRow("Distance", String(format: "%.0f km", m.position.distanceKm)),
                PanelRow("Size", m.size.map(\.label) ?? "Not near new or full"),
            ]
        case .twilights:
            let t = day.twilight
            func row(_ kind: TwilightKind) -> TwilightRow? { t.rows.first { $0.kind == kind } }
            rows = [
                PanelRow("Astronomical dawn", times(row(.astronomical)?.morning ?? [])),
                PanelRow("Nautical dawn", times(row(.nautical)?.morning ?? [])),
                PanelRow("Blue hour (am)", spans(t.morningBlueHours)),
                PanelRow("Golden hour (am)", spans(t.morningGoldenHours)),
                PanelRow("Golden hour (pm)", spans(t.eveningGoldenHours)),
                PanelRow("Blue hour (pm)", spans(t.eveningBlueHours)),
                PanelRow("Nautical dusk", times(row(.nautical)?.evening ?? [])),
                PanelRow("Astronomical dusk", times(row(.astronomical)?.evening ?? [])),
            ]
            if t.darkness != .fullNight {
                rows.append(PanelRow("Night", t.darkness.label))
            }
        }
        return PlannerPanel(kind: kind, rows: rows)
    }

    public static func all(snapshot: PlannerSnapshot, instant: Date, options: PlannerDisplayOptions) -> [PlannerPanel] {
        PlannerPanelKind.allCases.map { panel($0, snapshot: snapshot, instant: instant, options: options) }
    }

    /// "Sun 21 Jun 20:30"
    static func stamp(_ date: Date, zone: TimeZone, clock: ClockStyle) -> String {
        "\(dateLabel(date, zone: zone)) \(Formatting.clockTime(date, timeZone: zone, style: clock))"
    }

    /// "Sun 21 Jun" in `zone`, ASCII and locale-independent.
    static func dateLabel(_ date: Date, zone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.weekday, .day, .month], from: date)
        let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(weekdays[((c.weekday ?? 1) - 1) % 7]) \(c.day ?? 1) \(months[((c.month ?? 1) - 1) % 12])"
    }
}

extension LightPhase {
    public var label: String {
        switch self {
        case .night: "Night"
        case .astronomicalTwilight: "Astronomical twilight"
        case .nauticalTwilight: "Nautical twilight"
        case .blueHour: "Blue hour"
        case .goldenHour: "Golden hour"
        case .day: "Daylight"
        }
    }
}

extension MoonSize {
    public var label: String {
        switch self {
        case .supermoon: "Supermoon"
        case .micromoon: "Micromoon"
        case .regular: "Regular"
        }
    }
}

extension NightDarkness {
    public var label: String {
        switch self {
        case .fullNight: "Full night"
        case .astronomicalTwilightAllNight: "No astronomical night"
        case .nauticalTwilightAllNight: "Nautical twilight all night"
        case .civilTwilightAllNight: "Civil twilight all night"
        case .midnightSun: "Midnight sun"
        }
    }
}
