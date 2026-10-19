// App/Tests/AppSmokeTests.swift

import AstroCore
import PlannerKit
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
