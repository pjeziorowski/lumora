// App/Sources/Planner/TimeBarView.swift
//
// The Planner's time controls: a date/time line with day steps, a horizontal ruler you drag
// to scrub time (one point = one minute, coloured by the light at each moment), and the
// jump buttons. The ruler is an adjustable control for VoiceOver (15-minute steps) and
// ticks a selection haptic on every hour while scrubbing.

import PlannerKit
import SwiftUI

struct TimeBarView: View {
    let state: PlannerState
    let zone: TimeZone
    let clock: ClockStyle
    @State private var showingDatePicker = false
    /// The ruler grows with Dynamic Type so its hour labels keep room below the ticks.
    @ScaledMetric(relativeTo: .caption2) private var rulerHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    state.shift(days: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Previous day")
                Button {
                    showingDatePicker = true
                } label: {
                    VStack(spacing: 0) {
                        Text(dayText)
                            .font(.caption)
                            .foregroundStyle(.subdued)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Formatting.clockTime(state.session.instant, timeZone: zone, style: clock))
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("planner.time")
                .accessibilityHint("Choose a date and time")
                Button {
                    state.shift(days: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Next day")
            }
            .font(.body.weight(.semibold))
            .padding(.horizontal)

            TimeRuler(state: state, zone: zone, clock: clock)
                .frame(height: min(rulerHeight, 96))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PlannerJump.allCases) { jump in
                        Button {
                            state.jump(jump)
                        } label: {
                            Label(jump.title, systemImage: jump.systemImage)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!state.canJump(jump))
                        .opacity(state.canJump(jump) ? 1 : 0.4)
                        .accessibilityIdentifier("planner.jump.\(jump.rawValue)")
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showingDatePicker) {
            DateTimeSheet(session: state.session, zone: zone) { state.refresh() }
                .presentationDetents([.medium, .large])
        }
    }

    private var dayText: String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted).weekday(.abbreviated)
        style.timeZone = zone
        return "\(state.session.instant.formatted(style)) · \(Formatting.utcOffset(zone, at: state.session.instant))"
    }
}

private struct DateTimeSheet: View {
    @Bindable var session: PillSession
    let zone: TimeZone
    let onChange: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date and time", selection: $session.instant)
                    .datePickerStyle(.graphical)
                    .environment(\.timeZone, zone)
            }
            .navigationTitle("Date and time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: session.instant) { onChange() }
        }
    }
}

/// Drag left to move forward in time. Six hours are visible; the needle marks the instant.
struct TimeRuler: View {
    let state: PlannerState
    let zone: TimeZone
    let clock: ClockStyle
    @State private var lastTranslation: CGFloat = 0
    @State private var carry: CGFloat = 0
    /// Minutes per point of drag.
    private let minutesPerPoint: CGFloat = 1
    /// Hour labels follow Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let delta = value.translation.width - lastTranslation + carry
                    lastTranslation = value.translation.width
                    let minutes = Int((-delta * minutesPerPoint).rounded(.towardZero))
                    carry = delta + CGFloat(minutes) / minutesPerPoint
                    state.scrub(minutes: minutes)
                }
                .onEnded { _ in
                    lastTranslation = 0
                    carry = 0
                }
        )
        .sensoryFeedback(.selection, trigger: hourStamp)
        .accessibilityElement()
        .accessibilityLabel("Time")
        .accessibilityValue(Formatting.clockTime(state.session.instant, timeZone: zone, style: clock))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: state.scrub(minutes: 15)
            case .decrement: state.scrub(minutes: -15)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("planner.timebar")
    }

    private var hourStamp: Int { Int(state.session.instant.timeIntervalSince1970 / 3600) }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let instant = state.session.instant
        let halfSpan = Double(size.width / 2) * Double(minutesPerPoint) * 60
        let start = instant.addingTimeInterval(-halfSpan)
        let end = instant.addingTimeInterval(halfSpan)
        func x(_ date: Date) -> CGFloat {
            CGFloat(date.timeIntervalSince(start) / (end.timeIntervalSince(start))) * size.width
        }

        // Light bands.
        for band in state.snapshot?.day.lightBands ?? [] where band.end > start && band.start < end {
            let x0 = max(0, x(band.start)), x1 = min(size.width, x(band.end))
            context.fill(Path(CGRect(x: x0, y: 0, width: x1 - x0, height: size.height * 0.45)), with: .color(band.phase.color))
        }

        // Hour ticks and labels.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let resolver = context
        func label(_ date: Date) -> GraphicsContext.ResolvedText {
            resolver.resolve(Text(Formatting.clockTime(date, timeZone: zone, style: clock))
                .font(.system(size: labelSize, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85)))
        }
        // At large text sizes the labels are wider than an hour: label every second or third hour.
        let hourWidth = 3600 / (Double(minutesPerPoint) * 60)
        let widest = cal.date(bySettingHour: 22, minute: 0, second: 0, of: instant).map { label($0).measure(in: size).width } ?? 0
        let labelEvery = max(1, Int((Double(widest) + 6) / hourWidth) + 1)
        var tick = cal.dateInterval(of: .hour, for: start)?.start ?? start
        while tick <= end {
            let tx = x(tick)
            let minute = cal.component(.minute, from: tick)
            let isHour = minute == 0
            let height = isHour ? size.height * 0.3 : size.height * 0.15
            context.fill(Path(CGRect(x: tx - 0.5, y: size.height * 0.45, width: 1, height: height)),
                         with: .color(.white.opacity(isHour ? 0.9 : 0.5)))
            if isHour, cal.component(.hour, from: tick) % labelEvery == 0 {
                context.draw(label(tick), at: CGPoint(x: tx, y: size.height - 2), anchor: .bottom)
            }
            tick = tick.addingTimeInterval(15 * 60)
        }

        // Needle.
        let mid = size.width / 2
        context.fill(Path(CGRect(x: mid - 1.5, y: 0, width: 3, height: size.height)), with: .color(.red))
    }
}

extension LightPhase {
    var color: Color {
        switch self {
        case .night: Color(red: 0.05, green: 0.06, blue: 0.16)
        case .astronomicalTwilight: Color(red: 0.10, green: 0.13, blue: 0.32)
        case .nauticalTwilight: Color(red: 0.16, green: 0.24, blue: 0.52)
        case .blueHour: Color(red: 0.20, green: 0.42, blue: 0.85)
        case .goldenHour: Color(red: 0.98, green: 0.70, blue: 0.22)
        case .day: Color(red: 0.62, green: 0.82, blue: 0.98)
        }
    }
}

extension PlannerJump {
    var systemImage: String {
        switch self {
        case .now: "clock"
        case .sunrise: "sunrise"
        case .sunset: "sunset"
        case .goldenHour: "sun.horizon"
        case .blueHour: "moon.haze"
        case .moonrise: "moon.circle"
        case .moonset: "moon.zzz"
        case .milkyWayStart: "sparkles"
        case .milkyWayEnd: "sparkle"
        }
    }
}
