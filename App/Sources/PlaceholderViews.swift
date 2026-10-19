// App/Sources/PlaceholderViews.swift

import SwiftUI

struct PlaceholderView: View {
    let message: LocalizedStringKey

    var body: some View {
        ContentUnavailableView {
            Label("Coming soon", systemImage: "hammer")
        } description: {
            Text(message)
        }
    }
}

struct ToolsView: View {
    private struct Upcoming: Identifiable {
        let name: LocalizedStringKey
        let systemImage: String
        let phase: String
        var id: String { systemImage }
    }

    private let upcoming: [Upcoming] = [
        Upcoming(name: "Exposure", systemImage: "camera.aperture", phase: "Phase 5"),
        Upcoming(name: "Depth of field", systemImage: "scope", phase: "Phase 5"),
        Upcoming(name: "Field of view", systemImage: "viewfinder", phase: "Phase 5"),
        Upcoming(name: "Spot stars", systemImage: "star", phase: "Phase 5"),
        Upcoming(name: "Star trails", systemImage: "circle.dashed", phase: "Phase 5"),
        Upcoming(name: "Time lapse", systemImage: "timer", phase: "Phase 5"),
        Upcoming(name: "Meteor showers", systemImage: "moon.stars", phase: "Phase 9"),
    ]

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SunPillView()
                } label: {
                    Label("Sun", systemImage: "sun.max")
                }
                NavigationLink {
                    MoonPillView()
                } label: {
                    Label("Moon", systemImage: "moon")
                }
                NavigationLink {
                    MilkyWayPillView()
                } label: {
                    Label("Milky Way", systemImage: "sparkles")
                }
            }
            Section("Coming later") {
                ForEach(upcoming) { tool in
                    LabeledContent {
                        Text(tool.phase).foregroundStyle(.secondary)
                    } label: {
                        Label(tool.name, systemImage: tool.systemImage)
                    }
                }
            }
        }
    }
}
