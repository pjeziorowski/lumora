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
            Section("Photography") {
                NavigationLink {
                    ExposureView()
                } label: {
                    Label("Exposure", systemImage: "camera.aperture")
                }
                NavigationLink {
                    DepthOfFieldView()
                } label: {
                    Label("Depth of field", systemImage: "scope")
                }
                NavigationLink {
                    FieldOfViewView()
                } label: {
                    Label("Field of view", systemImage: "viewfinder")
                }
                NavigationLink {
                    SpotStarsView()
                } label: {
                    Label("Spot stars", systemImage: "star")
                }
                NavigationLink {
                    StarTrailsView()
                } label: {
                    Label("Star trails", systemImage: "circle.dashed")
                }
                NavigationLink {
                    TimeLapseView()
                } label: {
                    Label("Time lapse", systemImage: "timer")
                }
                NavigationLink {
                    CameraManagerView()
                } label: {
                    Label("Cameras", systemImage: "camera")
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
