// Packages/CameraCatalog/Sources/CameraCatalog/CameraCatalog.swift
//
// Camera body catalogue (sensor size, resolution, pixel pitch, circle of confusion).
// Phase 0 skeleton: the bundled JSON catalogue and picker models land in Phase 5.

import Foundation

public enum CameraCatalog {
    /// Diagonal of a 36 × 24 mm full-frame sensor in mm, the reference for crop factors.
    public static let fullFrameDiagonalMM = (36.0 * 36.0 + 24.0 * 24.0).squareRoot()
}
