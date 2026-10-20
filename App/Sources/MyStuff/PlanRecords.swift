// App/Sources/MyStuff/PlanRecords.swift
//
// SwiftData storage for saved plans and places. Each record keeps a few fields for sorting
// and listing plus the full `Plan` / `SavedPlace` value as JSON, so the exchange format and
// the stored format are the same and nothing is lost between them.

import Foundation
import GeoCore
import PlannerKit
import SwiftData

@Model
final class PlanRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var instant: Date
    var placeName: String
    var modified: Date
    var payload: Data
    @Attribute(.externalStorage) var thumbnail: Data?

    init(_ plan: Plan) {
        id = plan.id
        name = plan.name
        instant = plan.instant
        placeName = plan.location.name
        modified = plan.modified
        payload = (try? JSONEncoder().encode(plan)) ?? Data()
    }

    var plan: Plan? { try? JSONDecoder().decode(Plan.self, from: payload) }

    func update(_ plan: Plan) {
        name = plan.name
        instant = plan.instant
        placeName = plan.location.name
        modified = plan.modified
        payload = (try? JSONEncoder().encode(plan)) ?? payload
    }
}

@Model
final class PlaceRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var created: Date
    var payload: Data

    init(_ place: SavedPlace) {
        id = place.id
        name = place.location.name
        created = place.created
        payload = (try? JSONEncoder().encode(place)) ?? Data()
    }

    var place: SavedPlace? { try? JSONDecoder().decode(SavedPlace.self, from: payload) }
}

enum PlanLibrary {
    /// Applies an archive (`PlanArchive.merge` decides what is added or replaced) and
    /// reschedules the reminders of imported plans; returns how many items changed.
    @MainActor @discardableResult
    static func importArchive(_ archive: PlanArchive, into context: ModelContext) throws -> Int {
        let plans = try context.fetch(FetchDescriptor<PlanRecord>())
        let places = try context.fetch(FetchDescriptor<PlaceRecord>())
        let merge = archive.merge(intoPlans: Set(plans.map(\.id)), places: Set(places.map(\.id)))
        for plan in merge.replaced {
            guard let existing = plans.first(where: { $0.id == plan.id }) else { continue }
            existing.update(plan)
            existing.thumbnail = nil
        }
        for plan in merge.added { context.insert(PlanRecord(plan)) }
        for place in merge.addedPlaces { context.insert(PlaceRecord(place)) }
        try context.save()
        for plan in merge.added + merge.replaced {
            Task { _ = await PlanReminders.schedule(plan) }
        }
        return merge.count
    }

    @MainActor
    static func archive(from context: ModelContext) -> PlanArchive {
        let plans = (try? context.fetch(FetchDescriptor<PlanRecord>(sortBy: [SortDescriptor(\.instant)]))) ?? []
        let places = (try? context.fetch(FetchDescriptor<PlaceRecord>(sortBy: [SortDescriptor(\.created)]))) ?? []
        return PlanArchive(plans: plans.compactMap(\.plan), places: places.compactMap(\.place))
    }

    /// Example plans for screenshot runs (`-seedPlans`).
    @MainActor
    static func seed(_ context: ModelContext, now: Date) {
        let samples = PillLocation.samples
        func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso) ?? now }
        var optics = MapOptics()
        optics.showFieldOfView = true
        optics.focalLength = 200
        let plans = [
            Plan(name: "Sunset over the Vistula", notes: "Golden hour from the Poniatowski Bridge", created: now,
                 location: samples[0], instant: at("2026-06-21T18:45:00Z"), reminderMinutes: 60),
            Plan(name: "Manhattanhenge", notes: "Full sun on the grid", created: now, location: samples[1],
                 instant: at("2026-05-30T00:12:00Z"),
                 target: TargetPin(point: .init(latitude: 40.73029, longitude: -74.04748), groundElevation: 30, objectHeight: 60),
                 mapOptics: optics, cameraID: "sony-a7r-iv", panel: PlannerPanelKind.obstacle.rawValue, reminderMinutes: 30),
            Plan(name: "Milky Way from Cape Town", created: now, location: samples[5], instant: at("2026-07-14T21:30:00Z"),
                 layers: .all, mapStyle: .satellite, panel: PlannerPanelKind.milkyWay.rawValue),
        ]
        for plan in plans { context.insert(PlanRecord(plan)) }
        context.insert(PlaceRecord(SavedPlace(location: samples[4], notes: "Fjellheisen viewpoint", created: now)))
        context.insert(PlaceRecord(SavedPlace(location: samples[3], notes: "Equator monument", created: now)))
        try? context.save()
    }
}
