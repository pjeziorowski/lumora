// Packages/PlannerKit/Sources/PlannerKit/Events/EclipseReports.swift
//
// Eclipses for a place: upcoming solar and lunar eclipses in date order, each with its local
// contact times and the Sun's or Moon's altitude at each, whether any of it can be seen
// from the place, and (for total and annular solar eclipses) the centre line of the path.

import AstroCore
import Foundation
import GeoCore

public struct EclipseContact: Sendable, Hashable, Identifiable {
    /// Which contact this is; logic uses this, never the display label.
    public enum Phase: String, Sendable, Hashable {
        case penumbralBegin, partialBegin, centralBegin, greatest, centralEnd, partialEnd, penumbralEnd

        public var isPenumbral: Bool { self == .penumbralBegin || self == .penumbralEnd }
    }

    public let phase: Phase
    public let label: String
    public let time: Date
    /// Altitude of the eclipsed body (Sun or Moon) in degrees.
    public let altitude: Double
    public var id: Phase { phase }
}

public struct EclipseSummary: Sendable, Hashable, Identifiable {
    public enum Body: String, Sendable, Hashable { case sun, moon }

    public let body: Body
    public let kind: EclipseKind
    /// Greatest eclipse (global for lunar eclipses; local for a solar eclipse seen here).
    public let peak: Date
    /// Something of the eclipse can be seen from the place.
    public let visibleHere: Bool
    /// Local contacts, in time order; empty for a solar eclipse not seen here.
    public let contacts: [EclipseContact]
    /// Solar: fraction of the Sun's diameter covered here. Lunar: umbral obscuration.
    public let magnitude: Double?
    public let obscuration: Double?
    /// Where the shadow axis meets the Earth at greatest eclipse (central solar eclipses).
    public let greatestPoint: GeoPoint?
    public var id: String { "\(body.rawValue)-\(Int(peak.timeIntervalSince1970))" }

    /// "Total solar eclipse", "Partial lunar eclipse", … as seen here when it is seen here.
    public var title: String { Self.title(localKind ?? kind, body) }

    /// The kind anywhere on Earth: "Total solar eclipse" even where it is only partial.
    public var globalTitle: String { Self.title(kind, body) }

    private static func title(_ kind: EclipseKind, _ body: Body) -> String {
        let kindName: String = switch kind {
        case .penumbral: "Penumbral"
        case .partial: "Partial"
        case .annular: "Annular"
        case .total: "Total"
        }
        return "\(kindName) \(body == .sun ? "solar" : "lunar") eclipse"
    }

    /// For a solar eclipse seen here, the local kind can be milder than the global one.
    public let localKind: EclipseKind?
}

public enum EclipseCalendar {
    /// The next `count` eclipses (solar and lunar) from `start`, in date order.
    public static func upcoming(location: PillLocation, from start: Date, count: Int = 8) -> [EclipseSummary] {
        let observer = location.observer
        var lunar: [EclipseSummary] = []
        var solar: [EclipseSummary] = []
        var t = AstroTime(start)
        while lunar.count < count, !Task.isCancelled, let e = Eclipses.nextLunarEclipse(after: t) {
            lunar.append(summary(e, observer: observer))
            t = e.peak.addingDays(10)
        }
        t = AstroTime(start)
        while solar.count < count, !Task.isCancelled, let e = Eclipses.nextGlobalSolarEclipse(after: t) {
            solar.append(summary(e, observer: observer))
            t = e.peak.addingDays(10)
        }
        return Array((lunar + solar).sorted { $0.peak < $1.peak }.prefix(count))
    }

    /// The next eclipse that can be seen from the place, searching up to `years` ahead.
    public static func nextVisible(location: PillLocation, from start: Date, years: Int = 4) -> [EclipseSummary] {
        let limit = start.addingTimeInterval(Double(years) * 365.25 * 86_400)
        return upcoming(location: location, from: start, count: years * 5).filter { $0.visibleHere && $0.peak < limit }
    }

