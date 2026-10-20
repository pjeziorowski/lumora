// Packages/OpticsCore/Sources/OpticsCore/DepthOfField.swift
//
// Depth of field (brief §2.8, §3.2), thin-lens formulas as DOFMaster uses them
// (Greenleaf, Photographic Optics, 1950, pp. 25–27):
//   H = f² / (N·c) + f
//   near = s(H − f) / (H + s − 2f)
//   far  = s(H − f) / (H − s), infinite when s ≥ H
// All lengths in millimetres. A teleconverter multiplies focal length and f-number. A lens
// cannot focus at or inside its focal length, so shorter distances are clamped to 1 mm beyond it.
// Advanced mode adds diffraction (Airy disc 2.44·λ·N against the pixel pitch) and a
// circle of confusion derived from print size, viewing distance and visual acuity.

import Foundation

public struct DoFInput: Sendable, Hashable, Codable {
    public var focalLength: Double
    public var aperture: Double
    /// Focus distance from the lens (the thin-lens object distance), mm. Lens barrels engrave
    /// distance from the image plane; `objectDistance(fromImagePlane:focalLength:)` converts.
    public var distance: Double
    /// Circle of confusion, mm.
    public var coc: Double
    /// 1 for none, 1.4, 2 …
    public var teleconverter: Double

    public init(focalLength: Double, aperture: Double, distance: Double, coc: Double, teleconverter: Double = 1) {
        self.focalLength = focalLength
        self.aperture = aperture
        self.distance = distance
        self.coc = coc
        self.teleconverter = teleconverter
    }

    public var effectiveFocalLength: Double { focalLength * teleconverter }
    public var effectiveAperture: Double { aperture * teleconverter }
}

public struct DoFResult: Sendable, Hashable {
    public let hyperfocal: Double
    public let near: Double
    /// `.infinity` when the far limit is at infinity.
    public let far: Double

    public var total: Double { far - near }
    public var isFarInfinite: Bool { far.isInfinite }
    /// Sharp zone in front of and behind the subject.
    public let inFront: Double
    public var behind: Double { far - subject }
    /// The focus distance used, after clamping beyond the focal length.
    public let subject: Double
    /// In front : behind, as a fraction in front (0.5 = even split; 0 when behind is infinite).
    public var frontFraction: Double { far.isInfinite ? 0 : inFront / total }
}

public enum DepthOfField {
    public static func hyperfocal(focalLength f: Double, aperture n: Double, coc c: Double) -> Double {
        f * f / (n * c) + f
    }

    /// Closest focus distance accepted beyond the focal length, mm.
    public static let minimumFocusMargin = 1.0

    /// Thin-lens object distance for a subject `distance` mm from the image plane
    /// (s + s·f/(s − f) = distance). Below 4f no real focus exists and 2f is returned.
    public static func objectDistance(fromImagePlane distance: Double, focalLength f: Double) -> Double {
        guard distance > 4 * f else { return 2 * f }
        return (distance + (distance * distance - 4 * distance * f).squareRoot()) / 2
    }

    public static func compute(_ input: DoFInput) -> DoFResult {
        let f = input.effectiveFocalLength
        let n = input.effectiveAperture
        let s = max(input.distance, f + minimumFocusMargin)
        let h = hyperfocal(focalLength: f, aperture: n, coc: input.coc)
        let near = s * (h - f) / (h + s - 2 * f)
        let far = s >= h ? Double.infinity : s * (h - f) / (h - s)
        return DoFResult(hyperfocal: h, near: near, far: far, inFront: s - near, subject: s)
    }

    // MARK: Advanced

    /// Wavelength for diffraction, mm (550 nm, green).
    public static let wavelength = 550e-6

    /// Airy disc diameter (to the first minimum) in mm: 2.44·λ·N.
    public static func airyDisc(aperture: Double, wavelength: Double = wavelength) -> Double {
        2.44 * wavelength * aperture
    }

    /// Diffraction becomes visible once the Airy disc exceeds `factor` × pixel pitch.
    public static func isDiffractionLimited(aperture: Double, pixelPitchMicrons: Double, factor: Double = 2) -> Bool {
        airyDisc(aperture: aperture) * 1000 > factor * pixelPitchMicrons
    }

    /// The smallest f-number at which the sensor is diffraction-limited.
    public static func diffractionLimitedAperture(pixelPitchMicrons: Double, factor: Double = 2) -> Double {
        factor * pixelPitchMicrons / 1000 / (2.44 * wavelength)
    }

    /// Circle of confusion on the sensor from viewing conditions: the eye resolves
    /// `acuity` line pairs per mm at 250 mm, the blur spot on the print scales with the
    /// viewing distance, and the print enlarges the sensor by printDiagonal/sensorDiagonal.
    /// 8×10 in print at 250 mm with 5 lp/mm on full frame gives 0.0266 mm.
    public static func coc(sensorDiagonal: Double, printDiagonal: Double, viewingDistance: Double = 250,
                           acuity: Double = 5) -> Double {
        let printBlur = viewingDistance / 250 / acuity
        return printBlur / (printDiagonal / sensorDiagonal)
    }

    // MARK: Tables

    public struct TableRow: Sendable, Hashable, Identifiable {
        public let aperture: Double
        public let cells: [DoFResult]
        public var id: Double { aperture }
    }

    /// DoF across apertures (rows) and distances (columns).
    public static func table(focalLength: Double, coc: Double, apertures: [Double], distances: [Double],
                             teleconverter: Double = 1) -> [TableRow] {
        apertures.map { n in
            TableRow(aperture: n, cells: distances.map { s in
                compute(DoFInput(focalLength: focalLength, aperture: n, distance: s, coc: coc, teleconverter: teleconverter))
            })
        }
    }

    /// Hyperfocal distance (mm) for each focal length (rows) and aperture (columns).
    public static func hyperfocalTable(focalLengths: [Double], apertures: [Double], coc: Double) -> [[Double]] {
        focalLengths.map { f in apertures.map { hyperfocal(focalLength: f, aperture: $0, coc: coc) } }
    }
}
