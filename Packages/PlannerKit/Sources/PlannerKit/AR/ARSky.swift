// Packages/PlannerKit/Sources/PlannerKit/AR/ARSky.swift
//
// What the AR views draw, as directions in the local east-north-up frame: horizon, azimuth
// and elevation grid, the Sun's and Moon's paths for the day with hour marks, the galactic
// plane and the core's path through the night, the celestial equator, poles, Polaris and
// star-trail circles, and ground lines at the near limit, focus and far limit of the depth
// of field. The app projects these with `ARProjector`.
//
// Circles of constant declination are drawn from the observer's latitude alone (they do not
// move in azimuth/elevation), with standard refraction so they meet the horizon where the
// Sun and stars do.

import AstroCore
import Foundation

public enum ARMode: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case sunMoon, milkyWay, night, frame
    public var id: Self { self }
}

public enum ARLineKind: String, Sendable, Hashable, Codable {
    case horizon, azimuthGrid, elevationGrid
    case sunPath, moonPath
    case galacticPlane, corePath
    case celestialEquator, starTrail
    case focusNear, focus, focusFar
}

public enum ARMarkerKind: String, Sendable, Hashable, Codable {
    case sun, moon, sunHour, moonHour, galacticCenter, coreHour, polaris, celestialPole, cardinal, gridLabel
}

public struct ARLine: Sendable, Hashable {
    public let kind: ARLineKind
    public let points: [ARVector]
    public let label: String?
}

public struct ARMarker: Sendable, Hashable {
    public let kind: ARMarkerKind
    public let direction: ARVector
    public let label: String
}

/// Distances (metres) for the depth-of-field ground lines, and the camera's height above
/// the ground they lie on.
public struct ARFocusLines: Sendable, Hashable {
    public var near: Double
    public var focus: Double
    /// nil when the far limit is at infinity.
    public var far: Double?
    public var eyeHeight: Double

    public init(near: Double, focus: Double, far: Double?, eyeHeight: Double = 1.6) {
        self.near = near
        self.focus = focus
        self.far = far
        self.eyeHeight = eyeHeight
    }
}

public struct ARSky: Sendable, Hashable {
    public let lines: [ARLine]
    public let markers: [ARMarker]
    /// The Sun's elevation now, for the simulated sky colour and twilight hints.
    public let sunElevation: Double

    public static func compute(location: PillLocation, instant: Date, mode: ARMode, clock: ClockStyle = .twentyFourHour,
                               focus: ARFocusLines? = nil) -> ARSky {
        let observer = location.observer
        let zone = location.timeZone
        var lines = grid()
        var markers = cardinals()
        let sun = Ephemeris.horizontal(.sun, at: AstroTime(instant), observer: observer)
        func hour(_ date: Date) -> String { Formatting.clockTime(date, timeZone: zone, style: clock) }

        switch mode {
        case .sunMoon:
            let day = LocalDay(containing: instant, timeZone: zone)
            for body in [Body.sun, .moon] {
                let path = SkyPath.compute(body, location: location, day: day, stepMinutes: 5)
                lines.append(ARLine(kind: body == .sun ? .sunPath : .moonPath,
                                    points: path.samples.map { ARVector(azimuth: $0.azimuth, elevation: $0.altitude) }, label: nil))
                for s in path.samples where isWholeHour(s.time, zone) && s.altitude > -6 {
                    markers.append(ARMarker(kind: body == .sun ? .sunHour : .moonHour,
                                            direction: ARVector(azimuth: s.azimuth, elevation: s.altitude), label: hour(s.time)))
                }
            }
            let moon = Ephemeris.horizontal(.moon, at: AstroTime(instant), observer: observer)
            let lit = Int((Lunar.illumination(at: AstroTime(instant)).fraction * 100).rounded())
            markers.append(ARMarker(kind: .moon, direction: ARVector(azimuth: moon.azimuth, elevation: moon.altitude),
                                    label: "Moon \(lit)%"))
            markers.append(ARMarker(kind: .sun, direction: ARVector(azimuth: sun.azimuth, elevation: sun.altitude), label: "Sun"))
        case .milkyWay, .night:
            let time = AstroTime(instant)
            lines.append(ARLine(kind: .galacticPlane,
                                points: MilkyWay.plane(at: time, observer: observer, step: 2)
                                    .map { ARVector(azimuth: $0.horizontal.azimuth, elevation: $0.horizontal.altitude) },
                                label: nil))
            let frame = FixedSky.Frame(time)
            let core = frame.horizontal(FixedSky.galacticCenter, observer: observer)
            markers.append(ARMarker(kind: .galacticCenter, direction: ARVector(azimuth: core.azimuth, elevation: core.altitude),
                                    label: "Galactic centre"))
            if mode == .milkyWay {
                // The core from six hours before to six hours after, with hour marks.
                var points: [ARVector] = []
                let start = instant.addingTimeInterval(-6 * 3600)
                for step in 0...144 {
                    let t = start.addingTimeInterval(Double(step) * 300)
                    let h = MilkyWay.center(at: AstroTime(t), observer: observer)
                    points.append(ARVector(azimuth: h.azimuth, elevation: h.altitude))
                    if isWholeHour(t, zone) && h.altitude > -6 && abs(t.timeIntervalSince(instant)) > 600 {
                        markers.append(ARMarker(kind: .coreHour, direction: ARVector(azimuth: h.azimuth, elevation: h.altitude),
                                                label: hour(t)))
                    }
                }
                lines.append(ARLine(kind: .corePath, points: points, label: nil))
            } else {
                lines += nightLines(latitude: location.latitude)
                let north = location.latitude >= 0
                let pole = ARVector(azimuth: north ? 0 : 180, elevation: refracted(abs(location.latitude)))
                markers.append(ARMarker(kind: .celestialPole, direction: pole,
                                        label: north ? "North celestial pole" : "South celestial pole"))
                let polaris = frame.horizontal(FixedSky.polaris, observer: observer)
                if polaris.altitude > -2 {
                    markers.append(ARMarker(kind: .polaris, direction: ARVector(azimuth: polaris.azimuth, elevation: polaris.altitude),
                                            label: "Polaris"))
                }
            }
        case .frame:
            if let focus {
                lines.append(groundLine(.focusNear, distance: focus.near, eyeHeight: focus.eyeHeight))
                lines.append(groundLine(.focus, distance: focus.focus, eyeHeight: focus.eyeHeight))
                if let far = focus.far { lines.append(groundLine(.focusFar, distance: far, eyeHeight: focus.eyeHeight)) }
            }
        }
        return ARSky(lines: lines, markers: markers, sunElevation: sun.altitude)
    }

