// App/Sources/Pills/MilkyWayPillView.swift
//
// Milky Way pill: for the selected night, when the galactic core can be photographed (dark
// sky, core up, Moon down or dim), its path and arc orientation through the night; for the
// year, the season, best months and best nights. Numbers come from PlannerKit's
// MilkyWayNightReport and MilkyWayYearReport; this file only lays them out.

import AstroCore
import Charts
import PlannerKit
import SwiftUI

struct MilkyWayPillView: View {
    enum Screen: String, CaseIterable, Identifiable {
        case night, year
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .night: "Night"
            case .year: "Year"
            }
        }
    }

    @Environment(PillSession.self) private var session
    @AppStorage(SettingsKeys.clockStyle) private var clock: ClockStyle = .twentyFourHour
    @State private var screen: Screen = .night
    private static let top = "milkyway.top"

    var body: some View {
        let format = PillFormat(timeZone: session.timeZone, clock: clock)
        ScrollViewReader { proxy in
            List {
                PillHeader()
                Section {
                    Picker("View", selection: $screen) {
                        ForEach(Screen.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("milkyway.screen")
                    .id(Self.top)
                }
                switch screen {
                case .night: MilkyWayNightSections(format: format)
                case .year: MilkyWayYearSections(format: format) { screen = .night }
                }
            }
            // Picking a best night switches to Night: show it from the top.
            .onChange(of: screen) { withAnimation { proxy.scrollTo(Self.top, anchor: .top) } }
        }
        .navigationTitle("Milky Way")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NightKey: Equatable, Sendable {
    let location: PillLocation
    let day: LocalDay
}

private struct YearKey: Equatable, Sendable {
    let location: PillLocation
    let year: Int
}

/// The night that contains the selected instant: before local noon it is the previous date's night.
@MainActor
private func nightDay(_ session: PillSession) -> LocalDay {
    let day = session.day
    return session.instant < day.noon ? day.adding(days: -1) : day
}

// MARK: - Night

private struct MilkyWayNightSections: View {
    @Environment(PillSession.self) private var session
    let format: PillFormat

    var body: some View {
        ReportLoader(key: NightKey(location: session.location, day: nightDay(session))) { key in
            MilkyWayNightReport.compute(location: key.location, day: key.day)
        } content: { report in
            TitledSection("Night of \(format.dayLabel(report.day))") {
                ValueRow("Core visible", spans(report.visible))
                ValueRow("Moon-free", spans(report.moonFree))
                ValueRow("Dark sky", spans(report.dark))
                ValueRow("Moon", "\(report.moonInterference.label) · \(Int((report.moonIllumination * 100).rounded()))% lit")
                if !report.moonRises.isEmpty || !report.moonSets.isEmpty {
                    ValueRow("Moonrise / set", "\(format.times(report.moonRises)) / \(format.times(report.moonSets))")
                }
            }
            if let best = report.bestMoment {
                TitledSection("Best moment") {
                    HStack(spacing: 16) {
                        ArcGlyph(tilt: best.tilt)
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(format.time(best.time)).font(.title3.weight(.semibold))
                            Text("Core at \(Formatting.azimuth(best.azimuth)), el \(Formatting.degrees(best.altitude))")
                            Text(best.orientation.label).foregroundStyle(.subdued)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
            TitledSection("Core through the night") {
                CoreNightChart(report: report, format: format)
                    .padding(.vertical, 8)
            }
            TitledSection("Hour by hour") {
                let hourly = report.path.filter { $0.altitude > -2 && isOnTheHour($0.time) }
                if hourly.isEmpty {
                    Text("The core stays below the horizon all night.").foregroundStyle(.subdued)
                }
                ForEach(hourly) { sample in
                    HourRow(sample: sample, format: format, visible: report.visible.contains { $0.contains(sample.time) })
                }
            }
        }
    }

    private func spans(_ list: [DateInterval]) -> String {
        list.isEmpty ? String(localized: "Not tonight") : format.spans(list)
    }

    private func isOnTheHour(_ date: Date) -> Bool {
        Int(date.timeIntervalSince1970 + Double(format.timeZone.secondsFromGMT(for: date))) % 3600 == 0
    }
}

private struct HourRow: View {
    let sample: GalacticCenterSample
    let format: PillFormat
    let visible: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(format.time(sample.time))
                .monospacedDigit()
                .frame(width: 64, alignment: .leading)
            ArcGlyph(tilt: sample.tilt)
                .frame(width: 26, height: 26)
                .opacity(sample.altitude > 0 ? 1 : 0.35)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Formatting.azimuth(sample.azimuth)) · el \(Formatting.degrees(sample.altitude))").monospacedDigit()
                Text(sample.orientation.label).font(.caption).foregroundStyle(.subdued)
            }
            Spacer()
            if visible {
                Image(systemName: "sparkles").foregroundStyle(.purple)
                    .accessibilityLabel("Visible")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Core elevation from noon to noon, with the visible and Moon-free windows shaded.
private struct CoreNightChart: View {
    let report: MilkyWayNightReport
    let format: PillFormat

    private var ticks: [Date] {
        stride(from: 0.0, through: report.end.timeIntervalSince(report.start), by: 4 * 3600).map {
            report.start.addingTimeInterval($0)
        }
    }

    var body: some View {
        Chart {
            ForEach(report.dark, id: \.self) { span in
                RectangleMark(xStart: .value("Start", span.start), xEnd: .value("End", span.end))
                    .foregroundStyle(Color.indigo.opacity(0.18))
            }
            ForEach(report.moonFree, id: \.self) { span in
                RectangleMark(xStart: .value("Start", span.start), xEnd: .value("End", span.end))
                    .foregroundStyle(Color.purple.opacity(0.22))
            }
            RuleMark(y: .value("Horizon", 0.0))
                .foregroundStyle(.subdued)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            ForEach(report.path) { sample in
                LineMark(x: .value("Time", sample.time), y: .value("Elevation", sample.altitude))
                    .foregroundStyle(Color.purple)
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartXScale(domain: report.start...report.end)
        .chartYScale(domain: -90.0...90.0)
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(format.time(date)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: [-60.0, -30.0, 0.0, 30.0, 60.0]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let degrees = value.as(Double.self) { Text("\(Int(degrees))°") }
                }
            }
        }
        .frame(height: 200)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Galactic core elevation through the night"))
    }
}

/// The band as it would look over the horizon at the core: a horizon line and a streak at
/// `tilt` degrees, with a dot for the core.
struct ArcGlyph: View {
    let tilt: Double

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let horizon = h * 0.82
            var ground = Path()
            ground.move(to: CGPoint(x: 0, y: horizon))
            ground.addLine(to: CGPoint(x: w, y: horizon))
            context.stroke(ground, with: .color(.secondary), lineWidth: 1)
            let angle = CGFloat(tilt) * .pi / 180
            let center = CGPoint(x: w / 2, y: horizon - h * 0.22)
            let length = w * 0.9
            let dx = cos(angle) * length / 2, dy = sin(angle) * length / 2
            var band = Path()
            band.move(to: CGPoint(x: center.x - dx, y: center.y + dy))
            band.addLine(to: CGPoint(x: center.x + dx, y: center.y - dy))
            context.stroke(band, with: .color(.purple.opacity(0.75)), style: StrokeStyle(lineWidth: max(3, w * 0.14), lineCap: .round))
            let dot = max(3, w * 0.09)
            context.fill(Path(ellipseIn: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2)),
                         with: .color(.white))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Year

private struct MilkyWayYearSections: View {
    @Environment(PillSession.self) private var session
    let format: PillFormat
    let showNight: () -> Void

    var body: some View {
        ReportLoader(key: YearKey(location: session.location, year: session.day.year)) { key in
            MilkyWayYearReport.compute(location: key.location, year: key.year)
        } content: { report in
            TitledSection("Season \(String(report.year))") {
                if let start = report.seasonStart, let end = report.seasonEnd {
                    ValueRow("First core night", format.dayLabel(start))
                    ValueRow("Last core night", format.dayLabel(end))
                } else {
                    Text("The core never rises in a dark sky here.").foregroundStyle(.subdued)
                }
                if !report.bestMonths.isEmpty {
                    ValueRow("Best months", report.bestMonths.prefix(3).map { monthName($0.month) }.joined(separator: ", "))
                }
            }
            TitledSection("Core hours by month") {
                MonthChart(months: report.months)
                    .padding(.vertical, 8)
            }
            TitledSection("Best nights") {
                ForEach(report.bestNights(10)) { night in
                    Button {
                        // 23:00 local on that date, inside the night that starts there.
                        session.instant = night.day.noon.addingTimeInterval(11 * 3600)
                        showNight()
                    } label: {
                        LabeledContent {
                            Text("\(hours(night.moonFreeHours)) · Moon \(Int((night.moonIllumination * 100).rounded()))%")
                                .monospacedDigit()
                        } label: {
                            Text(format.dayLabel(night.day))
                        }
                    }
                    .accessibilityIdentifier("milkyway.bestNight")
                }
            }
        }
    }

    private func hours(_ value: Double) -> String { String(format: "%.1f h", value) }

    private func monthName(_ month: Int) -> String { shortMonthName(month) }
}

/// "Jun" for 6, in the user's language. A bare Gregorian calendar has no locale, so its
/// symbols come out as "M06".
private func shortMonthName(_ month: Int) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = .autoupdatingCurrent
    return calendar.shortMonthSymbols[month - 1]
}

private struct MonthChart: View {
    let months: [MilkyWayMonthSummary]

    var body: some View {
        Chart(months) { month in
            let name = shortMonthName(month.month)
            // Stacked: Moon-free hours, then the rest of the visible hours.
            BarMark(x: .value("Month", name), y: .value("Hours", month.moonFreeHours))
                .foregroundStyle(by: .value("Kind", String(localized: "Moon-free")))
            BarMark(x: .value("Month", name), y: .value("Hours", max(0, month.visibleHours - month.moonFreeHours)))
                .foregroundStyle(by: .value("Kind", String(localized: "With Moon")))
        }
        .chartForegroundStyleScale([String(localized: "Moon-free"): Color.purple,
                                    String(localized: "With Moon"): Color.indigo.opacity(0.3)])
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) { Text(String(label.prefix(1))) }
                }
            }
        }
        .frame(height: 180)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Hours the core is visible each month, Moon-free and with the Moon up"))
    }
}
