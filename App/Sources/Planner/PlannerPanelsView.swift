// App/Sources/Planner/PlannerPanelsView.swift
//
// The swipeable information panels above the Planner map, with a row of panel buttons
// (also the VoiceOver-friendly way to switch panels). Rows come ready-made from PlannerKit.
// At accessibility text sizes each row stacks its label above its value so nothing is cut.

import PlannerKit
import SwiftUI

struct PlannerPanelsView: View {
    @Bindable var state: PlannerState
    let options: PlannerDisplayOptions

    var body: some View {
        let panels = state.panels(options: options)
        VStack(spacing: 6) {
            PanelTabBar(selection: $state.selectedPanel)

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

/// One button per panel, each at least 44 pt square (wider when the icons grow with the text
/// size). They share the width evenly when they fit and scroll sideways when they do not, on
/// narrow phones or at large text sizes; the selected panel's button is kept in view.
private struct PanelTabBar: View {
    @Binding var selection: PlannerPanelKind
    /// Room for the icon; it grows with the text size like the icon does.
    @ScaledMetric(relativeTo: .subheadline) private var iconRoom: CGFloat = 24

    private var minSide: CGFloat { max(44, iconRoom + 12) }

    var body: some View {
        let side = minSide
        let count = CGFloat(PlannerPanelKind.allCases.count)
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(PlannerPanelKind.allCases) { kind in
                        tab(kind)
                            .containerRelativeFrame(.horizontal) { width, _ in max(side, width / count) }
                            .id(kind)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onChange(of: selection) {
                withAnimation(.snappy) { proxy.scrollTo(selection, anchor: .center) }
            }
        }
    }

    private func tab(_ kind: PlannerPanelKind) -> some View {
        Button {
            withAnimation(.snappy) { selection = kind }
        } label: {
            Image(systemName: kind.systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: minSide)
                .background(selection == kind ? Color.accentColor.opacity(0.2) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selection == kind ? AnyShapeStyle(.tint) : AnyShapeStyle(.subdued))
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(selection == kind ? .isSelected : [])
        .accessibilityIdentifier("planner.panelTab.\(kind.rawValue)")
    }
}

private struct PanelCard: View {
    let kind: PlannerPanelKind
    let panel: PlannerPanel?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(kind.title, systemImage: kind.systemImage)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("planner.panel.\(kind.rawValue)")
            if let panel {
                ScrollView {
                    if typeSize.isAccessibilitySize {
                        stackedRows(panel.rows)
                    } else {
                        gridRows(panel.rows)
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

    /// Label and value side by side, values right-aligned in a second column.
    private func gridRows(_ rows: [PanelRow]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            ForEach(rows) { row in
                GridRow {
                    Text(row.label)
                        .foregroundStyle(.subdued)
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

    /// Label above value, both leading, so long values wrap within the screen width.
    private func stackedRows(_ rows: [PanelRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.label)
                        .foregroundStyle(.subdued)
                    Text(row.value)
                        .monospacedDigit()
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
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
        case .meteors: "moon.stars"
        case .eclipse: "circle.lefthalf.filled"
        }
    }
}