    static func summary(_ e: LunarEclipse, observer: Observer) -> EclipseSummary {
        let labelled: [(EclipseContact.Phase, String, AstroTime?)] = [
            (.penumbralBegin, "Penumbral begins", e.penumbralBegin), (.partialBegin, "Partial begins", e.partialBegin),
            (.centralBegin, "Total begins", e.totalBegin), (.greatest, "Greatest", e.peak), (.centralEnd, "Total ends", e.totalEnd),
            (.partialEnd, "Partial ends", e.partialEnd), (.penumbralEnd, "Penumbral ends", e.penumbralEnd),
        ]
        let contacts = labelled.compactMap { phase, label, time in
            time.map { EclipseContact(phase: phase, label: label, time: $0.date, altitude: moonAltitude($0, observer)) }
        }
        // Visible when the Moon is up during the umbral phase (or any of a penumbral one).
        let phase = e.kind == .penumbral ? contacts : contacts.filter { !$0.phase.isPenumbral }
        let visible = phase.contains { $0.altitude > 0 } || moonUpBetween(phase, observer)
        return EclipseSummary(body: .moon, kind: e.kind, peak: e.peak.date, visibleHere: visible, contacts: contacts,
                              magnitude: nil, obscuration: e.obscuration, greatestPoint: nil, localKind: nil)
    }

    static func summary(_ e: GlobalSolarEclipse, observer: Observer) -> EclipseSummary {
        let greatest = e.latitude.flatMap { lat in e.longitude.map { GeoPoint(latitude: lat, longitude: $0) } }
        guard let local = Eclipses.nextLocalSolarEclipse(after: e.peak.addingDays(-1), observer: observer, limitDays: 2),
              abs(local.peak.time.ut - e.peak.ut) < 1 else {
            return EclipseSummary(body: .sun, kind: e.kind, peak: e.peak.date, visibleHere: false, contacts: [],
                                  magnitude: nil, obscuration: nil, greatestPoint: greatest, localKind: nil)
        }
        let central = local.kind == .annular ? "Annular" : "Total"
        let labelled: [(EclipseContact.Phase, String, EclipseEvent?)] = [
            (.partialBegin, "Partial begins", local.partialBegin), (.centralBegin, "\(central) begins", local.totalBegin),
            (.greatest, "Greatest", local.peak), (.centralEnd, "\(central) ends", local.totalEnd),
            (.partialEnd, "Partial ends", local.partialEnd),
        ]
        let contacts = labelled.compactMap { phase, label, event in
            event.map { EclipseContact(phase: phase, label: label, time: $0.time.date, altitude: $0.altitude) }
        }
        return EclipseSummary(body: .sun, kind: e.kind, peak: local.peak.time.date, visibleHere: true, contacts: contacts,
                              magnitude: local.magnitude, obscuration: local.obscuration, greatestPoint: greatest,
                              localKind: local.kind)
    }

    static func moonAltitude(_ time: AstroTime, _ observer: Observer) -> Double {
        Ephemeris.horizontal(.moon, at: time, observer: observer).altitude
    }

    /// The Moon can rise and set within a long phase; check every 10 minutes.
    static func moonUpBetween(_ contacts: [EclipseContact], _ observer: Observer) -> Bool {
        guard let first = contacts.first?.time, let last = contacts.last?.time else { return false }
        var t = first
        while t < last {
            if moonAltitude(AstroTime(t), observer) > 0 { return true }
            t = t.addingTimeInterval(600)
        }
        return false
    }

    /// The centre line of a central solar eclipse as map points.
    public static func centralLine(peak: Date) -> [GeoPoint] {
        guard let e = Eclipses.nextGlobalSolarEclipse(after: AstroTime(peak.addingTimeInterval(-86_400 * 2))) else { return [] }
        return Eclipses.centralLine(of: e).map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
