// App/Shared/WidgetViews.swift
//
// The widget faces, shared by the widget extension and the app's widget gallery: Sun (light
// now and the next sunrise, sunset, golden and blue hour), Moon (phase and next rise or set),
// Milky Way (tonight's core window) and the next saved plan, each for the home screen (small,
// medium) and the lock screen (circular, rectangular, inline). Numbers come from PlannerKit's
// widget snapshots; times are in the place's own time zone.

import PlannerKit
import SwiftUI
import WidgetKit

enum LumoraWidgetKind: String, CaseIterable, Identifiable, Sendable {
    case sun, moon, milkyWay, nextPlan
    var id: Self { self }

    var title: String {
        switch self {
        case .sun: String(localized: "Sun")
        case .moon: String(localized: "Moon")
        case .milkyWay: String(localized: "Milky Way")
        case .nextPlan: String(localized: "Next plan")
        }
    }

    var summary: String {
        switch self {
        case .sun: String(localized: "Light now and the next sunrise, sunset, golden and blue hour.")
        case .moon: String(localized: "The Moon's phase and its next rise or set.")
        case .milkyWay: String(localized: "When the galactic core is up in a dark sky tonight.")
        case .nextPlan: String(localized: "Your next saved plan and the light it expects.")
        }
    }
}

/// Everything one widget entry needs.
struct LumoraWidgetContent: Sendable {
    var clock: ClockStyle = .twentyFourHour
    var sun: SunWidgetSnapshot?
    var moon: MoonWidgetSnapshot?
    var milkyWay: MilkyWayWidgetSnapshot?
    var plan: WidgetPlan?
    /// False when the app has not shared a place yet.
    var hasPlace = true
}

private func clockTime(_ date: Date, _ zone: TimeZone, _ clock: ClockStyle) -> String {
    Formatting.clockTime(date, timeZone: zone, style: clock)
}

private func shortDate(_ date: Date, _ zone: TimeZone) -> String {
    var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
    style.timeZone = zone
    return date.formatted(style.weekday(.abbreviated))
}

/// The face for one kind and family.
struct LumoraWidgetFace: View {
    let kind: LumoraWidgetKind
    let content: LumoraWidgetContent
    let family: WidgetFamily

    var body: some View {
        if !content.hasPlace {
            WidgetMessage(kind: kind, text: String(localized: "Open Lumora to choose a place."), family: family)
        } else {
            switch kind {
            case .sun: SunFace(snapshot: content.sun, clock: content.clock, family: family)
            case .moon: MoonFace(snapshot: content.moon, clock: content.clock, family: family)
            case .milkyWay: MilkyWayFace(snapshot: content.milkyWay, clock: content.clock, family: family)
            case .nextPlan: PlanFace(plan: content.plan, clock: content.clock, family: family)
            }
        }
    }

    /// Home-screen background: the colour of the light now.
    static func background(kind: LumoraWidgetKind, content: LumoraWidgetContent) -> LinearGradient {
        let colors: [Color]
        switch kind {
        case .sun: colors = Self.colors(for: content.sun?.lightPhase ?? .day)
        case .moon, .milkyWay: colors = [Color(red: 0.05, green: 0.06, blue: 0.16), Color(red: 0.16, green: 0.12, blue: 0.32)]
        case .nextPlan: colors = [Color(red: 0.13, green: 0.20, blue: 0.42), Color(red: 0.42, green: 0.25, blue: 0.45)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    static func colors(for phase: LightPhase) -> [Color] {
        switch phase {
        case .day: [Color(red: 0.22, green: 0.55, blue: 0.92), Color(red: 0.52, green: 0.78, blue: 0.98)]
        case .goldenHour: [Color(red: 0.95, green: 0.55, blue: 0.20), Color(red: 0.98, green: 0.80, blue: 0.40)]
        case .blueHour: [Color(red: 0.10, green: 0.20, blue: 0.55), Color(red: 0.30, green: 0.40, blue: 0.80)]
        case .nauticalTwilight, .astronomicalTwilight: [Color(red: 0.06, green: 0.09, blue: 0.28), Color(red: 0.18, green: 0.20, blue: 0.45)]
        case .night: [Color(red: 0.02, green: 0.03, blue: 0.10), Color(red: 0.08, green: 0.09, blue: 0.22)]
        }
    }
}

private struct WidgetMessage: View {
    let kind: LumoraWidgetKind
    let text: String
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline: Text(text)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "location.slash")
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title).font(.headline)
                Text(text).font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(.white)
        }
    }
}

// MARK: - Sun

private struct SunFace: View {
    let snapshot: SunWidgetSnapshot?
    let clock: ClockStyle
    let family: WidgetFamily

