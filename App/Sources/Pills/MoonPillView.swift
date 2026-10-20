// App/Sources/Pills/MoonPillView.swift
//
// Moon pill: day summary with the Moon's path, a month phase calendar and the year's
// new/full moons with supermoon, micromoon and blue-moon flags. Numbers come from
// PlannerKit reports; this file only lays them out.

import AstroCore
import PlannerKit
import SwiftUI

struct MoonPillView: View {
    enum Screen: String, CaseIterable, Identifiable {
        case day, calendar, phases
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .day: "Day"
            case .calendar: "Calendar"
            case .phases: "Full & new"
            }
        }
    }

    @Environment(PillSession.self) private var session
    @AppStorage(SettingsKeys.clockStyle) private var clock: ClockStyle = .twentyFourHour
    @State private var screen: Screen = .day

    var body: some View {
        let format = PillFormat(timeZone: session.timeZone, clock: clock)
        List {
            PillHeader()
            Section {
                Picker("View", selection: $screen) {
                    ForEach(Screen.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            switch screen {
            case .day: MoonDaySections(format: format)
            case .calendar: MoonCalendarSection(format: format)
            case .phases: MoonPhasesSections(format: format)
            }
        }
        .navigationTitle("Moon")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MoonDayKey: Equatable, Sendable {
    let location: PillLocation
    let day: LocalDay
    let instant: Date
    let rule: SupermoonRule
}

private struct MoonPathKey: Equatable, Sendable {
    let location: PillLocation
    let day: LocalDay
}

// MARK: - Day

private struct MoonDaySections: View {
    @Environment(PillSession.self) private var session
    @AppStorage(SettingsKeys.unitSystem) private var units: UnitSystem = .metric
    let format: PillFormat

    var body: some View {
        ReportLoader(key: MoonDayKey(location: session.location, day: session.day, instant: session.instant,
                                     rule: session.supermoonRule)) { key in
            MoonDayReport.compute(location: key.location, day: key.day, instant: key.instant, rule: key.rule)
        } content: { report in
            Section {
                HStack(spacing: 16) {
                    MoonDisc(elongation: report.elongation, southern: report.location.isSouthern)
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.phaseName.displayName)
                            .font(.title3.weight(.semibold))
                        Text("\(Int((report.illumination * 100).rounded()))% lit")
                        if report.ageDays.isFinite {
                            Text("Age \(String(format: "%.1f", report.ageDays)) days")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
            Section(format.dayLabel(report.day)) {
                ValueRow("Moonrise", format.events(report.rises, none: report.state.noEventLabel(body: .moon)))
                ValueRow("Moonset", format.events(report.sets, none: report.state.noEventLabel(body: .moon)))
                if let transit = report.transit {
                    ValueRow("Highest", "\(format.time(transit.time)) · el \(Formatting.degrees(transit.altitude))")
                }
            }
            Section("At \(format.time(report.position.time))") {
                ValueRow("Azimuth", Formatting.azimuth(report.position.azimuth))
                ValueRow("Elevation", Formatting.degrees(report.position.altitude))
                ValueRow("Distance", distance(report.position.distanceKm))
                ValueRow("Apparent size", String(format: "%.1f′", report.angularDiameter * 60))
            }
            ReportLoader(key: MoonPathKey(location: session.location, day: session.day)) { key in
                SkyPath.compute(.moon, location: key.location, day: key.day)
            } content: { path in
                Section("Moon path") {
                    SkyPathChart(path: path, day: report.day, selected: session.instant, format: format)
                        .padding(.vertical, 8)
                }
            }
            Section("Next phases") {
                ForEach(report.upcoming) { event in
                    PhaseEventRow(event: event, format: format, southern: report.location.isSouthern, units: units)
                }
            }
        }
    }

    private func distance(_ km: Double) -> String {
        switch units {
        case .metric: String(format: "%.0f km", km)
        case .imperial: String(format: "%.0f mi", km / 1.609344)
        }
    }
}

private struct PhaseEventRow: View {
    let event: LunarPhaseEvent
    let format: PillFormat
    let southern: Bool
    let units: UnitSystem

    var body: some View {
        HStack(spacing: 12) {
            MoonDisc(elongation: event.quarter.elongation, southern: southern)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.quarter.displayName)
                    ForEach(badges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                }
                Text(subtitle)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var badges: [String] {
        var list: [String] = []
        switch event.size {
        case .supermoon: list.append(String(localized: "Supermoon"))
        case .micromoon: list.append(String(localized: "Micromoon"))
        case .regular: break
        }
        if event.isMonthlyBlueMoon || event.isSeasonalBlueMoon { list.append(String(localized: "Blue moon")) }
        return list
    }

    /// Date and time, plus the distance for new and full moons.
    private var subtitle: String {
        let when = format.dateAndTime(event.time)
        return event.quarter == .new || event.quarter == .full ? "\(when) · \(distance)" : when
    }

    private var distance: String {
        switch units {
        case .metric: String(format: "%.0f km", event.distanceKm)
        case .imperial: String(format: "%.0f mi", event.distanceKm / 1.609344)
        }
    }
}

// MARK: - Calendar

private struct MoonMonthKey: Equatable, Sendable {
    let location: PillLocation
    let year: Int
    let month: Int
}

private struct MoonCalendarSection: View {
    @Environment(PillSession.self) private var session
    let format: PillFormat

    private var firstWeekday: Int { Calendar.current.firstWeekday }

    var body: some View {
        let day = session.day
        ReportLoader(key: MoonMonthKey(location: session.location, year: day.year, month: day.month)) { key in
            MoonCalendarMonth.compute(location: key.location, year: key.year, month: key.month)
        } content: { month in
            Section {
                MonthNavigator(title: format.monthTitle(year: month.year, month: month.month))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                    // One ForEach with unique ids: a lazy grid drops cells whose ids repeat
                    // across sibling ForEach views (weekday 1 vs day 1).
                    ForEach(cells(month)) { cell in
                        switch cell {
                        case let .weekday(_, symbol):
                            Text(symbol)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        case .blank:
                            Color.clear.frame(height: 1)
                        case let .day(entry):
                            Button {
                                session.shift(days: entry.day.day - day.day)
                            } label: {
                                CalendarCell(entry: entry, selected: entry.day == day, southern: session.location.isSouthern)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accessibilityText(entry))
                        }
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Phase at local noon. Marked days hold a new moon, quarter or full moon; tap a day to select it.")
            }
            Section("This month") {
                ForEach(month.days.filter { $0.phaseEvent != nil }) { entry in
                    if let event = entry.phaseEvent {
                        ValueRow(LocalizedStringKey(event.quarter.displayName), format.dateAndTime(event.time.date))
                    }
                }
            }
        }
    }

    private enum GridCell: Identifiable {
        case weekday(Int, String)
        case blank(Int)
        case day(MoonCalendarDay)

        var id: String {
            switch self {
            case let .weekday(index, _): "weekday-\(index)"
            case let .blank(index): "blank-\(index)"
            case let .day(entry): "day-\(entry.day.day)"
            }
        }
    }

    private func cells(_ month: MoonCalendarMonth) -> [GridCell] {
        weekdaySymbols.enumerated().map { GridCell.weekday($0.offset, $0.element) }
            + (0..<month.leadingBlanks(firstWeekday: firstWeekday)).map { GridCell.blank($0) }
            + month.days.map { GridCell.day($0) }
    }

    /// Very short weekday names, rotated to start at the user's first weekday.
    private var weekdaySymbols: [String] {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let start = firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private func accessibilityText(_ entry: MoonCalendarDay) -> String {
        var text = "\(format.dayLabel(entry.day)), \(entry.phaseName.displayName), \(Int((entry.illumination * 100).rounded()))%"
        if let event = entry.phaseEvent { text += ", \(event.quarter.displayName) \(format.time(event.time.date))" }
        return text
    }
}

private struct CalendarCell: View {
    let entry: MoonCalendarDay
    let selected: Bool
    let southern: Bool

    var body: some View {
        VStack(spacing: 2) {
            MoonDisc(elongation: entry.elongation, southern: southern)
                .frame(width: 26, height: 26)
            Text("\(entry.day.day)")
                .font(.caption.monospacedDigit())
                .fontWeight(entry.phaseEvent != nil ? .bold : .regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor.opacity(0.2) : Color.clear)
        }
        .overlay(alignment: .topTrailing) {
            if entry.phaseEvent != nil {
                Circle().fill(.tint).frame(width: 5, height: 5).padding(3)
            }
        }
    }
}

// MARK: - Year list

private struct LunarYearKey: Equatable, Sendable {
    let location: PillLocation
    let year: Int
    let rule: SupermoonRule
}

private struct MoonPhasesSections: View {
    @Environment(PillSession.self) private var session
    @AppStorage(SettingsKeys.unitSystem) private var units: UnitSystem = .metric
    let format: PillFormat

    var body: some View {
        ReportLoader(key: LunarYearKey(location: session.location, year: session.day.year, rule: session.supermoonRule)) { key in
            LunarYear.compute(location: key.location, year: key.year, rule: key.rule)
        } content: { year in
            Section {
                MonthNavigator(title: String(year.year), step: 12)
                ValueRow("Supermoons", "\(year.supermoons.count)")
                ValueRow("Blue moons", "\(year.blueMoons.count)")
            } footer: {
                Text(ruleNote(session.supermoonRule))
            }
            Section("Full moons") {
                ForEach(year.fullMoons) { PhaseEventRow(event: $0, format: format, southern: session.location.isSouthern, units: units) }
            }
            Section("New moons") {
                ForEach(year.newMoons) { PhaseEventRow(event: $0, format: format, southern: session.location.isSouthern, units: units) }
            }
        }
    }

    private func ruleNote(_ rule: SupermoonRule) -> String {
        let near = Int(rule.superBelowKm / 1000), far = Int(rule.microAboveKm / 1000)
        return String(localized: """
            Supermoon: new or full moon closer than \(near),000 km. Micromoon: farther than \(far),000 km. \
            Blue moon: second full moon in a calendar month here, or third of four in a season.
            """)
    }
}
