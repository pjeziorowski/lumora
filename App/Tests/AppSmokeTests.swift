// App/Tests/AppSmokeTests.swift

import AstroCore
import Foundation
import PlannerKit
import SwiftUI
import Testing
@testable import Lumora

struct AppSmokeTests {
    @Test func fourTabs() {
        #expect(AppTab.allCases.count == 4)
    }

    @Test func demoLocationsHaveValidTimeZones() {
        for location in DemoLocation.all {
            #expect(TimeZone(identifier: location.timeZoneID) != nil)
        }
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