    var body: some View {
        if let s = snapshot {
            let next = s.next
            switch family {
            case .accessoryInline:
                if let next {
                    Label("\(next.kind.label) \(clockTime(next.time, s.timeZone, clock))", systemImage: next.kind.systemImage)
                } else {
                    Label(s.lightPhase.label, systemImage: "sun.max")
                }
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        Image(systemName: next?.kind.systemImage ?? "sun.max").font(.system(size: 15, weight: .semibold))
                        Text(next.map { clockTime($0.time, s.timeZone, clock) } ?? "—")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .minimumScaleFactor(0.6)
                    }
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label(s.lightPhase.label, systemImage: "sun.max").font(.headline).widgetAccentable()
                    ForEach(Array(s.upcoming.prefix(2).enumerated()), id: \.offset) { _, event in
                        Text("\(event.kind.label) \(clockTime(event.time, s.timeZone, clock))").font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .systemMedium:
                HStack(alignment: .top, spacing: 14) {
                    SunHeader(s: s, clock: clock)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(s.upcoming.enumerated()), id: \.offset) { _, event in
                            EventLine(event: event, time: clockTime(event.time, s.timeZone, clock))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(.white)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    SunHeader(s: s, clock: clock)
                    Spacer(minLength: 0)
                    if let next {
                        Label(next.kind.label, systemImage: next.kind.systemImage).font(.caption.weight(.semibold))
                        Text(clockTime(next.time, s.timeZone, clock)).font(.title.weight(.bold).monospacedDigit())
                            .minimumScaleFactor(0.6)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(.white)
            }
        } else {
            Text("—")
        }
    }
}

private struct SunHeader: View {
    let s: SunWidgetSnapshot
    let clock: ClockStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s.place).font(.caption.weight(.semibold)).lineLimit(1)
            Text(s.lightPhase.label).font(.headline).lineLimit(2)
            Text("Sun \(Formatting.degrees(s.altitude, decimals: 0)) · \(Formatting.azimuth(s.azimuth, decimals: 0))")
                .font(.caption2).opacity(0.85)
        }
    }
}

private struct EventLine: View {
    let event: WidgetEvent
    let time: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: event.kind.systemImage).frame(width: 18)
            Text(event.kind.label).font(.caption).lineLimit(1)
            Spacer(minLength: 4)
            Text(time).font(.caption.weight(.semibold).monospacedDigit())
        }
    }
}

// MARK: - Moon

private struct MoonFace: View {
    let snapshot: MoonWidgetSnapshot?
    let clock: ClockStyle
    let family: WidgetFamily

    var body: some View {
        if let s = snapshot {
            let lit = "\(Int((s.illumination * 100).rounded()))%"
            let next = s.upcoming.first
            switch family {
            case .accessoryInline:
                Label("\(s.phaseName.displayName) \(lit)", systemImage: "moon.fill")
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 2) {
                        MoonDisc(elongation: s.elongation, southern: s.isSouthern).frame(width: 30, height: 30)
                        Text(lit).font(.system(size: 11, weight: .semibold))
                    }
                }
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    MoonDisc(elongation: s.elongation, southern: s.isSouthern).frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.phaseName.displayName).font(.headline).widgetAccentable()
                        Text("\(lit) lit").font(.caption)
                        if let next { Text("\(next.kind.label) \(clockTime(next.time, s.timeZone, clock))").font(.caption) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .systemMedium:
                HStack(spacing: 16) {
                    MoonDisc(elongation: s.elongation, southern: s.isSouthern).frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.place).font(.caption.weight(.semibold))
                        Text(s.phaseName.displayName).font(.headline)
                        Text("\(lit) lit").font(.caption)
                        ForEach(Array(s.upcoming.prefix(2).enumerated()), id: \.offset) { _, event in
                            EventLine(event: event, time: clockTime(event.time, s.timeZone, clock))
                        }
                        if let full = s.nextFull {
                            Text("Full Moon \(shortDate(full, s.timeZone))").font(.caption2).opacity(0.85)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(.white)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        MoonDisc(elongation: s.elongation, southern: s.isSouthern).frame(width: 48, height: 48)
                        Spacer()
                        Text(lit).font(.title3.weight(.bold))
                    }
                    Spacer(minLength: 0)
                    Text(s.phaseName.displayName).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                    if let next {
                        Text("\(next.kind.label) \(clockTime(next.time, s.timeZone, clock))").font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(.white)
            }
        } else {
            Text("—")
        }
    }
}

// MARK: - Milky Way

private struct MilkyWayFace: View {
    let snapshot: MilkyWayWidgetSnapshot?
    let clock: ClockStyle
    let family: WidgetFamily

