// App/Sources/Pills/PillComponents.swift
//
// Small pieces shared by the Sun and Moon pills: time/position formatting in the place's
// time zone, a value row, display names for engine enums, the sky-path chart and the
// Moon phase disc.

import AstroCore
import Charts
import PlannerKit
import SwiftUI

// MARK: - Formatting

/// Formats instants in the place's time zone with the user's clock setting.
struct PillFormat {
    let timeZone: TimeZone
    let clock: ClockStyle

    func time(_ date: Date) -> String { Formatting.clockTime(date, timeZone: timeZone, style: clock) }

    func times(_ dates: [Date], none: String = "—") -> String {
        dates.isEmpty ? none : dates.map(time).joined(separator: ", ")
    }

    func span(_ interval: DateInterval) -> String { "\(time(interval.start))–\(time(interval.end))" }

    func spans(_ intervals: [DateInterval]) -> String {
        intervals.isEmpty ? "—" : intervals.map(span).joined(separator: ", ")
    }

    /// "06:18 · 89.2° E"
    func event(_ e: SkyEvent) -> String { "\(time(e.time)) · \(Formatting.azimuth(e.azimuth))" }

    func events(_ list: [SkyEvent], none: String) -> String {
        list.isEmpty ? none : list.map(event).joined(separator: "\n")
    }

    /// "Tue 21 Jun" in the place's zone.
    func dayLabel(_ day: LocalDay) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = timeZone
        return day.noon.formatted(style.weekday(.abbreviated))
    }

    /// "Aug 12, 2026" in the place's zone.
    func date(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    func dateAndTime(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = timeZone
        return "\(date.formatted(style)), \(time(date))"
    }

    /// "Mar 2026" for a month header.
    func monthTitle(year: Int, month: Int) -> String {
        var style = Date.FormatStyle().month(.wide).year()
        style.timeZone = timeZone
        return LocalDay(year: year, month: month, day: 15, timeZone: timeZone).noon.formatted(style)
    }
}

/// "16h 47m", or a plain-language label for polar days with no sunrise or no sunset.
func daylightText(_ seconds: Double) -> String {
    if seconds <= 0 { return String(localized: "None (polar night)") }
    if seconds >= 86_400 - 1 { return String(localized: "All day (midnight sun)") }
    return Formatting.duration(seconds: seconds)
}

/// "+2m 31s" / "−1m 05s"
func signedDuration(_ seconds: Double) -> String {
    let text = Formatting.duration(seconds: abs(seconds))
    return seconds < 0 ? "−\(text)" : "+\(text)"
}

struct ValueRow: View {
    let label: LocalizedStringKey
    let value: String

