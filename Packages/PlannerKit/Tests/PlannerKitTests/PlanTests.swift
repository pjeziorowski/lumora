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
