// App/Sources/Pills/MeteorShowersView.swift
//
// Meteor showers: the year's showers for the selected place with their peak night rated
// (radiant height, darkness, Moon), and a night view of one shower hour by hour. Numbers come
// from PlannerKit's MeteorShowerCalendar and MeteorNightReport.

import AstroCore
import Charts
import PlannerKit
import SwiftUI

private struct YearKey: Equatable, Sendable {
    let location: PillLocation
    let year: Int
}

struct MeteorShowersView: View {
    @Environment(PillSession.self) private var session
    @AppStorage(SettingsKeys.clockStyle) private var clock: ClockStyle = .twentyFourHour

    var body: some View {
        let format = PillFormat(timeZone: session.timeZone, clock: clock)
        List {
            PillHeader()
            ReportLoader(key: YearKey(location: session.location, year: session.day.year)) { key in
                MeteorShowerCalendar.year(key.year, location: key.location)
            } content: { showers in
                Section {
                    ForEach(showers) { summary in
                        NavigationLink {
                            MeteorShowerDetailView(summary: summary)
                        } label: {
                            ShowerRow(summary: summary, format: format)
                        }
                        .accessibilityIdentifier("meteors.\(summary.shower.code)")
                    }
                } header: {
                    Text("Showers in \(String(session.day.year))")
                } footer: {
                    Text("Rates are for one observer on the peak night: ZHR × sin(radiant height), reduced for twilight and moonlight.")
                }
            }
        }
        .navigationTitle("Meteor showers")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ShowerRow: View {
    let summary: MeteorShowerSummary
    let format: PillFormat

    var body: some View {
        let night = summary.peakNight
        HStack(spacing: 12) {
            RatingBadge(rating: night.rating)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.shower.name).font(.headline)
                Text(format.dateAndTime(summary.peak)).font(.subheadline).foregroundStyle(.secondary)
                Text("ZHR \(Int(summary.shower.zhr)) · Moon \(Int((night.moonIllumination * 100).rounded()))%"
                     + (night.best.map { " · ≈ \(Int($0.rate.rounded()))/h here" } ?? " · radiant not up in the dark"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct RatingBadge: View {
    let rating: MeteorRating

    var body: some View {
        let color: Color = switch rating {
        case .excellent: .green
        case .good: .teal
        case .fair: .orange
        case .poor: .gray
        }
        Text(rating.label)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .frame(width: 66, height: 22)
            .background(color, in: Capsule())
    }
}

struct MeteorShowerDetailView: View {
    let summary: MeteorShowerSummary
    @Environment(PillSession.self) private var session
    @AppStorage(SettingsKeys.clockStyle) private var clock: ClockStyle = .twentyFourHour

    var body: some View {
        let format = PillFormat(timeZone: session.timeZone, clock: clock)
        let night = summary.peakNight
        let shower = summary.shower
        List {
            Section("Peak night") {
                ValueRow("Peak", format.dateAndTime(summary.peak))
                if let best = night.best {
                    ValueRow("Best time", "\(format.time(best.time)) · ≈ \(Int(best.rate.rounded())) per hour")
                    ValueRow("Radiant then", "\(Formatting.azimuth(best.radiantAzimuth)) · el \(Formatting.degrees(best.radiantAltitude))")
                } else {
                    ValueRow("Best time", String(localized: "The radiant is not up while the sky is dark"))
                }
                ValueRow("Useful hours", String(format: "%.1f h", night.usefulHours))
                ValueRow("Moon", "\(Int((night.moonIllumination * 100).rounded()))% lit")
                HStack {
                    Text("Conditions")
                    Spacer()
                    RatingBadge(rating: night.rating)
                }
            }
            Section("Through the night") {
                RateChart(report: night, format: format)
                    .padding(.vertical, 8)
            }
            Section("Shower") {
                ValueRow("Active", "\(format.date(summary.active.start)) – \(format.date(summary.active.end.addingTimeInterval(-1)))")
                ValueRow("ZHR", "\(Int(shower.zhr))")
                ValueRow("Radiant at peak", String(format: "RA %.0f°, Dec %+.0f°", shower.radiantRA, shower.radiantDec))
                ValueRow("Speed", "\(Int(shower.speed)) km/s")
                ValueRow("Population index", String(format: "%.1f", shower.populationIndex))
            }
        }
        .navigationTitle(shower.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Expected rate (bars) and radiant elevation (line) from noon to noon.
private struct RateChart: View {
    let report: MeteorNightReport
    let format: PillFormat

    var body: some View {
        let start = report.samples.first?.time ?? Date()
        let end = report.samples.last?.time ?? Date()
        let ticks = stride(from: 0.0, through: end.timeIntervalSince(start), by: 4 * 3600).map { start.addingTimeInterval($0) }
        Chart {
            ForEach(report.samples) { sample in
                BarMark(x: .value("Time", sample.time), y: .value("Rate", sample.rate), width: .fixed(3))
                    .foregroundStyle(Color.teal)
                LineMark(x: .value("Time", sample.time), y: .value("Radiant", max(0, sample.radiantAltitude)),
                         series: .value("Series", "Radiant"))
                    .foregroundStyle(Color.purple)
            }
        }
        .chartXScale(domain: start...end)
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisGridLine()
                AxisValueLabel { if let date = value.as(Date.self) { Text(format.time(date)) } }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 180)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 12) {
                Label("Meteors per hour", systemImage: "square.fill").foregroundStyle(.teal)
                Label("Radiant height (°)", systemImage: "line.diagonal").foregroundStyle(.purple)
            }
            .font(.caption2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Expected meteors per hour and radiant height through the night"))
    }
}
