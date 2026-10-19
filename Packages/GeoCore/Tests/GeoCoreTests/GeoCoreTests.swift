// Packages/GeoCore/Tests/GeoCoreTests/GeoCoreTests.swift

import Testing
@testable import GeoCore

struct GeoCoreTests {
    // Golden: NIMA TR8350.2, WGS84 defining parameters (a = 6378137 m, 1/f = 298.257223563).
    @Test func wgs84Constants() {
        #expect(GeoCore.wgs84SemiMajorAxis == 6_378_137.0)
        #expect(abs(1 / GeoCore.wgs84Flattening - 298.257223563) < 1e-9)
    }
}
