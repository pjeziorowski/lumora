// Packages/PlannerKit/Tests/PlannerKitTests/PlanTests.swift
//
// Phase 7 acceptance: a plan round-trips through export and import unchanged, including
// awkward values (sub-second instants, a dateline place, unicode names, optional fields).

import Foundation
import GeoCore
import Testing
@testable import PlannerKit

@MainActor
struct PlanTests {
    static func sample() -> Plan {
        var optics = MapOptics()
        optics.showFieldOfView = true
        optics.focalLength = 85
        optics.aperture = 1.8
        optics.orientation = .portrait
        return Plan(name: "Księżyc nad Taveuni 🌕", notes: "Line 1\nLine \"2\"",
                    created: Date(timeIntervalSinceReferenceDate: 812_345_678.123_456_7),
                    location: PillLocation.samples.first { $0.name == "Taveuni" }!,
                    instant: Date(timeIntervalSinceReferenceDate: 812_400_000.000_123),
                    target: TargetPin(point: GeoPoint(latitude: -16.79, longitude: -179.99), groundElevation: nil, objectHeight: 12.5),
                    eyeHeight: 1.65, mapOptics: optics, cameraID: "sony-a7r-iv", layers: [.moon, .milkyWay],
                    mapStyle: .hybrid, panel: "obstacle", reminderMinutes: 45)
    }

    @Test func roundTripsUnchanged() throws {
        let plans = [Self.sample(), Plan(name: "", location: PillLocation.samples[0], instant: Date(timeIntervalSince1970: 0))]
        let places = [SavedPlace(location: PillLocation.samples[4], notes: "Fjellheisen")]
        let archive = PlanArchive(plans: plans, places: places)
        let data = try archive.encoded()
        let back = try PlanArchive.decode(data)
        #expect(back == archive)
        #expect(back.plans[0].instant == plans[0].instant)
        // Encoding again gives byte-identical JSON (sorted keys).
        #expect(try back.encoded() == data)
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: PlanArchive.ImportError.notAPlanFile) { try PlanArchive.decode(Data("{\"plans\":[]}".utf8)) }
        #expect(throws: PlanArchive.ImportError.notAPlanFile) { try PlanArchive.decode(Data("not json".utf8)) }
        let future = Data("{\"format\":\"lumora.plans\",\"version\":99,\"plans\":[],\"places\":[]}".utf8)
        #expect(throws: PlanArchive.ImportError.newerVersion(99)) { try PlanArchive.decode(future) }
    }

    @Test func importMergesById() {
        let stored = Self.sample()
        var newer = stored
        newer.name = "Renamed"
        newer.instant = stored.instant.addingTimeInterval(3600)
        let fresh = Plan(name: "Fresh", location: PillLocation.samples[0], instant: Date(timeIntervalSince1970: 0))
        let place = SavedPlace(location: PillLocation.samples[4])
        let other = SavedPlace(location: PillLocation.samples[3])
        // The archive repeats ids: the last copy of a plan wins, the first of a place.
        let archive = PlanArchive(plans: [stored, fresh, newer], places: [place, other, place])
        let merge = archive.merge(intoPlans: [stored.id], places: [place.id])
        #expect(merge.replaced == [newer])
        #expect(merge.added == [fresh])
        #expect(merge.addedPlaces == [other])
        #expect(merge.count == 3)
        // Empty archive or empty library.
        #expect(PlanArchive(plans: []).merge(intoPlans: [stored.id], places: []).count == 0)
        let intoEmpty = archive.merge(intoPlans: [], places: [])
        #expect(intoEmpty.added.map(\.name) == ["Renamed", "Fresh"] && intoEmpty.addedPlaces.count == 2)
    }

    @Test func olderStoredPlansStillDecode() throws {
        // A plan and place as an earlier build might have stored them: only the core keys.
        let json = """
        {"id":"6A8E2C1D-3B4F-4E5A-9C7D-1E2F3A4B5C6D","name":"Old plan","instant":800000000,
         "location":{"name":"Warsaw","latitude":52.2297,"longitude":21.0122,"elevation":100,
                     "timeZoneIdentifier":"Europe/Warsaw"}}
        """
        let plan = try JSONDecoder().decode(Plan.self, from: Data(json.utf8))
        #expect(plan.name == "Old plan" && plan.location.name == "Warsaw")
        #expect(plan.instant == Date(timeIntervalSinceReferenceDate: 800_000_000))
        #expect(plan.eyeHeight == 1.7 && plan.layers == .all && plan.mapStyle == .standard)
        #expect(plan.panel == PlannerPanelKind.pin.rawValue && plan.target == nil && plan.reminderMinutes == nil)
        #expect(plan.created == plan.instant && plan.modified == plan.instant)
        let placeJSON = """
        {"id":"0B1C2D3E-4F50-4617-8293-A4B5C6D7E8F9","location":{"name":"Tromsø","latitude":69.6496,
         "longitude":18.956,"elevation":0,"timeZoneIdentifier":"Europe/Oslo"}}
        """
        let place = try JSONDecoder().decode(SavedPlace.self, from: Data(placeJSON.utf8))
        #expect(place.notes.isEmpty && place.location.name == "Tromsø")
        // A full plan still decodes to itself through the explicit decoder.
        let sample = Self.sample()
        #expect(try JSONDecoder().decode(Plan.self, from: JSONEncoder().encode(sample)) == sample)
    }

    @Test func duplicateAndReminder() {
        let plan = Self.sample()
        let copy = plan.duplicated(now: Date(timeIntervalSince1970: 1000))
        #expect(copy.id != plan.id && copy.name.hasSuffix(" copy") && copy.location == plan.location)
        #expect(plan.reminderDate == plan.instant.addingTimeInterval(-45 * 60))
        #expect(plan.shareText().contains("Taveuni"))
    }

    @Test func stateCapturesAndRestores() async {
        let session = PillSession(defaults: nil, fallback: PillLocation.samples[0]) { Date(timeIntervalSince1970: 1_780_000_000) }
        let state = PlannerState(session: session)
        await state.apply(Self.sample())
        #expect(session.location.name == "Taveuni" && state.mapStyle == .hybrid && state.selectedPanel == .obstacle)
        #expect(state.target?.objectHeight == 12.5)
        let captured = state.plan(named: "Again", cameraID: "sony-a7r-iv", reminderMinutes: 45, now: Self.sample().created)
        let original = Self.sample()
        #expect(captured.location == original.location && captured.instant == original.instant && captured.target == original.target)
        #expect(captured.mapOptics == original.mapOptics && captured.layers == original.layers && captured.panel == original.panel)
    }
}
