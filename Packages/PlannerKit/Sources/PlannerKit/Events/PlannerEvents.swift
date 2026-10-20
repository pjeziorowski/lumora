// Packages/PlannerKit/Sources/PlannerKit/Events/PlannerEvents.swift
//
// Meteor showers and eclipses for the Planner (panels 8 and 9, the radiant on the map and
// the centre line of the next central solar eclipse). Computed per place and night, off the
// main actor; the radiant's position at the selected instant is cheap and done on demand.

import AstroCore
import Foundation
import GeoCore

public struct PlannerEvents: Sendable, Hashable {
    public let location: PillLocation
    /// The local date the night starts on.
    public let night: LocalDay
    /// Showers active that night, strongest first, with their peaks.
    public let active: [ActiveShower]
    /// The strongest active shower's night, hour by hour.
    public let meteorNight: MeteorNightReport?
    /// When nothing is active: the next shower to peak.
    public let nextShower: ActiveShower?
    /// Eclipses that can be seen from here, next first (up to two).
    public let visibleEclipses: [EclipseSummary]
    /// The next total or annular solar eclipse anywhere, with its centre line.
    public let nextCentral: EclipseSummary?
    public let centralLine: [GeoPoint]

    public struct ActiveShower: Sendable, Hashable {
        public let shower: MeteorShower
        public let peak: Date
    }

