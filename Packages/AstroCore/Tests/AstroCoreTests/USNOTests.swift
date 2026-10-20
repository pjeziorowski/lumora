// Packages/AstroCore/Tests/AstroCoreTests/USNOTests.swift
//
// Golden values published by the U.S. Naval Observatory, as archived (with parsing scripts)
// in the Astronomy Engine repository, MIT licence, https://github.com/cosinekitty/astronomy:
//   Golden/usno_seasons.txt    ← generate/seasons/seasons.txt (USNO "Earth's Seasons", 1900–2100)
//   Golden/usno_moonphases.txt ← generate/moonphase/moonphases.txt (USNO "Phases of the Moon", 1900–2100)
//   Golden/usno_riseset.txt    ← generate/riseset/riseset.txt (USNO "Rise/Set Table for One Year")
// USNO publishes these to the minute, so ±1 min is the best agreement the data can show.

import Foundation
import Testing
@testable import AstroCore

struct USNOTests {
    @Test func seasons1900to2100() {
        var stats = ErrorStats("Equinox/solstice vs USNO 1900-2100", unit: "s")
        var byYear: [Int: SeasonInfo] = [:]
        for line in Golden.lines("usno_seasons") {
            let parts = line.split(separator: " ")
            guard parts.count == 2, parts[1] == "Equinox" || parts[1] == "Solstice" else { continue }
            let expected = Golden.time(String(parts[0]))
            let year = Int(parts[0].prefix(4))!
            let month = Int(parts[0].dropFirst(5).prefix(2))!
            if byYear[year] == nil { byYear[year] = Seasons.of(year: year) }
            guard let info = byYear[year] else {
                Issue.record("Seasons search failed for \(year)")
                continue
            }
            let actual: AstroTime
            switch month {
            case 3: actual = info.marchEquinox
            case 6: actual = info.juneSolstice
            case 9: actual = info.septemberEquinox
            default: actual = info.decemberSolstice
            }
            let err = abs(actual.ut - expected.ut) * 86_400
            stats.add(err, String(parts[0]))
            // USNO rounds to the minute: allow 30 s rounding + engine error.
            #expect(err < 150, "\(parts[0]) off by \(err) s")
        }
        Report.line(stats)
        #expect(stats.count == 804)
    }

    @Test func moonPhases1900to2100() {
        var stats = ErrorStats("Moon quarters vs USNO 1900-2100", unit: "s")
        let lines = Golden.lines("usno_moonphases")
        let expected = lines.map { line -> (Int, AstroTime) in
            let parts = line.split(separator: " ")
            return (Int(parts[0])!, Golden.time(String(parts[1])))
        }
        // The table holds one year per decade. Walk quarters sequentially within each year,
        // restarting a day before the first entry after each gap.
        var cursor = expected[0].1.addingDays(-1)
        for (quarter, time) in expected {
            if time.ut - cursor.ut > 10 { cursor = time.addingDays(-1) }
            guard let found = Lunar.nextQuarter(after: cursor) else {
                Issue.record("No quarter after \(cursor)")
                return
            }
            #expect(found.quarter.rawValue == quarter)
            let err = abs(found.time.ut - time.ut) * 86_400
            stats.add(err, "q\(quarter) \(time.date)")
            #expect(err < 150, "quarter \(quarter) at \(time.date) off by \(err) s")
            cursor = found.time.addingDays(6)
        }
        Report.line(stats)
    }

    /// USNO yearly rise/set tables, including polar (89° N, 88° S) and southern-hemisphere sites.
    @Test func riseSetTables() {
        struct Key: Hashable { let body: String; let lon: Double; let lat: Double }
        var groups: [Key: [(AstroTime, RiseSetDirection)]] = [:]
        var order: [Key] = []
        for line in Golden.lines("usno_riseset") {
            let p = line.split(separator: " ", omittingEmptySubsequences: true)
            let key = Key(body: String(p[0]), lon: Double(p[1])!, lat: Double(p[2])!)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append((Golden.time(String(p[3])), p[4] == "r" ? .rise : .set))
        }
        var sun = ErrorStats("Sun rise/set vs USNO tables, |lat| <= 80", unit: "s")
        var sunPolar = ErrorStats("Sun rise/set vs USNO tables, |lat| > 80 (grazing)", unit: "s")
        var moon = ErrorStats("Moon rise/set vs USNO tables", unit: "s")
        var missing = 0
        for key in order {
            guard let rows = groups[key], let first = rows.first, let last = rows.last else { continue }
            let body: Body = key.body == "Sun" ? .sun : .moon
            let observer = Observer(latitude: key.lat, longitude: key.lon)
            let computed = Almanac.riseSetEvents(body, observer: observer,
                                                 from: first.0.addingDays(-0.01), to: last.0.addingDays(0.01))
            for (time, direction) in rows {
                let candidates = computed.filter { $0.direction == direction }
                guard let nearest = candidates.min(by: { abs($0.time.ut - time.ut) < abs($1.time.ut - time.ut) }) else {
                    missing += 1
                    continue
                }
                let err = abs(nearest.time.ut - time.ut) * 86_400
                let label = "\(key.body) \(key.lat),\(key.lon) \(time.date) \(direction)"
                if body == .moon {
                    moon.add(err, label)
                } else if abs(key.lat) > 80 {
                    sunPolar.add(err, label)
                } else {
                    sun.add(err, label)
                }
                // USNO rounds to the minute; polar grazing events can differ by more because the
                // Sun skims the horizon for hours. Astronomy Engine's own test allows the same.
                let tolerance = abs(key.lat) > 80 ? 30.0 * 60 : 90.0
                #expect(err <= tolerance, "\(label): off by \(err) s")
            }
            #expect(computed.count == rows.count,
                    "\(key.body) \(key.lat),\(key.lon): USNO lists \(rows.count) events, computed \(computed.count)")
        }
        #expect(missing == 0)
        Report.line(sun)
        Report.line(sunPolar)
        Report.line(moon)
    }
}
