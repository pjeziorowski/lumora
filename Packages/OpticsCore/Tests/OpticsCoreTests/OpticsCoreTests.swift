// Packages/OpticsCore/Tests/OpticsCoreTests/OpticsCoreTests.swift

import Foundation
import Testing
@testable import OpticsCore

struct OpticsCoreTests {
    // Golden: the marked full-stop f-number series f/1.4, 2, 2.8, 4, 5.6, 8, 11, 16, 22
    // (ISO 517:2008, Table 1). Marked values are rounded, so allow 3 %.
    @Test func fullStopSeries() {
        let marked = [1.4, 2.0, 2.8, 4.0, 5.6, 8.0, 11.0, 16.0, 22.0]
        for (index, value) in marked.enumerated() {
            let exact = pow(OpticsCore.fullStopApertureRatio, Double(index + 1))
            #expect(abs(exact - value) / value < 0.03)
        }
    }
}
