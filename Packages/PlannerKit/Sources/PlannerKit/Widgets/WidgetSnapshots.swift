// Packages/PlannerKit/Sources/PlannerKit/Widgets/WidgetSnapshots.swift
//
// What the home-screen and lock-screen widgets show, computed for one place and instant:
// the Sun's light phase and next events, the Moon's phase and next rise or set, tonight's
// Milky Way core window, and the next saved plan. Widget timelines call these for each entry;
// the views only lay them out.

import AstroCore
import Foundation

/// One upcoming moment on a widget.
public struct WidgetEvent: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case sunrise, sunset, goldenHourStart, goldenHourEnd, blueHourStart, blueHourEnd, moonrise, moonset

        public var label: String {
            switch self {
            case .sunrise: "Sunrise"
            case .sunset: "Sunset"
            case .goldenHourStart: "Golden hour"
            case .goldenHourEnd: "Golden hour ends"
            case .blueHourStart: "Blue hour"
            case .blueHourEnd: "Blue hour ends"
            case .moonrise: "Moonrise"
            case .moonset: "Moonset"
            }
        }

        public var systemImage: String {
            switch self {
            case .sunrise: "sunrise.fill"
            case .sunset: "sunset.fill"
            case .goldenHourStart, .goldenHourEnd: "sun.horizon.fill"
            case .blueHourStart, .blueHourEnd: "moon.haze.fill"
            case .moonrise: "moonrise.fill"
            case .moonset: "moonset.fill"
            }
        }
    }

    public let kind: Kind
    public let time: Date

    public init(kind: Kind, time: Date) {
        self.kind = kind
        self.time = time
    }
}

public struct SunWidgetSnapshot: Sendable, Hashable {
    public let place: String
    public let timeZone: TimeZone
    public let instant: Date
    public let altitude: Double
    public let azimuth: Double
    public let lightPhase: LightPhase
    /// The next sunrise, sunset, golden-hour and blue-hour moments, soonest first (up to 4).
    public let upcoming: [WidgetEvent]
    /// The golden or blue hour under way at the instant, if any.
    public let current: DateInterval?

    public var next: WidgetEvent? { upcoming.first }

    public static func compute(location: PillLocation, instant: Date) -> SunWidgetSnapshot {
        let today = LocalDay(containing: instant, timeZone: location.timeZone)
        var events: [WidgetEvent] = []
        var bands: [DateInterval] = []
        for day in [today, today.adding(days: 1)] {
            let sun = SunDayReport.compute(location: location, day: day, instant: instant)
            let twilight = TwilightReport.compute(location: location, day: day)
            events += sun.rises.map { WidgetEvent(kind: .sunrise, time: $0.time) }
            events += sun.sets.map { WidgetEvent(kind: .sunset, time: $0.time) }
            // Morning bands: blue then golden; evening: golden then blue. Mark the start of
            // each evening band and the end of each morning band, the moments to be ready for.
            for band in twilight.morningBlueHours { events.append(WidgetEvent(kind: .blueHourStart, time: band.start)) }
            for band in twilight.morningGoldenHours { events.append(WidgetEvent(kind: .goldenHourEnd, time: band.end)) }
            for band in twilight.eveningGoldenHours { events.append(WidgetEvent(kind: .goldenHourStart, time: band.start)) }
            for band in twilight.eveningBlueHours { events.append(WidgetEvent(kind: .blueHourEnd, time: band.end)) }
            bands += twilight.goldenHours + twilight.blueHours
        }
        let upcoming = events.filter { $0.time > instant }.sorted { $0.time < $1.time }
        let now = SunDayReport.compute(location: location, day: today, instant: instant)
        return SunWidgetSnapshot(place: location.name, timeZone: location.timeZone, instant: instant,
                                 altitude: now.position.altitude, azimuth: now.position.azimuth, lightPhase: now.lightPhase,
                                 upcoming: Array(Self.dedupe(upcoming).prefix(4)),
                                 current: bands.first { $0.contains(instant) })
    }

    /// Bands clipped at midnight produce an extra start or end at 00:00; keep one per minute.
    private static func dedupe(_ events: [WidgetEvent]) -> [WidgetEvent] {
        var seen = Set<String>()
        return events.filter { seen.insert("\($0.kind.rawValue)-\(Int($0.time.timeIntervalSince1970 / 60))").inserted }
    }
}

