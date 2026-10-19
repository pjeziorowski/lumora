// Packages/CameraCatalog/Tests/CameraCatalogTests/CameraCatalogTests.swift

import Testing
@testable import CameraCatalog

struct CameraCatalogTests {
    // Golden: 36 × 24 mm diagonal = 43.267 mm (√(36² + 24²)).
    @Test func fullFrameDiagonal() {
        #expect(abs(CameraCatalog.fullFrameDiagonalMM - 43.2666) < 1e-3)
    }
}
