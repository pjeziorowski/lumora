// App/Widgets/LumoraWidgets.swift
//
// The widget extension: Sun, Moon, Milky Way and Next plan widgets for the home screen and
// the lock screen. The place, clock style and upcoming plans come from the app through the
// shared app-group store (PlannerKit.WidgetStore); timelines last six hours, with an entry
// every 30 minutes (every 5 for the plan countdown) and one just after each event shown.

import PlannerKit
import SwiftUI
import WidgetKit

struct LumoraEntry: TimelineEntry, Sendable {
    let date: Date
    let content: LumoraWidgetContent
}

struct LumoraProvider: TimelineProvider {
    let kind: LumoraWidgetKind

    func placeholder(in context: Context) -> LumoraEntry {
        entries(at: [Date()], sample: true)[0]
    }

    func getSnapshot(in context: Context, completion: @escaping (LumoraEntry) -> Void) {
        completion(entries(at: [Date()], sample: context.isPreview)[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LumoraEntry>) -> Void) {
        let now = Date()
        let list = entries(at: dates(from: now), sample: false)
        completion(Timeline(entries: list, policy: .after(now.addingTimeInterval(WidgetTimeline.span))))
    }

    private func dates(from start: Date) -> [Date] {
        let shared = WidgetStore.shared
        switch kind {
        case .sun:
            let events = WidgetStore.location(in: shared).map { WidgetTimeline.sunEvents(location: $0, from: start) } ?? []
            return WidgetTimeline.dates(from: start, step: 1800, events: events)
        case .nextPlan:
            return WidgetTimeline.dates(from: start, step: 300, events: WidgetStore.plans(in: shared).map(\.instant))
        case .moon, .milkyWay:
            return WidgetTimeline.dates(from: start, step: 1800)
        }
    }

    /// One entry per date. The gallery preview uses a sample place.
    private func entries(at dates: [Date], sample: Bool) -> [LumoraEntry] {
        let shared = WidgetStore.shared
        let location = WidgetStore.location(in: shared) ?? (sample ? PillLocation.samples[0] : nil)
        let clock = WidgetStore.clock(in: shared)
        let plans = WidgetStore.plans(in: shared)
        // The core window changes once a night: compute it again only when the shown one ends.
        var milkyWay: MilkyWayWidgetSnapshot?
        return dates.map { date in
            if kind == .milkyWay, let location, milkyWay?.isStale(at: date) ?? true {
                milkyWay = MilkyWayWidgetSnapshot.compute(location: location, instant: date)
            }
            return LumoraEntry(date: date, content: .compute(kind: kind, location: location, instant: date, clock: clock,
                                                             plans: plans, milkyWay: milkyWay))
        }
    }
}

struct LumoraEntryView: View {
    let kind: LumoraWidgetKind
    let entry: LumoraEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        LumoraWidgetFace(kind: kind, content: entry.content, family: family)
            .containerBackground(for: .widget) {
                LumoraWidgetFace.background(kind: kind, content: entry.content)
            }
    }
}

extension WidgetConfiguration {
    /// Home screen (small, medium) and lock screen (circular, rectangular, inline).
    func lumoraFamilies() -> some WidgetConfiguration {
        supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct SunWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lumora.sun", provider: LumoraProvider(kind: .sun)) { LumoraEntryView(kind: .sun, entry: $0) }
            .configurationDisplayName(LumoraWidgetKind.sun.title)
            .description(LumoraWidgetKind.sun.summary)
            .lumoraFamilies()
    }
}

struct MoonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lumora.moon", provider: LumoraProvider(kind: .moon)) { LumoraEntryView(kind: .moon, entry: $0) }
            .configurationDisplayName(LumoraWidgetKind.moon.title)
            .description(LumoraWidgetKind.moon.summary)
            .lumoraFamilies()
    }
}

struct MilkyWayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lumora.milkyway", provider: LumoraProvider(kind: .milkyWay)) {
            LumoraEntryView(kind: .milkyWay, entry: $0)
        }
        .configurationDisplayName(LumoraWidgetKind.milkyWay.title)
        .description(LumoraWidgetKind.milkyWay.summary)
        .lumoraFamilies()
    }
}

struct NextPlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lumora.nextplan", provider: LumoraProvider(kind: .nextPlan)) {
            LumoraEntryView(kind: .nextPlan, entry: $0)
        }
        .configurationDisplayName(LumoraWidgetKind.nextPlan.title)
        .description(LumoraWidgetKind.nextPlan.summary)
        .lumoraFamilies()
    }
}

@main
struct LumoraWidgetBundle: WidgetBundle {
    var body: some Widget {
        SunWidget()
        MoonWidget()
        MilkyWayWidget()
        NextPlanWidget()
    }
}
