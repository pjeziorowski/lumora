// App/Sources/LumoraApp.swift

import CameraCatalog
import Foundation
import GeoCore
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
        let planner = PlannerState(session: session, lookup: { latitude, longitude in
            await PlaceSearch.placeInfo(latitude: latitude, longitude: longitude)
        }, elevation: { latitude, longitude in
            await ElevationClient.elevation(latitude: latitude, longitude: longitude)
        })
        LumoraApp.applyTarget(arguments: ProcessInfo.processInfo.arguments, to: planner)
        _plannerState = State(initialValue: planner)
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

    /// Screenshot runs can place the target pin with `-target <lat>,<lon>` and give the
    /// object there a height with `-objectHeight <m>`.
    static func applyTarget(arguments: [String], to planner: PlannerState) {
        guard let index = arguments.firstIndex(of: "-target"), index + 1 < arguments.count else { return }
        let parts = arguments[index + 1].split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return }
        var height = 0.0
        if let h = arguments.firstIndex(of: "-objectHeight"), h + 1 < arguments.count { height = Double(arguments[h + 1]) ?? 0 }
        Task { @MainActor in
            await planner.setTarget(GeoPoint(latitude: parts[0], longitude: parts[1]), objectHeight: height)
        }
    }
}
