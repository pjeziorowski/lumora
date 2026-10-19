// Packages/OpticsCore/Tests/OpticsCoreTests/OpticsCoreTests.swift

import Testing
@testable import OpticsCore

struct OpticsCoreTests {
    @Test func packageLinks() {
        #expect(OpticsCore.specification.contains("3.2"))
    }
}
