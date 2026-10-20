// App/Sources/Planner/PlannerPanelsView.swift
//
// The swipeable information panels above the Planner map, with a row of panel buttons
// (also the VoiceOver-friendly way to switch panels). Rows come ready-made from PlannerKit.

import PlannerKit
import SwiftUI

struct PlannerPanelsView: View {
    @Bindable var state: PlannerState
    let options: PlannerDisplayOptions

    var body: some View {
        let panels = state.panels(options: options)
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(PlannerPanelKind.allCases) { kind in
                    Button {
                        withAnimation(.snappy) { state.selectedPanel = kind }
                    } label: {
                        Label(kind.title, systemImage: kind.systemImage)
                            .labelStyle(.iconOnly)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(state.selectedPanel == kind ? Color.accentColor.opacity(0.2) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(state.selectedPanel == kind ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .accessibilityLabel(kind.title)
                    .accessibilityAddTraits(state.selectedPanel == kind ? .isSelected : [])
                    .accessibilityIdentifier("planner.panelTab.\(kind.rawValue)")
                }
            }
            .padding(.horizontal, 12)

            TabView(selection: $state.selectedPanel) {
                ForEach(PlannerPanelKind.allCases) { kind in
                    PanelCard(kind: kind, panel: panels.first { $0.kind == kind })
                        .tag(kind)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .padding(.top, 6)
    }
}

private struct PanelCard: View {
    let kind: PlannerPanelKind
    let panel: PlannerPanel?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(kind.title, systemImage: kind.systemImage)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("planner.panel.\(kind.rawValue)")
            if let panel {
                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                        ForEach(panel.rows) { row in
                            GridRow {
                                Text(row.label)
                                    .foregroundStyle(.secondary)
                                Text(row.value)
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .multilineTextAlignment(.trailing)
                            }
                            .font(.subheadline)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                Spacer()
                ProgressView()
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension PlannerPanelKind {
    var systemImage: String {
        switch self {
        case .pin: "mappin.and.ellipse"
        case .sun: "sun.max"
        case .moon: "moon"
        case .twilights: "sun.horizon"
        case .milkyWay: "sparkles"
        case .geodetics: "ruler"
        case .obstacle: "building.2"
        }
    }
}
