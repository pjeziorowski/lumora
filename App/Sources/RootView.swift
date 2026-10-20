// App/Sources/RootView.swift

import PlannerKit
import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case planner
    case pills
    case myStuff
    case settings

    var title: LocalizedStringKey {
        switch self {
        case .planner: "Planner"
        case .pills: "Tools"
        case .myStuff: "My Stuff"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .planner: "map"
        case .pills: "square.grid.2x2"
        case .myStuff: "folder"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @State private var selection: AppTab = .planner

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                NavigationStack {
                    content(for: tab)
                        .navigationTitle(tab.title)
                }
                .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                .tag(tab)
            }
        }
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .planner: PlannerPlaceholderView()
        case .pills: ToolsView()
        case .myStuff: PlaceholderView(message: "Saved plans, places and cameras arrive in Phase 7.")
        case .settings: SettingsView()
        }
    }
}

#Preview {
    RootView()
        .environment(PillSession(defaults: nil))
}
