// App/Sources/Widgets/WidgetSync.swift
//
// Hands the widgets what they need: the selected place, the clock style and the upcoming
// saved plans go to the app-group store whenever they change, and the widget timelines are
// reloaded. Screenshot runs (`-fixedDate`) leave the store alone.

import PlannerKit
import SwiftData
import SwiftUI
import WidgetKit

struct WidgetSync: ViewModifier {
    @Environment(PillSession.self) private var session
    @AppStorage(SettingsKeys.clockStyle) private var clock: ClockStyle = .twentyFourHour
    @Query(sort: \PlanRecord.instant) private var records: [PlanRecord]
    private let enabled = !ProcessInfo.processInfo.arguments.contains("-fixedDate")

    func body(content: Content) -> some View {
        content
            .task(id: PlaceKey(location: session.location, clock: clock)) {
                guard enabled else { return }
                WidgetStore.save(location: session.location, clock: clock, to: WidgetStore.shared)
                WidgetCenter.shared.reloadAllTimelines()
            }
            .task(id: records.map { "\($0.id)\($0.modified.timeIntervalSince1970)" }) {
                guard enabled else { return }
                let plans = records.compactMap(\.plan).filter { $0.instant > Date() }
                let widgetPlans = await Task.detached { plans.map(WidgetPlan.init) }.value
                WidgetStore.save(plans: widgetPlans, now: Date(), to: WidgetStore.shared)
                WidgetCenter.shared.reloadTimelines(ofKind: "lumora.nextplan")
            }
    }

    private struct PlaceKey: Equatable {
        let location: PillLocation
        let clock: ClockStyle
    }
}

extension View {
    func syncsWidgets() -> some View { modifier(WidgetSync()) }
}
