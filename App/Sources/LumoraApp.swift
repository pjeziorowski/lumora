// App/Sources/LumoraApp.swift

import CameraCatalog
import Foundation
import PlannerKit
import SwiftUI

@main
struct LumoraApp: App {
    /// Place and date shared by the Planner and the Sun and Moon tools.
    @State private var pillSession: PillSession
    @State private var plannerState: PlannerState
    /// Custom cameras, favourites and the default camera used by the photography tools.
    @State private var cameraStore: CameraStore

    init() {
        let session = LumoraApp.makePillSession(arguments: ProcessInfo.processInfo.arguments)
        _pillSession = State(initialValue: session)
        _plannerState = State(initialValue: PlannerState(session: session) { latitude, longitude in
            await PlaceSearch.placeInfo(latitude: latitude, longitude: longitude)
        })
        _cameraStore = State(initialValue: LumoraApp.makeCameraStore(arguments: ProcessInfo.processInfo.arguments))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(pillSession)
                .environment(plannerState)
                .environment(cameraStore)
        }
    }

    /// Normally restores the saved place and uses the real clock. The screenshot UI tests pass
    /// `-fixedDate <ISO 8601>` and `-place <sample name>` so every capture shows the same
    /// place and moment, without touching the user's saved place.
    static func makePillSession(arguments: [String]) -> PillSession {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        guard let text = value(after: "-fixedDate"), let date = ISO8601DateFormatter().date(from: text) else {
            return PillSession()
        }
        let place = value(after: "-place").flatMap { name in PillLocation.samples.first { $0.name == name } }
        return PillSession(defaults: nil, fallback: place ?? PillLocation.samples[0]) { date }
    }

    /// Screenshot runs (`-fixedDate`) get an in-memory store, with `-camera <id>` as the default.
    static func makeCameraStore(arguments: [String]) -> CameraStore {
        guard arguments.contains("-fixedDate") else { return CameraStore() }
        let store = CameraStore(defaults: nil)
        if let index = arguments.firstIndex(of: "-camera"), index + 1 < arguments.count,
           let camera = store.camera(id: arguments[index + 1]) {
            store.setDefault(camera)
        }
        return store
    }
}
