// App/Sources/Pills/EclipsesView.swift
//
// Eclipses: the next solar and lunar eclipses with whether they can be seen from the selected
// place, and for each its local contact times, the Sun's or Moon's height at each, coverage,
// and the centre line of a total or annular solar eclipse on a map. Numbers come from
// PlannerKit's EclipseCalendar.

import AstroCore
import GeoCore
import MapKit
import PlannerKit
import SwiftUI

private struct ListKey: Equatable, Sendable {
    let location: PillLocation
    let start: Date
}

struct EclipsesView: View {
    @Environment(PillSession.self) private var session
    @AppStorage(SettingsKeys.clockStyle) private var clock: ClockStyle = .twentyFourHour

    var body: some View {
        let format = PillFormat(timeZone: session.timeZone, clock: clock)
        List {
            PillHeader()
            ReportLoader(key: ListKey(location: session.location, start: session.day.start)) { key in
                EclipseCalendar.upcoming(location: key.location, from: key.start, count: 12)
            } content: { eclipses in
                Section("Next eclipses") {
                    ForEach(eclipses) { eclipse in
                        NavigationLink {
                            EclipseDetailView(eclipse: eclipse)
                        } label: {
                            EclipseRow(eclipse: eclipse, format: format)
                        }
                        .accessibilityIdentifier("eclipse.row")
                    }
                }
            }
        }
        .navigationTitle("Eclipses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EclipseRow: View {
    let eclipse: EclipseSummary
    let format: PillFormat

    var body: some View {
        HStack(spacing: 12) {
            EclipseGlyph(disc: eclipse.body, kind: eclipse.localKind ?? eclipse.kind)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(eclipse.title).font(.headline)
                Text(format.dateAndTime(eclipse.peak)).font(.subheadline).foregroundStyle(.secondary)
                Text(eclipse.visibleHere ? String(localized: "Visible here") : String(localized: "Not visible here"))
                    .font(.caption.bold())
                    .foregroundStyle(eclipse.visibleHere ? .green : .secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A disc with the eclipsing body's shadow: dark for the Moon over the Sun, red-brown for the
/// Earth's umbra on the Moon.
struct EclipseGlyph: View {
    let disc: EclipseSummary.Body
    let kind: EclipseKind

    var body: some View {
        Canvas { context, size in
            let d = min(size.width, size.height)
            let sun = self.disc == .sun
            let disc = CGRect(x: (size.width - d) / 2, y: (size.height - d) / 2, width: d, height: d)
            let base: Color = sun ? .orange : Color(white: 0.85)
            context.fill(Path(ellipseIn: disc), with: .color(base))
            let shadow: Color = sun ? .black : Color(red: 0.55, green: 0.2, blue: 0.1)
            switch kind {
            case .total:
                context.fill(Path(ellipseIn: disc.insetBy(dx: sun ? 1 : 0, dy: sun ? 1 : 0)), with: .color(shadow.opacity(0.9)))
            case .annular:
                context.fill(Path(ellipseIn: disc.insetBy(dx: d * 0.12, dy: d * 0.12)), with: .color(shadow))
            case .partial:
                context.fill(Path(ellipseIn: disc.offsetBy(dx: d * 0.45, dy: -d * 0.2)), with: .color(shadow.opacity(0.85)))
            case .penumbral:
                context.fill(Path(ellipseIn: disc), with: .color(.black.opacity(0.25)))
            }
            context.stroke(Path(ellipseIn: disc), with: .color(base), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

struct EclipseDetailView: View {
    let eclipse: EclipseSummary
    @Environment(PillSession.self) private var session
    @AppStorage(SettingsKeys.clockStyle) private var clock: ClockStyle = .twentyFourHour
    @AppStorage(SettingsKeys.coordinateStyle) private var coordinates: CoordinateStyle = .decimal

    var body: some View {
        let format = PillFormat(timeZone: session.timeZone, clock: clock)
        List {
            Section {
                HStack(spacing: 14) {
                    EclipseGlyph(disc: eclipse.body, kind: eclipse.localKind ?? eclipse.kind)
                        .frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(eclipse.title).font(.title3.weight(.semibold))
                        if eclipse.title != eclipse.globalTitle {
                            Text("\(eclipse.globalTitle) elsewhere").font(.subheadline)
                        }
                        Text(format.dateAndTime(eclipse.peak)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            if eclipse.contacts.isEmpty {
                Section {
                    Text("Not visible from \(session.location.name).").foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(eclipse.contacts) { contact in
                        LabeledContent(contact.label) {
                            HStack(spacing: 8) {
                                Text(format.time(contact.time)).monospacedDigit()
                                Text(Formatting.degrees(contact.altitude, decimals: 0))
                                    .monospacedDigit()
                                    .foregroundStyle(contact.altitude > 0 ? Color.primary : Color.secondary)
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                    }
                } header: {
                    Text("From \(session.location.name)")
                } footer: {
                    Text(eclipse.body == .sun
                         ? "Times in the place's time zone; the second column is the Sun's height. Below 0° it is set."
                         : "Times in the place's time zone; the second column is the Moon's height. Below 0° it is set.")
                }
                if let magnitude = eclipse.magnitude, let obscuration = eclipse.obscuration {
                    Section("Coverage") {
                        ValueRow("Magnitude", String(format: "%.3f", magnitude))
                        ValueRow("Sun covered", "\(Int((obscuration * 100).rounded()))%")
                    }
                } else if eclipse.body == .moon, let obscuration = eclipse.obscuration, eclipse.kind == .partial {
                    Section("Coverage") {
                        ValueRow("Moon in the umbra", "\(Int((obscuration * 100).rounded()))%")
                    }
                }
            }
            if eclipse.body == .sun, let point = eclipse.greatestPoint {
                Section {
                    ValueRow("Greatest eclipse", Formatting.coordinate(latitude: point.latitude, longitude: point.longitude,
                                                                      style: coordinates))
                    CentralLineMap(peak: eclipse.peak, greatest: point, pin: session.location.geoPoint)
                        .frame(height: 240)
                        .listRowInsets(EdgeInsets())
                } header: {
                    Text("Path of \(eclipse.kind == .annular ? "annularity" : "totality")")
                }
            }
        }
        .navigationTitle(eclipse.body == .sun ? "Solar eclipse" : "Lunar eclipse")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The centre line on a world map, with the place and the point of greatest eclipse.
private struct CentralLineMap: View {
    let peak: Date
    let greatest: GeoPoint
    let pin: GeoPoint
    @State private var line: [GeoPoint] = []

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: greatest.latitude, longitude: greatest.longitude),
            span: MKCoordinateSpan(latitudeDelta: 70, longitudeDelta: 120)))) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                MapPolyline(coordinates: run.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                    .stroke(.red, lineWidth: 3)
            }
            Marker("Greatest", systemImage: "sun.max.fill",
                   coordinate: CLLocationCoordinate2D(latitude: greatest.latitude, longitude: greatest.longitude))
                .tint(.orange)
            Marker("You", systemImage: "mappin",
                   coordinate: CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude))
                .tint(.blue)
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .task(id: peak) {
            let peak = peak
            line = await Task.detached { EclipseCalendar.centralLine(peak: peak) }.value
        }
        .accessibilityLabel(String(localized: "Map of the eclipse path"))
    }

    /// The line split where it crosses the antimeridian.
    private var runs: [[GeoPoint]] {
        var result: [[GeoPoint]] = []
        var run: [GeoPoint] = []
        for p in line {
            if let last = run.last, abs(p.longitude - last.longitude) > 180 {
                result.append(run)
                run = []
            }
            run.append(p)
        }
        if run.count > 1 { result.append(run) }
        return result
    }
}