    public static func == (a: PlannerEvents, b: PlannerEvents) -> Bool { a.location == b.location && a.night == b.night }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(location)
        hasher.combine(night)
    }

    /// Stops searching early, returning what it has, when the calling task is cancelled.
    public static func compute(location: PillLocation, instant: Date) -> PlannerEvents {
        let zone = location.timeZone
        let night = MeteorShowerCalendar.night(containing: instant, timeZone: zone)
        let middle = night.noon.addingTimeInterval(12 * 3600)
        let active = MeteorShowerCalendar.active(at: middle, timeZone: zone).map { ActiveShower(shower: $0.shower, peak: $0.peak) }
        let meteorNight = active.first.map { MeteorNightReport.compute(shower: $0.shower, location: location, day: night) }
        var next: ActiveShower?
        if active.isEmpty {
            let time = AstroTime(middle)
            next = MeteorShowers.all.compactMap { shower -> ActiveShower? in
                SolarLongitude.search(shower.peakSolarLongitude, after: time, limitDays: 366)
                    .map { ActiveShower(shower: shower, peak: $0.date) }
            }
            .min { $0.peak < $1.peak }
        }
        let start = night.noon
        let visible = Array(EclipseCalendar.nextVisible(location: location, from: start, years: 4).prefix(2))
        var central: EclipseSummary?
        var line: [GeoPoint] = []
        var t = AstroTime(start)
        for _ in 0..<8 where !Task.isCancelled {
            guard let e = Eclipses.nextGlobalSolarEclipse(after: t) else { break }
            if e.latitude != nil, e.kind == .total || e.kind == .annular {
                central = EclipseCalendar.summary(e, observer: location.observer)
                line = Eclipses.centralLine(of: e).map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) }
                break
            }
            t = e.peak.addingDays(10)
        }
        return PlannerEvents(location: location, night: night, active: active, meteorNight: meteorNight, nextShower: next,
                             visibleEclipses: visible, nextCentral: central, centralLine: line)
    }

    /// The strongest active shower's radiant at `instant`.
    public func radiant(at instant: Date) -> BodyNow? {
        guard let shower = active.first?.shower else { return nil }
        let time = AstroTime(instant)
        let h = FixedSky.horizontal(shower.radiant(atSolarLongitude: SolarLongitude.j2000(at: time)), at: time,
                                    observer: location.observer)
        return BodyNow(azimuth: h.azimuth, altitude: h.altitude, distanceKm: 0)
    }

    // MARK: Panels

    func meteorRows(instant: Date, moon: MoonNow, time: (Date) -> String, zone: TimeZone) -> [PanelRow] {
        guard let first = active.first, let report = meteorNight else {
            var rows = [PanelRow("Active showers", "None tonight")]
            if let next = nextShower {
                rows.append(PanelRow("Next", "\(next.shower.name), \(Self.date(next.peak, zone: zone))"))
                rows.append(PanelRow("ZHR at peak", "\(Int(next.shower.zhr))"))
            }
            return rows
        }
        var rows = [
            PanelRow("Shower", "\(first.shower.name) · ZHR \(Int(first.shower.zhr))"),
            PanelRow("Peak", "\(Self.date(first.peak, zone: zone)) \(time(first.peak))"),
        ]
        if let radiant = radiant(at: instant) {
            rows.append(PanelRow("Radiant", "\(Formatting.azimuth(radiant.azimuth)) · \(Formatting.degrees(radiant.altitude))"
                                 + (radiant.isUp ? "" : " (below horizon)")))
        }
        let now = report.samples.min { abs($0.time.timeIntervalSince(instant)) < abs($1.time.timeIntervalSince(instant)) }
        rows.append(PanelRow("Rate now", now.map { $0.rate > 0 ? "≈ \(Int($0.rate.rounded())) per hour" : "None (sky or radiant)" } ?? "—"))
        if let best = report.best {
            rows.append(PanelRow("Best tonight", "\(time(best.time)) · ≈ \(Int(best.rate.rounded())) per hour (\(report.rating.label))"))
        } else {
            rows.append(PanelRow("Best tonight", "Radiant not up in a dark sky"))
        }
        rows.append(PanelRow("Moon", "\(Int((report.moonIllumination * 100).rounded()))% lit, \(moon.position.isUp ? "up" : "down") now"))
        if active.count > 1 {
            rows.append(PanelRow("Also active", active.dropFirst().map(\.shower.name).joined(separator: ", ")))
        }
        return rows
    }

    func eclipseRows(time: (Date) -> String, zone: TimeZone) -> [PanelRow] {
        guard let next = visibleEclipses.first else {
            var rows = [PanelRow("Next here", "None in the next 4 years")]
            if let central = nextCentral {
                rows.append(PanelRow("Next central", "\(central.globalTitle), \(Self.date(central.peak, zone: zone))"))
            }
            return rows
        }
        var rows = [PanelRow("Next here", next.title), PanelRow("Date", Self.date(next.peak, zone: zone))]
        let shown = next.contacts.filter { next.body == .sun || next.kind == .penumbral || !$0.phase.isPenumbral }
        for contact in shown {
            rows.append(PanelRow(contact.label, "\(time(contact.time)) · \(Formatting.degrees(contact.altitude, decimals: 0))"))
        }
        if let magnitude = next.magnitude, let obscuration = next.obscuration, next.localKind == .partial {
            rows.append(PanelRow("Coverage", "\(Int((obscuration * 100).rounded()))% of the Sun (magnitude "
                                 + String(format: "%.2f", magnitude) + ")"))
        }
        if visibleEclipses.count > 1 {
            let after = visibleEclipses[1]
            rows.append(PanelRow("After that", "\(after.title), \(Self.date(after.peak, zone: zone))"))
        }
        if let central = nextCentral {
            rows.append(PanelRow("Centre line on map", "\(central.globalTitle), \(Self.date(central.peak, zone: zone))"))
        }
        return rows
    }

    /// "12 Aug 2026", ASCII and locale-independent.
    static func date(_ date: Date, zone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.day, .month, .year], from: date)
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(c.day ?? 1) \(months[((c.month ?? 1) - 1) % 12]) \(c.year ?? 0)"
    }

    // MARK: Map

    /// The radiant's direction from the pin and the eclipse centre line.
    public func overlays(instant: Date, radius: Double, layers: PlannerLayers) -> PlannerOverlays {
        var lines: [OverlayLine] = []
        var markers: [OverlayMarker] = []
        let pin = location.geoPoint
        if layers.contains(.meteors), let radiant = radiant(at: instant) {
            let end = Geodesy.destination(from: pin, bearing: radiant.azimuth, distance: radius * 1.15).unwrapped(near: pin.longitude)
            lines.append(OverlayLine(body: .radiant, role: .now, isAboveHorizon: radiant.isUp, points: [pin, end], index: 0))
            markers.append(OverlayMarker(body: .radiant,
                                         point: PlannerOverlays.project(radiant.azimuth, radiant.altitude, pin: pin, radius: radius),
                                         isAboveHorizon: radiant.isUp))
        }
        if layers.contains(.eclipse), centralLine.count > 1 {
            // Split where the line jumps across the antimeridian.
            var run: [GeoPoint] = []
            var index = 0
            for p in centralLine {
                if let last = run.last, abs(p.longitude - last.longitude) > 180 {
                    lines.append(OverlayLine(body: .eclipse, role: .pathUp, isAboveHorizon: true, points: run, index: index))
                    index += 1
                    run = []
                }
                run.append(p)
            }
            if run.count > 1 { lines.append(OverlayLine(body: .eclipse, role: .pathUp, isAboveHorizon: true, points: run, index: index)) }
        }
        return PlannerOverlays(lines: lines, markers: markers)
    }
}