    // MARK: Pieces

    static func grid() -> [ARLine] {
        var lines = [ARLine(kind: .horizon, points: stride(from: 0.0, through: 360, by: 2).map { ARVector(azimuth: $0, elevation: 0) },
                            label: nil)]
        for az in stride(from: 0.0, to: 360, by: 15) {
            let points = stride(from: -10.0, through: 85, by: 5).map { ARVector(azimuth: az, elevation: $0) }
            lines.append(ARLine(kind: .azimuthGrid, points: points, label: nil))
        }
        for el in stride(from: 15.0, through: 75, by: 15) {
            let points = stride(from: 0.0, through: 360, by: 3).map { ARVector(azimuth: $0, elevation: el) }
            lines.append(ARLine(kind: .elevationGrid, points: points, label: "\(Int(el))°"))
        }
        return lines
    }

    static func cardinals() -> [ARMarker] {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return names.enumerated().map { index, name in
            ARMarker(kind: .cardinal, direction: ARVector(azimuth: Double(index) * 45, elevation: 0), label: name)
        }
    }

    /// The celestial equator and star-trail circles (declination 60°, 75° and 85° toward the
    /// visible pole).
    static func nightLines(latitude: Double) -> [ARLine] {
        let sign = latitude >= 0 ? 1.0 : -1.0
        var lines = [ARLine(kind: .celestialEquator, points: declinationCircle(0, latitude: latitude), label: nil)]
        for dec in [60.0, 75.0, 85.0] {
            lines.append(ARLine(kind: .starTrail, points: declinationCircle(sign * dec, latitude: latitude), label: "\(Int(dec))°"))
        }
        return lines
    }

    /// A circle of constant declination in azimuth/elevation, from hour angle −180° to 180°.
    public static func declinationCircle(_ declination: Double, latitude: Double, step: Double = 2) -> [ARVector] {
        let d2r = Double.pi / 180
        let phi = latitude * d2r, dec = declination * d2r
        return stride(from: -180.0, through: 180, by: step).map { h in
            let ha = h * d2r
            // East-north-up components of the direction (hour angle measured westward).
            let up = sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(ha)
            let north = cos(phi) * sin(dec) - sin(phi) * cos(dec) * cos(ha)
            let east = -cos(dec) * sin(ha)
            let v = ARVector(east: east, north: north, up: up)
            return ARVector(azimuth: v.azimuth, elevation: refracted(v.elevation))
        }
    }

    /// Ground points `distance` metres away all around a camera `eyeHeight` above flat ground.
    static func groundLine(_ kind: ARLineKind, distance: Double, eyeHeight: Double) -> ARLine {
        let depression = groundDepression(distance: distance, eyeHeight: eyeHeight)
        return ARLine(kind: kind, points: stride(from: 0.0, through: 360, by: 2).map { ARVector(azimuth: $0, elevation: -depression) },
                      label: nil)
    }

    /// Angle below the horizon of flat ground `distance` metres away, degrees.
    public static func groundDepression(distance: Double, eyeHeight: Double) -> Double {
        atan2(max(0, eyeHeight), max(0.01, distance)) * 180 / .pi
    }

    static func refracted(_ elevation: Double) -> Double {
        elevation + Ephemeris.refractionAngle(.normal, altitude: elevation)
    }

    static func isWholeHour(_ date: Date, _ zone: TimeZone) -> Bool {
        Int((date.timeIntervalSince1970 + Double(zone.secondsFromGMT(for: date))).rounded()) % 3600 == 0
    }
}
