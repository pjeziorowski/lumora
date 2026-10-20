// Packages/AstroCore/Sources/AstroCore/VSOP87Earth.swift
//
// Truncated VSOP87 (Bretagnon & Francou 1988) heliocentric model of the Earth.
// Coefficients copied from Astronomy Engine (MIT) `vsop_lon_Earth_*`, `vsop_lat_Earth_*`,
// `vsop_rad_Earth_*`; evaluation ports `VsopCoords`, `VsopSphereToRect`, `VsopRotate`
// and `CalcVsop`.

import Foundation

enum VSOP87Earth {
    struct Term: Sendable {
        let amplitude: Double
        let phase: Double
        let frequency: Double
        init(_ a: Double, _ p: Double, _ f: Double) {
            amplitude = a
            phase = p
            frequency = f
        }
    }

    static let longitude: [[Term]] = [
        [
            Term(1.75347045673, 0.00000000000, 0.00000000000),
            Term(0.03341656453, 4.66925680415, 6283.07584999140),
            Term(0.00034894275, 4.62610242189, 12566.15169998280),
            Term(0.00003417572, 2.82886579754, 3.52311834900),
            Term(0.00003497056, 2.74411783405, 5753.38488489680),
            Term(0.00003135899, 3.62767041756, 77713.77146812050),
            Term(0.00002676218, 4.41808345438, 7860.41939243920),
            Term(0.00002342691, 6.13516214446, 3930.20969621960),
            Term(0.00001273165, 2.03709657878, 529.69096509460),
            Term(0.00001324294, 0.74246341673, 11506.76976979360),
            Term(0.00000901854, 2.04505446477, 26.29831979980),
            Term(0.00001199167, 1.10962946234, 1577.34354244780),
            Term(0.00000857223, 3.50849152283, 398.14900340820),
            Term(0.00000779786, 1.17882681962, 5223.69391980220),
            Term(0.00000990250, 5.23268072088, 5884.92684658320),
            Term(0.00000753141, 2.53339052847, 5507.55323866740),
            Term(0.00000505267, 4.58292599973, 18849.22754997420),
            Term(0.00000492392, 4.20505711826, 775.52261132400),
            Term(0.00000356672, 2.91954114478, 0.06731030280),
            Term(0.00000284125, 1.89869240932, 796.29800681640),
            Term(0.00000242879, 0.34481445893, 5486.77784317500),
            Term(0.00000317087, 5.84901948512, 11790.62908865880),
            Term(0.00000271112, 0.31486255375, 10977.07880469900),
            Term(0.00000206217, 4.80646631478, 2544.31441988340),
            Term(0.00000205478, 1.86953770281, 5573.14280143310),
            Term(0.00000202318, 2.45767790232, 6069.77675455340),
            Term(0.00000126225, 1.08295459501, 20.77539549240),
            Term(0.00000155516, 0.83306084617, 213.29909543800),
        ],
        [
            Term(6283.07584999140, 0.00000000000, 0.00000000000),
            Term(0.00206058863, 2.67823455808, 6283.07584999140),
            Term(0.00004303419, 2.63512233481, 12566.15169998280),
        ],
        [
            Term(0.00008721859, 1.07253635559, 6283.07584999140),
        ],
    ]
    static let latitude: [[Term]] = [
        [
        ],
        [
            Term(0.00227777722, 3.41376620530, 6283.07584999140),
            Term(0.00003805678, 3.37063423795, 12566.15169998280),
        ],
        [
        ],
    ]
    static let radius: [[Term]] = [
        [
            Term(1.00013988784, 0.00000000000, 0.00000000000),
            Term(0.01670699632, 3.09846350258, 6283.07584999140),
            Term(0.00013956024, 3.05524609456, 12566.15169998280),
            Term(0.00003083720, 5.19846674381, 77713.77146812050),
            Term(0.00001628463, 1.17387558054, 5753.38488489680),
            Term(0.00001575572, 2.84685214877, 7860.41939243920),
            Term(0.00000924799, 5.45292236722, 11506.76976979360),
            Term(0.00000542439, 4.56409151453, 3930.20969621960),
            Term(0.00000472110, 3.66100022149, 5884.92684658320),
            Term(0.00000085831, 1.27079125277, 161000.68573767410),
            Term(0.00000057056, 2.01374292245, 83996.84731811189),
            Term(0.00000055736, 5.24159799170, 71430.69561812909),
            Term(0.00000174844, 3.01193636733, 18849.22754997420),
            Term(0.00000243181, 4.27349530790, 11790.62908865880),
        ],
        [
            Term(0.00103018607, 1.10748968172, 6283.07584999140),
            Term(0.00001721238, 1.06442300386, 12566.15169998280),
        ],
        [
            Term(0.00004359385, 5.78455133808, 6283.07584999140),
        ],
    ]

    /// Heliocentric position of the Earth in J2000 equatorial coordinates (AU), at TT `time`.
    static func heliocentric(_ time: AstroTime) -> Vec3 {
        let t = time.tt / 365_250.0
        let lon = evaluate(longitude, t, isLongitude: true)
        let lat = evaluate(latitude, t, isLongitude: false)
        let rad = evaluate(radius, t, isLongitude: false)
        // Ecliptic spherical → ecliptic Cartesian (VSOP87 dynamical ecliptic of J2000).
        let rcl = rad * cos(lat)
        let ex = rcl * cos(lon), ey = rcl * sin(lon), ez = rad * sin(lat)
        // VSOP87 ecliptic → FK5 equatorial (VsopRotate).
        return Vec3(
            ex + 0.000000440360 * ey - 0.000000190919 * ez,
            -0.000000479966 * ex + 0.917482137087 * ey - 0.397776982902 * ez,
            0.397776982902 * ey + 0.917482137087 * ez
        )
    }

    private static func evaluate(_ formula: [[Term]], _ t: Double, isLongitude: Bool) -> Double {
        var total = 0.0
        var tpower = 1.0
        for series in formula {
            var sum = 0.0
            for term in series {
                sum += term.amplitude * cos(term.phase + t * term.frequency)
            }
            var incr = tpower * sum
            if isLongitude { incr = fmod(incr, AstroConstants.pi2) }
            total += incr
            tpower *= t
        }
        return total
    }
}
