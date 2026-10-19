// App/Sources/Pills/SunPillView.swift
//
// Sun pill: day summary, twilights, elevation graph, month table and seasons for the place
// and date in the shared PillSession. All numbers come from PlannerKit reports.

import AstroCore
import PlannerKit
import SwiftUI

struct SunPillView: View {
    enum Screen: String, CaseIterable, Identifiable {
        case day, twilight, graph, month, seasons
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .day: "Day"
            case .twilight: "Twilight"
            case .graph: "Graph"
            case .month: "Month"
            case .seasons: "Seasons"
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
            case .day: SunDaySections(format: format)
            case .twilight: TwilightSections(format: format)
            case .graph: SunGraphSection(format: format)
            case .month: SunMonthSection(format: format)
            case .seasons: SeasonsSections(format: format)
            }
        }
        .navigationTitle("Sun")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Inputs that change a day report.
private struct DayKey: Equatable, Sendable {
    let location: PillLocation
    let day: LocalDay
    let instant: Date
    let thresholds: SolarThresholds
}

// MARK: - Day

private struct SunDaySections: View {
    @Environment(PillSession.self) private var session
    @AppStorage(SettingsKeys.unitSystem) private var units: UnitSystem = .metric
    let format: PillFormat

    var body: some View {
        ReportLoader(key: DayKey(location: session.location, day: session.day, instant: session.instant,
                                 thresholds: session.thresholds)) { key in
            SunDayReport.compute(location: key.location, day: key.day, instant: key.instant, thresholds: key.thresholds)
        } content: { report in
            Section(format.dayLabel(report.day)) {
                ValueRow("Sunrise", format.events(report.rises, none: report.state.noEventLabel(body: .sun)))
                ValueRow("Sunset", format.events(report.sets, none: report.state.noEventLabel(body: .sun)))
                if let noon = report.noon {
                    ValueRow("Solar noon", "\(format.time(noon.time)) · el \(Formatting.degrees(noon.altitude))")
                }
                ValueRow("Daylight", Formatting.duration(seconds: report.daylightSeconds))
                ValueRow("Change from yesterday", signedDuration(report.daylightChangeSeconds))
            }
            Section("At \(format.time(report.position.time))") {
                ValueRow("Azimuth", Formatting.azimuth(report.position.azimuth))
                ValueRow("Elevation", Formatting.degrees(report.position.altitude))
                ValueRow("Light", report.lightPhase.displayName)
                ValueRow("Shadow length", report.shadowRatio.map { String(format: "%.2f × height", $0) }
                    ?? String(localized: "Sun below horizon"))
                ValueRow("Distance", distance(report.position.distanceKm))
            }
        }
    }

    private func distance(_ km: Double) -> String {
        switch units {
        case .metric: String(format: "%.3f million km", km / 1e6)
        case .imperial: String(format: "%.3f million mi", km / 1.609344 / 1e6)
        }
    }
}

// MARK: - Twilight

private struct TwilightKey: Equatable, Sendable {
    let location: PillLocation
    let day: LocalDay
    let thresholds: SolarThresholds
}

private struct TwilightSections: View {
    @Environment(PillSession.self) private var session
    let format: PillFormat

    var body: some View {
        ReportLoader(key: TwilightKey(location: session.location, day: session.day, thresholds: session.thresholds)) { key in
            TwilightReport.compute(location: key.location, day: key.day, thresholds: key.thresholds)
        } content: { report in
            Section {
                ValueRow("Astronomical dawn", format.times(morning(.astronomical, report)))
                ValueRow("Nautical dawn", format.times(morning(.nautical, report)))
                ValueRow("Civil dawn", format.times(morning(.civil, report)))
                ValueRow("Blue hour", format.spans(report.morningBlueHours))
                ValueRow("Golden hour", format.spans(report.morningGoldenHours))
                ValueRow("Sunrise", format.times(morning(.horizon, report)))
            } header: {
                Text("Morning")
            }
            Section {
                ValueRow("Sunset", format.times(evening(.horizon, report)))
                ValueRow("Golden hour", format.spans(report.eveningGoldenHours))
                ValueRow("Blue hour", format.spans(report.eveningBlueHours))
                ValueRow("Civil dusk", format.times(evening(.civil, report)))
                ValueRow("Nautical dusk", format.times(evening(.nautical, report)))
                ValueRow("Astronomical dusk", format.times(evening(.astronomical, report)))
            } header: {
                Text("Evening")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if report.isDarkAllDay {
                        Text("Polar night: the Sun stays below −18° all day.")
                    } else if let note = report.darkness.explanation {
                        Text(note)
                    }
                    Text(thresholdNote(report.thresholds))
                }
            }
        }
    }

    private func morning(_ kind: TwilightKind, _ report: TwilightReport) -> [Date] {
        report.rows.first { $0.kind == kind }?.morning ?? []
    }

    private func evening(_ kind: TwilightKind, _ report: TwilightReport) -> [Date] {
        report.rows.first { $0.kind == kind }?.evening ?? []
    }

    private func thresholdNote(_ t: SolarThresholds) -> String {
        String(localized: """
            Sun centre elevation: golden hour \(Int(t.goldenLower))° to +\(Int(t.goldenUpper))°, \
            blue hour \(Int(t.blueLower))° to \(Int(t.blueUpper))°; civil, nautical and astronomical \
            twilight end at \(Int(t.civil))°, \(Int(t.nautical))° and \(Int(t.astronomical))°.
            """)
    }
}

// MARK: - Graph

