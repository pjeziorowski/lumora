// App/Sources/Widgets/WidgetGalleryView.swift
//
// Settings > Widgets: every widget at its real size for the selected place and moment, with
// the lock-screen styles on a dark background, and how to add them. Uses the same faces and
// snapshots as the widget extension.

import PlannerKit
import SwiftData
import SwiftUI
import WidgetKit

struct WidgetGalleryView: View {
    @Environment(PillSession.self) private var session
    @AppStorage(SettingsKeys.clockStyle) private var clock: ClockStyle = .twentyFourHour
    @Query(sort: \PlanRecord.instant) private var records: [PlanRecord]
    @State private var contents: [LumoraWidgetKind: LumoraWidgetContent] = [:]
    @State private var kind: LumoraWidgetKind = .sun

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Widget", selection: $kind) {
                    ForEach(LumoraWidgetKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("widgets.kind")
                Text(kind.summary).font(.subheadline).foregroundStyle(.secondary)
                if let content = contents[kind] {
                    Text("Home Screen").font(.headline)
                    HStack(spacing: 14) {
                        tile(content, family: .systemSmall, size: CGSize(width: 158, height: 158))
                        Spacer(minLength: 0)
                    }
                    tile(content, family: .systemMedium, size: CGSize(width: 338, height: 158))
                    Text("Lock Screen").font(.headline)
                    LockScreenSample(kind: kind, content: content)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
                Text("To add a widget, touch and hold the Home Screen or Lock Screen, tap Edit, then Add Widgets, and choose Lumora. Widgets use the place selected here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: Key(location: session.location, instant: session.instant, clock: clock, plans: records.count)) {
            let location = session.location, instant = session.instant, clock = clock
            let plans = records.compactMap(\.plan)
            contents = await Task.detached {
                let widgetPlans = plans.map(WidgetPlan.init)
                var result: [LumoraWidgetKind: LumoraWidgetContent] = [:]
                for kind in LumoraWidgetKind.allCases {
                    result[kind] = .compute(kind: kind, location: location, instant: instant, clock: clock, plans: widgetPlans)
                }
                return result
            }.value
        }
    }

    private func tile(_ content: LumoraWidgetContent, family: WidgetFamily, size: CGSize) -> some View {
        LumoraWidgetFace(kind: kind, content: content, family: family)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(LumoraWidgetFace.background(kind: kind, content: content))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("widgets.\(family.debugName)")
    }

    private struct Key: Equatable {
        let location: PillLocation
        let instant: Date
        let clock: ClockStyle
        let plans: Int
    }
}

/// The lock-screen families over a dark wallpaper, tinted as the system draws them.
private struct LockScreenSample: View {
    let kind: LumoraWidgetKind
    let content: LumoraWidgetContent

    var body: some View {
        VStack(spacing: 12) {
            LumoraWidgetFace(kind: kind, content: content, family: .accessoryInline)
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            HStack(spacing: 14) {
                // AccessoryWidgetBackground draws nothing outside WidgetKit, so stand in for it here.
                LumoraWidgetFace(kind: kind, content: content, family: .accessoryCircular)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(.white.opacity(0.18)))
                LumoraWidgetFace(kind: kind, content: content, family: .accessoryRectangular)
                    .frame(width: 172, height: 72)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding(.vertical, 22)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.24), Color(red: 0.30, green: 0.18, blue: 0.36)],
                                   startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("widgets.lockScreen")
    }
}

private extension WidgetFamily {
    var debugName: String {
        switch self {
        case .systemSmall: "small"
        case .systemMedium: "medium"
        case .accessoryCircular: "circular"
        case .accessoryRectangular: "rectangular"
        case .accessoryInline: "inline"
        default: "other"
        }
    }
}
