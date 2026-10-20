// Packages/OpticsCore/Sources/OpticsCore/Exposure.swift
//
// Exposure value and equivalent exposures (brief §2.7, §3.2):
//   EV = log2(N² / t) − log2(ISO / 100)
// Equivalent exposures keep EV. ND filters lengthen the shutter: t' = t · 2^stops.
// Standard scales are in third stops; filters are named by stops, optical density
// ("ND 0.9") or filter factor ("ND8").

import Foundation

public struct ExposureSettings: Sendable, Hashable, Codable {
    /// f-number.
    public var aperture: Double
    /// Shutter time in seconds.
    public var shutter: Double
    public var iso: Double

    public init(aperture: Double, shutter: Double, iso: Double) {
        self.aperture = aperture
        self.shutter = shutter
        self.iso = iso
    }

    /// Exposure value referred to ISO 100.
    public var ev100: Double { Exposure.ev(aperture: aperture, shutter: shutter, iso: iso) }
}

public enum Exposure {
    public static func ev(aperture: Double, shutter: Double, iso: Double) -> Double {
        log2(aperture * aperture / shutter) - log2(iso / 100)
    }

    /// Shutter time giving `ev` at the aperture and ISO.
    public static func shutter(ev: Double, aperture: Double, iso: Double) -> Double {
        aperture * aperture / pow(2, ev + log2(iso / 100))
    }

    /// f-number giving `ev` at the shutter time and ISO.
    public static func aperture(ev: Double, shutter: Double, iso: Double) -> Double {
        (shutter * pow(2, ev + log2(iso / 100))).squareRoot()
    }

    /// ISO giving `ev` at the aperture and shutter time.
    public static func iso(ev: Double, aperture: Double, shutter: Double) -> Double {
        100 * pow(2, log2(aperture * aperture / shutter) - ev)
    }

    public enum Unknown: String, Sendable, CaseIterable { case aperture, shutter, iso }

    /// Equivalent exposure: keeps `reference`'s EV, takes two values from `fixed` and solves
    /// the `unknown` one.
    public static func equivalent(to reference: ExposureSettings, fixed: ExposureSettings, solving unknown: Unknown) -> ExposureSettings {
        let ev = reference.ev100
        var result = fixed
        switch unknown {
        case .aperture: result.aperture = aperture(ev: ev, shutter: fixed.shutter, iso: fixed.iso)
        case .shutter: result.shutter = shutter(ev: ev, aperture: fixed.aperture, iso: fixed.iso)
        case .iso: result.iso = iso(ev: ev, aperture: fixed.aperture, shutter: fixed.shutter)
        }
        return result
    }

    /// Shutter time after adding filters of `stops` total.
    public static func withFilters(shutter: Double, stops: Double) -> Double {
        shutter * pow(2, stops)
    }

    // MARK: Scales

    /// Nominal full/third-stop shutter speeds from 1/8000 s to 30 s, as marked on cameras.
    public static let shutterScale: [Double] = [
        1 / 8000, 1 / 6400, 1 / 5000, 1 / 4000, 1 / 3200, 1 / 2500, 1 / 2000, 1 / 1600, 1 / 1250, 1 / 1000,
        1 / 800, 1 / 640, 1 / 500, 1 / 400, 1 / 320, 1 / 250, 1 / 200, 1 / 160, 1 / 125, 1 / 100, 1 / 80,
        1 / 60, 1 / 50, 1 / 40, 1 / 30, 1 / 25, 1 / 20, 1 / 15, 1 / 13, 1 / 10, 1 / 8, 1 / 6, 1 / 5, 1 / 4,
        0.3, 0.4, 0.5, 0.6, 0.8, 1, 1.3, 1.6, 2, 2.5, 3.2, 4, 5, 6, 8, 10, 13, 15, 20, 25, 30,
    ]
    /// Third-stop apertures f/1 to f/32 as marked.
    public static let apertureScale: [Double] = [
        1.0, 1.1, 1.2, 1.4, 1.6, 1.8, 2, 2.2, 2.5, 2.8, 3.2, 3.5, 4, 4.5, 5, 5.6, 6.3, 7.1, 8, 9, 10, 11,
        13, 14, 16, 18, 20, 22, 25, 29, 32,
    ]
    /// Third-stop ISO 50 to 102 400.
    public static let isoScale: [Double] = [
        50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200,
        4000, 5000, 6400, 8000, 10000, 12800, 16000, 20000, 25600, 32000, 40000, 51200, 64000, 80000, 102400,
    ]

    /// The nearest marked value on `scale`, compared in stops (log2).
    public static func nearest(_ value: Double, on scale: [Double]) -> Double {
        scale.min { abs(log2($0 / value)) < abs(log2($1 / value)) } ?? value
    }

    /// "1/250", "0.6\"", "2\"", "1m 30s", "2h 05m".
    public static func shutterLabel(_ seconds: Double) -> String {
        if seconds < 0.3 { return "1/\(Int((1 / seconds).rounded()))" }
        if seconds < 60 {
            let rounded = seconds < 10 ? (seconds * 10).rounded() / 10 : seconds.rounded()
            return rounded == rounded.rounded() ? "\(Int(rounded))\"" : "\(rounded)\""
        }
        let total = Int(seconds.rounded())
        if total < 3600 { return String(format: "%dm %02ds", total / 60, total % 60) }
        return String(format: "%dh %02dm", total / 3600, (total % 3600) / 60)
    }
}

/// A neutral density filter.
public struct NDFilter: Sendable, Hashable, Codable, Identifiable {
    public let stops: Double
    public var id: Double { stops }

    public init(stops: Double) { self.stops = stops }
    /// From optical density, e.g. 0.9 → 3 stops (density = stops · log10 2).
    public init(opticalDensity: Double) { stops = opticalDensity / log10(2) }
    /// From filter factor, e.g. ND8 → 3 stops, ND1000 → 9.97 stops.
    public init(factor: Double) { stops = log2(factor) }

    public var opticalDensity: Double { stops * log10(2) }
    public var factor: Double { pow(2, stops) }

    /// "10 stops · ND1000 · 3.0", with the factor rounded to how brands sell them.
    public var label: String {
        let stopText = stops == stops.rounded() ? "\(Int(stops))" : String(format: "%.1f", stops)
        return "\(stopText) stops · ND\(Self.brandFactor(factor)) · \(String(format: "%.1f", opticalDensity))"
    }

    /// Common filters: 1–20 stops in whole stops plus the 1.5/2.5 half-stop steps.
    public static let common: [NDFilter] = ([1, 1.5, 2, 2.5] + (3...20).map(Double.init)).map(NDFilter.init(stops:))

    /// Factor as brands label it: ND1000 for 2^10 = 1024, ND32000 for 2^15 = 32768.
    static func brandFactor(_ factor: Double) -> String {
        let value = Int(factor.rounded())
        if value < 1000 { return "\(value)" }
        let digits = String(value).count
        let unit = Int(pow(10, Double(digits - 2)))
        return "\(value / unit * unit)"
    }
}