public struct MoonWidgetSnapshot: Sendable, Hashable {
    public let place: String
    public let timeZone: TimeZone
    public let instant: Date
    public let phaseName: MoonPhaseName
    public let illumination: Double
    /// Moon minus Sun ecliptic longitude: 0 new, 180 full.
    public let elongation: Double
    public let isSouthern: Bool
    public let altitude: Double
    public let azimuth: Double
    /// The next moonrise and moonset, soonest first.
    public let upcoming: [WidgetEvent]
    public let nextFull: Date?
    public let nextNew: Date?

    public static func compute(location: PillLocation, instant: Date) -> MoonWidgetSnapshot {
        let today = LocalDay(containing: instant, timeZone: location.timeZone)
        let report = MoonDayReport.compute(location: location, day: today, instant: instant)
        let tomorrow = MoonDayReport.compute(location: location, day: today.adding(days: 1), instant: instant)
        var events: [WidgetEvent] = []
        for day in [report, tomorrow] {
            events += day.rises.map { WidgetEvent(kind: .moonrise, time: $0.time) }
            events += day.sets.map { WidgetEvent(kind: .moonset, time: $0.time) }
        }
        return MoonWidgetSnapshot(place: location.name, timeZone: location.timeZone, instant: instant,
                                  phaseName: report.phaseName, illumination: report.illumination,
                                  elongation: report.elongation, isSouthern: location.latitude < 0,
                                  altitude: report.position.altitude, azimuth: report.position.azimuth,
                                  upcoming: events.filter { $0.time > instant }.sorted { $0.time < $1.time },
                                  nextFull: report.nextFull?.time, nextNew: report.nextNew?.time)
    }
}

public struct MilkyWayWidgetSnapshot: Sendable, Hashable {
    public let place: String
    public let timeZone: TimeZone
    public let instant: Date
    /// The night shown: tonight, or the next night with the core up in a dark sky.
    public let night: LocalDay
    public let isTonight: Bool
    /// Core visible and the Moon down or dim, still to come or under way.
    public let window: DateInterval?
    public let best: GalacticCenterSample?
    public let moonInterference: MoonInterference
    public let moonIllumination: Double

    /// The night containing `instant` (before local noon, the previous date's night); if the
    /// core is not visible then, the next night within `searchNights` when it is.
    public static func compute(location: PillLocation, instant: Date, searchNights: Int = 21) -> MilkyWayWidgetSnapshot {
        let zone = location.timeZone
        let day = LocalDay(containing: instant, timeZone: zone)
        var night = instant < day.noon ? day.adding(days: -1) : day
        var report = MilkyWayNightReport.compute(location: location, day: night)
        var isTonight = true
        func remaining(_ r: MilkyWayNightReport) -> DateInterval? {
            (r.moonFree.isEmpty ? r.visible : r.moonFree).first { $0.end > instant }
        }
        var window = remaining(report)
        if window == nil {
            for _ in 0..<searchNights {
                night = night.adding(days: 1)
                report = MilkyWayNightReport.compute(location: location, day: night)
                isTonight = false
                if let next = remaining(report) {
                    window = next
                    break
                }
            }
        }
        return MilkyWayWidgetSnapshot(place: location.name, timeZone: zone, instant: instant, night: night,
                                      isTonight: isTonight && window != nil, window: window,
                                      best: window == nil ? nil : report.bestMoment,
                                      moonInterference: report.moonInterference, moonIllumination: report.moonIllumination)
    }
}

/// A saved plan as the widget sees it; the app writes the upcoming ones to the shared store.
public struct WidgetPlan: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let place: String
    public let timeZoneID: String
    public let instant: Date
    /// "Golden hour", "Night", … at the plan's moment.
    public let light: String
    public let sunAzimuth: Double
    public let sunAltitude: Double

    public init(_ plan: Plan) {
        id = plan.id
        name = plan.name
        place = plan.location.name
        timeZoneID = plan.location.timeZoneIdentifier
        instant = plan.instant
        let sun = SunDayReport.compute(location: plan.location,
                                       day: LocalDay(containing: plan.instant, timeZone: plan.location.timeZone),
                                       instant: plan.instant)
        light = sun.lightPhase.label
        sunAzimuth = sun.position.azimuth
        sunAltitude = sun.position.altitude
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .gmt }

    /// The first plan still to come.
    public static func next(_ plans: [WidgetPlan], after instant: Date) -> WidgetPlan? {
        plans.filter { $0.instant > instant }.min { $0.instant < $1.instant }
    }
}