    init(_ label: LocalizedStringKey, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        LabeledContent {
            // LabeledContent draws values in the system's faint secondary style.
            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.subdued)
        } label: {
            Text(label)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shows a spinner until a report arrives; the report is recomputed off the main actor
/// whenever `key` changes.
struct ReportLoader<Key: Equatable & Sendable, Report: Sendable, Content: View>: View {
    let key: Key
    let compute: @Sendable (Key) -> Report
    @ViewBuilder let content: (Report) -> Content
    @State private var report: Report?

    var body: some View {
        Group {
            if let report {
                content(report)
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .task(id: key) {
            let key = key
            let compute = compute
            let result = await Task.detached(priority: .userInitiated) { compute(key) }.value
            guard !Task.isCancelled else { return }
            report = result
        }
    }
}

// MARK: - Display names

extension PolarState {
    func noEventLabel(body: Body) -> String {
        switch (self, body) {
        case (.alwaysAbove, .sun): String(localized: "Sun up all day")
        case (.alwaysBelow, .sun): String(localized: "Sun down all day")
        case (.alwaysAbove, .moon): String(localized: "Moon up all day")
        case (.alwaysBelow, .moon): String(localized: "Moon down all day")
        case (.normal, _): String(localized: "None today")
        }
    }
}

extension LightPhase {
    var displayName: String {
        switch self {
        case .night: String(localized: "Night")
        case .astronomicalTwilight: String(localized: "Astronomical twilight")
        case .nauticalTwilight: String(localized: "Nautical twilight")
        case .blueHour: String(localized: "Blue hour")
        case .goldenHour: String(localized: "Golden hour")
        case .day: String(localized: "Daylight")
        }
    }
}

extension Season {
    var displayName: String {
        switch self {
        case .spring: String(localized: "Spring")
        case .summer: String(localized: "Summer")
        case .autumn: String(localized: "Autumn")
        case .winter: String(localized: "Winter")
        }
    }
}

extension SeasonMarker {
    var displayName: String {
        switch self {
        case .marchEquinox: String(localized: "March equinox")
        case .juneSolstice: String(localized: "June solstice")
        case .septemberEquinox: String(localized: "September equinox")
        case .decemberSolstice: String(localized: "December solstice")
        }
    }
}

extension MoonQuarter {
    var displayName: String {
        switch self {
        case .new: String(localized: "New Moon")
        case .firstQuarter: String(localized: "First quarter")
        case .full: String(localized: "Full Moon")
        case .lastQuarter: String(localized: "Last quarter")
        }
    }

    /// Elongation of the phase, for drawing its disc.
    var elongation: Double { Double(rawValue) * 90 }
}

extension NightDarkness {
    var explanation: String? {
        switch self {
        case .fullNight: nil
        case .astronomicalTwilightAllNight:
            String(localized: "The Sun stays above −18° all night: no astronomical night.")
        case .nauticalTwilightAllNight:
            String(localized: "The Sun stays above −12° all night: nautical twilight lasts until dawn.")
        case .civilTwilightAllNight:
            String(localized: "The Sun stays above −6° all night: civil twilight lasts until dawn.")
        case .midnightSun:
            String(localized: "Midnight sun: the Sun stays above the horizon all day.")
        }
    }
}

// MARK: - Sky path chart

/// Elevation of the Sun or Moon across the local day, with light bands for the Sun,
/// the horizon, and a marker at the selected instant.
struct SkyPathChart: View {
    let path: SkyPath
    let day: LocalDay
    let selected: Date
    let format: PillFormat
    var thresholds: SolarThresholds = .standard

    private struct Band: Identifiable {
        let lower: Double
        let upper: Double
        let color: Color
        var id: Double { lower }
    }

    private var yDomain: ClosedRange<Double> {
        let lo = path.lowest?.altitude ?? -90
        let hi = path.highest?.altitude ?? 90
        return max(-90, (lo - 5).rounded(.down))...min(90, (hi + 5).rounded(.up))
    }

    private var bands: [Band] {
        guard path.body == .sun else { return [] }
        let t = thresholds
        return [
            Band(lower: t.astronomical, upper: t.nautical, color: .indigo.opacity(0.25)),
            Band(lower: t.nautical, upper: t.blueLower, color: .indigo.opacity(0.15)),
            Band(lower: t.blueLower, upper: t.blueUpper, color: .blue.opacity(0.25)),
            Band(lower: t.goldenLower, upper: t.goldenUpper, color: .orange.opacity(0.25)),
        ]
    }

    private var ticks: [Date] {
        stride(from: 0.0, through: day.end.timeIntervalSince(day.start), by: 3 * 3600).map { day.start.addingTimeInterval($0) }
    }

    var body: some View {
        Chart {
            ForEach(bands) { band in
                RectangleMark(
                    xStart: .value("Start", day.start), xEnd: .value("End", day.end),
                    yStart: .value("Lower", max(band.lower, yDomain.lowerBound)),
                    yEnd: .value("Upper", min(band.upper, yDomain.upperBound))
                )
                .foregroundStyle(band.color)
            }
            RuleMark(y: .value("Horizon", 0.0))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            ForEach(path.samples) { sample in
                LineMark(x: .value("Time", sample.time), y: .value("Elevation", sample.altitude))
                    .foregroundStyle(path.body == .sun ? Color.orange : Color.gray)
                    .interpolationMethod(.catmullRom)
            }
            if selected >= day.start && selected <= day.end {
                RuleMark(x: .value("Selected", selected))
                    .foregroundStyle(.tint)
            }
        }
        .chartXScale(domain: day.start...day.end)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(format.time(date)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let degrees = value.as(Double.self) { Text("\(Int(degrees))°") }
                }
            }
        }
        .frame(height: 220)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let high = path.highest else { return "" }
        let body = path.body == .sun ? String(localized: "Sun") : String(localized: "Moon")
        return String(localized: "\(body) elevation graph. Highest \(Formatting.degrees(high.altitude)) at \(format.time(high.time)).")
    }
}

