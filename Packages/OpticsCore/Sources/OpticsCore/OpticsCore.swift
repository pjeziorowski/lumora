// Packages/OpticsCore/Sources/OpticsCore/OpticsCore.swift
//
// Exposure, depth of field, field of view, spot stars, star trails and time-lapse math.
// Phase 0 skeleton: the calculators land in Phase 5 (see the project brief, §3.2 and §5).

import Foundation

public enum OpticsCore {
    /// Ratio between f-numbers one full stop apart (√2: the aperture area halves per stop).
    public static let fullStopApertureRatio = 2.0.squareRoot()
}