    var body: some View {
        if let s = snapshot {
            let span = s.window.map { "\(clockTime($0.start, s.timeZone, clock))–\(clockTime($0.end, s.timeZone, clock))" }
            let when = s.isTonight ? String(localized: "Tonight") : s.window.map { shortDate($0.start, s.timeZone) } ?? ""
            switch family {
            case .accessoryInline:
                Label(span.map { "\(when) \($0)" } ?? String(localized: "Core not up"), systemImage: "sparkles")
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold))
                        Text(s.window.map { clockTime($0.start, s.timeZone, clock) } ?? "—")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit()).minimumScaleFactor(0.6)
                    }
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label("Milky Way", systemImage: "sparkles").font(.headline).widgetAccentable()
                    if let span {
                        Text("\(when) \(span)").font(.caption)
                        if let best = s.best { Text("Best \(clockTime(best.time, s.timeZone, clock))").font(.caption) }
                    } else {
                        Text("Core not up in a dark sky soon").font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Milky Way", systemImage: "sparkles").font(.headline)
                        Spacer()
                        if family == .systemMedium { Text(s.place).font(.caption.weight(.semibold)) }
                    }
                    Spacer(minLength: 0)
                    if let span {
                        Text(when).font(.caption.weight(.semibold))
                        Text(span).font(.title2.weight(.bold).monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1)
                        if let best = s.best {
                            Text("Best \(clockTime(best.time, s.timeZone, clock)) · core \(Formatting.azimuth(best.azimuth, decimals: 0))")
                                .font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        if family == .systemMedium {
                            Text("\(s.moonInterference.label) · Moon \(Int((s.moonIllumination * 100).rounded()))%")
                                .font(.caption2).opacity(0.85)
                        }
                    } else {
                        Text("The core is not up in a dark sky in the next three weeks.").font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(.white)
            }
        } else {
            Text("—")
        }
    }
}

// MARK: - Next plan

private struct PlanFace: View {
    let plan: WidgetPlan?
    let clock: ClockStyle
    let family: WidgetFamily

    var body: some View {
        if let p = plan {
            let time = clockTime(p.instant, p.timeZone, clock)
            let day = shortDate(p.instant, p.timeZone)
            switch family {
            case .accessoryInline:
                Label("\(p.name) \(time)", systemImage: "bookmark.fill")
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        Image(systemName: "bookmark.fill").font(.system(size: 13))
                        Text(time).font(.system(size: 12, weight: .semibold).monospacedDigit()).minimumScaleFactor(0.6)
                    }
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name).font(.headline).lineLimit(1).widgetAccentable()
                    Text("\(day) \(time)").font(.caption)
                    Text("\(p.place) · \(p.light)").font(.caption).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 3) {
                    Label("Next plan", systemImage: "bookmark.fill").font(.caption.weight(.semibold))
                    Text(p.name).font(.headline).lineLimit(2)
                    Spacer(minLength: 0)
                    Text("\(day), \(time)").font(.subheadline.weight(.semibold).monospacedDigit())
                    Text(p.place).font(.caption).lineLimit(1)
                    if family == .systemMedium {
                        Text("\(p.light) · Sun \(Formatting.degrees(p.sunAltitude, decimals: 0)) at "
                             + Formatting.azimuth(p.sunAzimuth, decimals: 0))
                            .font(.caption2).opacity(0.85)
                        Text(p.instant, style: .relative).font(.caption2).opacity(0.85)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(.white)
            }
        } else {
            switch family {
            case .accessoryInline: Text("No upcoming plans")
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "bookmark")
                }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Label("Next plan", systemImage: "bookmark").font(.headline)
                    Text("No upcoming plans. Save one from the Planner.").font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(family == .accessoryRectangular ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
            }
        }
    }
}

extension LumoraWidgetContent {
    /// Snapshots for one kind at one instant (the extension's timeline and the app's gallery).
    static func compute(kind: LumoraWidgetKind, location: PillLocation?, instant: Date, clock: ClockStyle,
                        plans: [WidgetPlan], milkyWay: MilkyWayWidgetSnapshot? = nil) -> LumoraWidgetContent {
        var content = LumoraWidgetContent(clock: clock)
        if kind == .nextPlan {
            content.plan = WidgetPlan.next(plans, after: instant)
            return content
        }
        guard let location else {
            content.hasPlace = false
            return content
        }
        switch kind {
        case .sun: content.sun = SunWidgetSnapshot.compute(location: location, instant: instant)
        case .moon: content.moon = MoonWidgetSnapshot.compute(location: location, instant: instant)
        case .milkyWay: content.milkyWay = milkyWay ?? MilkyWayWidgetSnapshot.compute(location: location, instant: instant)
        case .nextPlan: break
        }
        return content
    }
}
