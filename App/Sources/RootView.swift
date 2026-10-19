// App/Sources/RootView.swift

import CameraCatalog
import PlannerKit
import SwiftData
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
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.tab) {
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
        case .planner: PlannerView()
        case .pills: ToolsView()
        case .myStuff: MyStuffView()
        case .settings: SettingsView()
        }
    }
}

#Preview {
    let session = PillSession(defaults: nil)
    return RootView()
        .environment(session)
        .environment(PlannerState(session: session))
        .environment(CameraStore(defaults: nil))
        .environment(AppNavigation())
        .modelContainer(for: [PlanRecord.self, PlaceRecord.self], inMemory: true)
}
