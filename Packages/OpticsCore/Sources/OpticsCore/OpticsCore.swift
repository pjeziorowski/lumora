// Packages/OpticsCore/Sources/OpticsCore/OpticsCore.swift
//
// Exposure, depth of field, field of view, spot stars, star trails and time-lapse math
// (see the project brief, §2.7–2.12 and §3.2). Pure functions on millimetres,
// seconds and degrees; no UI.

import Foundation

public enum OpticsCore {
    /// Ratio between f-numbers one full stop apart (√2: the aperture area halves per stop).
    public static let fullStopApertureRatio = 2.0.squareRoot()
}
