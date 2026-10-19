// App/Sources/PlannerPlaceholderView.swift
//
// Phase 0 placeholder for the Planner. Shows today's Sun and Moon summary for a fixed
// demo location so the AstroCore → PlannerKit → app path is exercised end to end.
// The map, pin and time scrubber arrive in Phase 3.

import AstroCore
import PlannerKit
import SwiftUI

struct DemoLocation: Identifiable, Hashable {
    let name: String
    let observer: Observer
    let timeZoneID: String
    var id: String { name }

    static let all: [DemoLocation] = [
        DemoLocation(name: "Warsaw", observer: Observer(latitude: 52.2297, longitude: 21.0122), timeZoneID: "Europe/Warsaw"),
        DemoLocation(name: "Tromsø", observer: Observer(latitude: 69.6492, longitude: 18.9553), timeZoneID: "Europe/Oslo"),
        DemoLocation(name: "Sydney", observer: Observer(latitude: -33.8688, longitude: 151.2093), timeZoneID: "Australia/Sydney"),
        DemoLocation(name: "Quito", observer: Observer(latitude: -0.1807, longitude: -78.4678, height: 2850),
                     timeZoneID: "America/Guayaquil"),
    ]
}

struct PlannerPlaceholderView: View {
    @AppStorage(SettingsKeys.clockStyle) private var clockStyle: ClockStyle = .twentyFourHour
    @State private var location = DemoLocation.all[0]
    @State private var summary: DaySummary?

    var body: some View {
        List {
            Section {
                Picker("Location", selection: $location) {
                    ForEach(DemoLocation.all) { Text($0.name).tag($0) }
                }
            } footer: {
                Text("The map planner arrives in Phase 3. Times are shown in the location's time zone.")
            }
            if let summary {
                Section(summary.title) {
                    ForEach(summary.rows) { row in
                        LabeledContent(row.label, value: row.value)
                            .accessibilityElement(children: .combine)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task(id: TaskKey(location: location, clock: clockStyle)) {
            let zone = TimeZone(identifier: location.timeZoneID) ?? .current
            let day = LocalDay(containing: Date(), timeZone: zone)
            summary = await DaySummary.make(observer: location.observer, day: day, clock: clockStyle)
        }
    }

    private struct TaskKey: Equatable {
        let location: DemoLocation
        let clock: ClockStyle
    }
}
