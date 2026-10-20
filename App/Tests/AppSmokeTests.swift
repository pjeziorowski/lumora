// App/Tests/AppSmokeTests.swift

import AstroCore
import Foundation
import GeoCore
import MapKit
import PlannerKit
import SwiftUI
import Testing
@testable import Lumora

struct AppSmokeTests {
    @Test func fourTabs() {
        #expect(AppTab.allCases.count == 4)
    }

}

@MainActor
struct PlannerMapTests {
    /// A line from a pin just west of the antimeridian to a point just east of it stays
    /// short on the map instead of wrapping round the world.
    @Test func mapPointsUnwrapAcrossAntimeridian() {
        let pin = MKMapPoint(CLLocationCoordinate2D(latitude: -16.8, longitude: 179.99))
        let east = PlannerMapView.Coordinator.mapPoint(GeoPoint(latitude: -16.8, longitude: 180.05), near: pin)
        let west = PlannerMapView.Coordinator.mapPoint(GeoPoint(latitude: -16.8, longitude: -179.95), near: pin)
        let world = MKMapSize.world.width
        #expect(abs(east.x - pin.x) < world / 1000)
        #expect(abs(west.x - pin.x) < world / 1000)
        #expect(east.x > pin.x)
    }

    @Test func polarPointsStayOnTheMap() {
        let pin = MKMapPoint(CLLocationCoordinate2D(latitude: 85, longitude: 0))
        let pole = PlannerMapView.Coordinator.mapPoint(GeoPoint(latitude: 90, longitude: 0), near: pin)
        #expect(pole.x.isFinite && pole.y.isFinite)
    }
}

@MainActor
struct PillUITests {
    @Test func sampleLocationsHaveValidTimeZones() {
        for location in PillLocation.samples {
            #expect(TimeZone(identifier: location.timeZoneIdentifier) != nil)
        }
    }

    /// The lit part of the disc: full at 180°, right half at first quarter (north), mirrored south.
    @Test func moonLitShape() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let full = MoonLitShape(elongation: 180, mirrored: false).path(in: rect).boundingRect
        #expect(abs(full.width - 100) < 0.5)
        let firstQuarter = MoonLitShape(elongation: 90, mirrored: false).path(in: rect).boundingRect
        #expect(abs(firstQuarter.minX - 50) < 0.5 && abs(firstQuarter.maxX - 100) < 0.5)
        let southern = MoonLitShape(elongation: 90, mirrored: true).path(in: rect).boundingRect
        #expect(abs(southern.minX) < 0.5 && abs(southern.maxX - 50) < 0.5)
        let lastQuarter = MoonLitShape(elongation: 270, mirrored: false).path(in: rect).boundingRect
        #expect(abs(lastQuarter.maxX - 50) < 0.5)
    }
}
