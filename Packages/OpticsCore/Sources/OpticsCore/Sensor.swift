// Packages/OpticsCore/Sources/OpticsCore/Sensor.swift
//
// Sensor geometry shared by every calculator: physical size, resolution, pixel pitch,
// crop factor and the default circle of confusion (diagonal / 1500, brief §3.2).

import Foundation

public struct Sensor: Sendable, Hashable, Codable {
    /// Width and height in millimetres, landscape orientation (width ≥ height).
    public var widthMM: Double
    public var heightMM: Double
    /// Pixels across the width and height. Zero when unknown (pixel-based outputs are then nil).
    public var pixelsWide: Int
    public var pixelsHigh: Int

    public init(widthMM: Double, heightMM: Double, pixelsWide: Int = 0, pixelsHigh: Int = 0) {
        self.widthMM = widthMM
        self.heightMM = heightMM
        self.pixelsWide = pixelsWide
        self.pixelsHigh = pixelsHigh
    }

    /// 36 × 24 mm.
    public static let fullFrame = Sensor(widthMM: 36, heightMM: 24)
    public static let fullFrameDiagonalMM = (36.0 * 36.0 + 24.0 * 24.0).squareRoot()
    /// Divisor for the default circle of confusion.
    public static let cocDivisor = 1500.0

    public var diagonalMM: Double { (widthMM * widthMM + heightMM * heightMM).squareRoot() }
    public var cropFactor: Double { Self.fullFrameDiagonalMM / diagonalMM }
    /// Default circle of confusion in mm: sensor diagonal / 1500 (0.0288 mm for full frame).
    public var defaultCoC: Double { diagonalMM / Self.cocDivisor }
    public var megapixels: Double { Double(pixelsWide * pixelsHigh) / 1_000_000 }

    /// Pixel pitch in micrometres, from the width (nil without a resolution).
    public var pixelPitchMicrons: Double? {
        pixelsWide > 0 ? widthMM / Double(pixelsWide) * 1000 : nil
    }

    /// The sensor turned to portrait (or back): width and height swap.
    public var rotated: Sensor {
        Sensor(widthMM: heightMM, heightMM: widthMM, pixelsWide: pixelsHigh, pixelsHigh: pixelsWide)
    }
}

public enum Orientation: String, Sendable, Hashable, Codable, CaseIterable {
    case landscape, portrait
}
