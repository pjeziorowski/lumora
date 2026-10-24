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
            TitledSection("Events") {
                NavigationLink {
                    MeteorShowersView()
                } label: {
                    Label("Meteor showers", systemImage: "moon.stars")
                }
                NavigationLink {
                    EclipsesView()
                } label: {
                    Label("Eclipses", systemImage: "circle.lefthalf.filled")
                }
            }
            TitledSection("Photography") {
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
            TitledSection("Augmented reality") {
                NavigationLink {
                    SkyARView(mode: .sunMoon)
                } label: {
                    Label("Sun & Moon AR", systemImage: "sun.horizon")
                }
                NavigationLink {
                    SkyARView(mode: .milkyWay)
                } label: {
                    Label("Milky Way AR", systemImage: "sparkles.rectangle.stack")
                }
                NavigationLink {
                    SkyARView(mode: .night)
                } label: {
                    Label("Night AR", systemImage: "moon.stars.fill")
                }
                NavigationLink {
                    SkyARView(mode: .frame)
                } label: {
                    Label("Frame AR", systemImage: "rectangle.dashed")
                }
            }
        }
    }
}
