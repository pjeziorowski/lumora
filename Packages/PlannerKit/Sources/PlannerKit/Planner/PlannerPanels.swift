// Packages/PlannerKit/Sources/PlannerKit/Planner/PlannerPanels.swift
//
// The Planner's information panels as ready-to-display rows: pin, Sun, Moon, twilights
// (Phase 3), Milky Way (Phase 4), geodetics and obstacle (Phase 6), meteors and eclipses
// (Phase 9). Times
// are shown in the pin's zone unless the user switches to device time.

import AstroCore
import Foundation

public enum PlannerPanelKind: String, Sendable, Hashable, CaseIterable, Identifiable {
    case pin, sun, moon, twilights, milkyWay, geodetics, obstacle, meteors, eclipse
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pin: "Pin"
        case .sun: "Sun"
        case .moon: "Moon"
        case .twilights: "Twilights"
        case .milkyWay: "Milky Way"
        case .geodetics: "Geodetics"
        case .obstacle: "Obstacle"
        case .meteors: "Meteors"
        case .eclipse: "Eclipses"
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
    /// - Parameters:
    ///   - obstacle: the target pin's report (panels 6 and 7), nil without a target.
    ///   - events: meteor showers and eclipses (panels 8 and 9), nil while computing.
    public static func panel(_ kind: PlannerPanelKind, snapshot s: PlannerSnapshot, instant: Date,
                             options o: PlannerDisplayOptions, obstacle: ObstacleReport? = nil,
                             events sky: PlannerEvents? = nil) -> PlannerPanel {
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
                PanelRow("Daylight", day.daylightSeconds <= 0 ? "None (polar night)"
                    : day.daylightSeconds >= day.day.lengthHours * 3600 - 1 ? "All day (midnight sun)"
                    : Formatting.duration(seconds: day.daylightSeconds)),
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
        case .milkyWay:
            let night = day.night(containing: instant)
            let visible = day.milkyWaySpans(\.visible, night: night)
            let moonFree = day.milkyWaySpans(\.moonFree, night: night)
            let dark = day.milkyWaySpans(\.dark, night: night)
            let orientation = ArcOrientation.of(tilt: s.arcTilt)
            rows = [
                PanelRow("Core", "\(position(s.galacticCenter))\(s.galacticCenter.isUp ? "" : " (below horizon)")"),
                PanelRow("Core visible", visible.isEmpty ? "Not tonight" : spans(visible)),
                PanelRow("Dark sky", dark.isEmpty ? "No astronomical night" : spans(dark)),
                PanelRow("Moon-free", visible.isEmpty ? "—" : (moonFree.isEmpty ? "Moon up all window" : spans(moonFree))),
                PanelRow("Moon", "\(Int((s.moon.illumination * 100).rounded()))% lit, \(s.moon.position.isUp ? "up" : "down")"),
                PanelRow("Arc", s.galacticCenter.isUp ? "\(orientation.label), \(Formatting.degrees(s.arcTilt, decimals: 0))" : "—"),
            ]
        case .geodetics:
            rows = geodeticsRows(obstacle?.geodetics, sun: s.sun, moon: s.moon.position, units: o.units)
        case .obstacle:
            rows = obstacleRows(obstacle, units: o.units, time: time)
        case .meteors:
            rows = sky?.meteorRows(instant: instant, moon: s.moon, time: time, zone: zone) ?? [PanelRow("Meteor showers", "Calculating…")]
        case .eclipse:
            rows = sky?.eclipseRows(time: time, zone: zone) ?? [PanelRow("Eclipses", "Calculating…")]
        }
        return PlannerPanel(kind: kind, rows: rows)
    }

    public static func all(snapshot: PlannerSnapshot, instant: Date, options: PlannerDisplayOptions,
                           obstacle: ObstacleReport? = nil, events: PlannerEvents? = nil) -> [PlannerPanel] {
        PlannerPanelKind.allCases.map {
            panel($0, snapshot: snapshot, instant: instant, options: options, obstacle: obstacle, events: events)
        }
    }

    static let noTarget = [PanelRow("Target pin", "None"), PanelRow("Add one", "Map options → Target pin")]

    static func geodeticsRows(_ g: GeodeticsReport?, sun: BodyNow, moon: BodyNow, units: UnitSystem) -> [PanelRow] {
        guard let g else { return noTarget }
        func height(_ m: Double) -> String { Formatting.height(meters: m, units: units) }
        func signed(_ m: Double) -> String { (m >= 0 ? "+" : "−") + height(abs(m)) }
        func offset(_ body: BodyNow) -> String {
            let d = BodyFinder.wrap(body.azimuth - g.bearing)
            let side = abs(d) < 0.05 ? "on the line" : String(format: "%.1f° %@", abs(d), d < 0 ? "left" : "right")
            return "\(Formatting.azimuth(body.azimuth)), \(side)"
        }
        return [
            PanelRow("Distance", Formatting.distance(meters: g.distance, units: units)),
            PanelRow("Bearing", Formatting.azimuth(g.bearing, decimals: 2)),
            PanelRow("Back bearing", Formatting.azimuth(g.backBearing, decimals: 2)),
            PanelRow("Eye level", height(g.observerHeight)),
            PanelRow("Target ground", g.targetGround.map(height) ?? "Unknown (sea level used)"),
            PanelRow("Height difference", g.heightDifference.map(signed) ?? "—"),
            PanelRow("Apparent angle", Formatting.degrees(g.groundAngle, decimals: 2)),
            PanelRow("Curvature + refraction", "−" + height(g.curvatureDrop)),
            PanelRow("Sun now", offset(sun)),
            PanelRow("Moon now", offset(moon)),
        ]
    }

    static func obstacleRows(_ r: ObstacleReport?, units: UnitSystem, time: (Date) -> String) -> [PanelRow] {
        guard let r else { return noTarget }
        let g = r.geodetics
        func height(_ m: Double) -> String { Formatting.height(meters: m, units: units) }
        var rows = [
            PanelRow("Object height", height(g.objectHeight)),
            PanelRow("Top of object", "\(height(g.topHeight)) above sea level"),
            PanelRow("Angle to top", Formatting.degrees(g.topAngle, decimals: 2)),
        ]
        for body in [FindBody.sun, .moon] {
            let list = r.alignments.filter { $0.body == body }
            let name = body == .sun ? "Sun" : "Moon"
            if list.isEmpty {
                rows.append(PanelRow("\(name) on the line", "Not today (above the horizon)"))
                continue
            }
            for (i, a) in list.enumerated() {
                let suffix = list.count > 1 ? " \(i + 1)" : ""
                let verdict = a.clearance >= 0
                    ? String(format: "clears by %.2f°", a.clearance) : String(format: "hidden by %.2f°", -a.clearance)
                let elevation = Formatting.degrees(a.elevation, decimals: 2)
                rows.append(PanelRow("\(name) on the line\(suffix)", "\(time(a.time)) · el \(elevation) · \(verdict)"))
                rows.append(PanelRow("Height for \(name.lowercased()) on top\(suffix)",
                                     a.heightForAlignment > 0 ? height(a.heightForAlignment) : "Below the target's ground"))
            }
        }
        return rows
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
