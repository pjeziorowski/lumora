// App/Sources/LumoraApp.swift

import PlannerKit
import SwiftUI

@main
struct LumoraApp: App {
    /// Place and date shared by the Sun and Moon tools.
    @State private var pillSession = PillSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(pillSession)
        }
    }
}
