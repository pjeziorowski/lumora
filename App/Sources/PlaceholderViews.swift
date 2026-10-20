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

struct ToolsPlaceholderView: View {
    private struct Tool: Identifiable {
        let name: LocalizedStringKey
        let systemImage: String
        let phase: String
        var id: String { systemImage }
    }

    private let tools: [Tool] = [
        Tool(name: "Sun", systemImage: "sun.max", phase: "Phase 2"),
        Tool(name: "Moon", systemImage: "moon", phase: "Phase 2"),
        Tool(name: "Milky Way", systemImage: "sparkles", phase: "Phase 4"),
        Tool(name: "Exposure", systemImage: "camera.aperture", phase: "Phase 5"),
        Tool(name: "Depth of field", systemImage: "scope", phase: "Phase 5"),
        Tool(name: "Field of view", systemImage: "viewfinder", phase: "Phase 5"),
        Tool(name: "Spot stars", systemImage: "star", phase: "Phase 5"),
        Tool(name: "Star trails", systemImage: "circle.dashed", phase: "Phase 5"),
        Tool(name: "Time lapse", systemImage: "timer", phase: "Phase 5"),
        Tool(name: "Meteor showers", systemImage: "moon.stars", phase: "Phase 9"),
    ]

    var body: some View {
        List(tools) { tool in
            LabeledContent {
                Text(tool.phase).foregroundStyle(.secondary)
            } label: {
                Label(tool.name, systemImage: tool.systemImage)
            }
        }
    }
}