private struct PathKey: Equatable, Sendable {
    let location: PillLocation
    let day: LocalDay
}

private struct SunGraphSection: View {
    @Environment(PillSession.self) private var session
    let format: PillFormat

    var body: some View {
        ReportLoader(key: PathKey(location: session.location, day: session.day)) { key in
            SkyPath.compute(.sun, location: key.location, day: key.day)
        } content: { path in
            Section {
                SkyPathChart(path: path, day: session.day, selected: session.instant, format: format,
                             thresholds: session.thresholds)
                    .padding(.vertical, 8)
                if let high = path.highest {
                    ValueRow("Highest", "\(Formatting.degrees(high.altitude)) at \(format.time(high.time))")
                }
                if let low = path.lowest {
                    ValueRow("Lowest", "\(Formatting.degrees(low.altitude)) at \(format.time(low.time))")
                }
            } header: {
                Text("Sun elevation")
            } footer: {
                Text("Shaded bands: astronomical and nautical twilight, blue hour and golden hour. The vertical line is the selected time.")
            }
        }
    }
}

// MARK: - Month

private struct MonthKey: Equatable, Sendable {
    let location: PillLocation
    let year: Int
    let month: Int
}

private struct SunMonthSection: View {
    @Environment(PillSession.self) private var session
    let format: PillFormat

    var body: some View {
        let day = session.day
        ReportLoader(key: MonthKey(location: session.location, year: day.year, month: day.month)) { key in
            SunMonthTable.compute(location: key.location, year: key.year, month: key.month)
        } content: { table in
            Section {
                MonthNavigator(title: format.monthTitle(year: table.year, month: table.month))
                MonthTableRow(cells: ["Day", "Rise", "Set", "Daylight"])
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                ForEach(table.rows) { row in
                    Button {
                        session.shift(days: row.day.day - day.day)
                    } label: {
                        MonthTableRow(cells: [
                            "\(row.day.day)",
                            row.rises.first.map { format.time($0.time) } ?? "—",
                            row.sets.last.map { format.time($0.time) } ?? "—",
                            daylight(row),
                        ])
                        .font(.callout.monospacedDigit())
                        .fontWeight(highlight(row, table) ? .semibold : .regular)
                        .foregroundStyle(row.day == day ? Color.accentColor : Color.primary)
                    }
                    .accessibilityLabel(accessibilityText(row))
                }
            } footer: {
                if let longest = table.longestDay, let shortest = table.shortestDay {
                    Text("Longest day this month: \(longest). Shortest: \(shortest). Tap a day to select it.")
                }
            }
        }
    }

    private func daylight(_ row: SunMonthRow) -> String {
        switch row.state {
        case .alwaysAbove: "24h"
        case .alwaysBelow: "0h"
        case .normal: Formatting.duration(seconds: row.daylightSeconds)
        }
    }

    private func accessibilityText(_ row: SunMonthRow) -> String {
        let rise = row.rises.first.map { format.time($0.time) } ?? "—"
        let set = row.sets.last.map { format.time($0.time) } ?? "—"
        return String(localized: "Day \(row.day.day), sunrise \(rise), sunset \(set), daylight \(daylight(row))")
    }

    private func highlight(_ row: SunMonthRow, _ table: SunMonthTable) -> Bool {
        row.day.day == table.longestDay || row.day.day == table.shortestDay
    }
}

/// Four equal columns, the first narrow.
struct MonthTableRow: View {
    let cells: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, text in
                Text(text)
                    .frame(minWidth: index == 0 ? 28 : nil, maxWidth: index == 0 ? 36 : .infinity, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

/// "‹ March 2026 ›" moving the shared date by a month (or a year, for `step` 12).
struct MonthNavigator: View {
    @Environment(PillSession.self) private var session
    let title: String
    var step = 1

    var body: some View {
        HStack {
            Button {
                session.shift(months: -step)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel(step == 12 ? "Previous year" : "Previous month")
            Spacer()
            Text(title).font(.headline)
            Spacer()
            Button {
                session.shift(months: step)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel(step == 12 ? "Next year" : "Next month")
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Seasons

private struct YearKey: Equatable, Sendable {
    let location: PillLocation
    let year: Int
}

private struct SeasonsSections: View {
    @Environment(PillSession.self) private var session
    let format: PillFormat

    var body: some View {
        ReportLoader(key: YearKey(location: session.location, year: session.day.year)) { key in
            SeasonsReport.compute(location: key.location, year: key.year)
        } content: { report in
            Section {
                MonthNavigator(title: String(session.day.year), step: 12)
                if let report {
                    ForEach(report.events) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(event.marker.displayName): \(event.begins.displayName) begins")
                                .font(.headline)
                            Text(format.dateAndTime(event.time))
                                .monospacedDigit()
                            Text("Daylight \(Formatting.duration(seconds: event.daylightSeconds))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } else {
                    Text("Seasons are not available for this year.")
                }
            } footer: {
                Text(session.location.isSouthern
                    ? "Southern hemisphere: seasons are the reverse of the north."
                    : "Northern hemisphere seasons.")
            }
            if let report, report.midnightSun != nil || report.polarNight != nil {
                Section("Polar days") {
                    if let period = report.midnightSun {
                        ValueRow("Midnight sun", periodText(period))
                    }
                    if let period = report.polarNight {
                        ValueRow("Polar night", periodText(period))
                    }
                }
            }
        }
    }

    private func periodText(_ period: PolarPeriod) -> String {
        "\(format.dayLabel(period.first)) – \(format.dayLabel(period.last)) (\(period.days) days)"
    }
}
