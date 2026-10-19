// Packages/AstroCore/Tests/AstroCoreTests/EclipseTests.swift
//
// Phase 9 acceptance: eclipse contact times against NASA (Fred Espenak, NASA/GSFC eclipse
// web site, "Total Lunar Eclipse of 2019 Jan 21", "… 2022 Nov 08", "… 2025 Mar 14": contact
// times P1, U1, U2, greatest, U3, U4, P4 in UT), and the time and place of greatest eclipse
// for four total solar eclipses (NASA "Total Solar Eclipse of 1999 Aug 11 / 2017 Aug 21 /
// 2024 Apr 08 / 2026 Aug 12"; NASA quotes greatest eclipse in TD, converted to UT with the
// ΔT NASA gives on the same page).

import Foundation
import Testing
@testable import AstroCore

struct EclipseTests {
    static func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    struct LunarGolden {
        let start: (Int, Int, Int)
        let contacts: [String] // P1, U1, U2, greatest, U3, U4, P4
    }

    static let lunar = [
        LunarGolden(start: (2019, 1, 1), contacts: ["2019-01-21T02:36:29Z", "2019-01-21T03:33:54Z", "2019-01-21T04:41:17Z",
                                                   "2019-01-21T05:12:14Z", "2019-01-21T05:43:16Z", "2019-01-21T06:50:39Z",
                                                   "2019-01-21T07:48:00Z"]),
        LunarGolden(start: (2022, 10, 1), contacts: ["2022-11-08T08:02:17Z", "2022-11-08T09:09:12Z", "2022-11-08T10:16:39Z",
                                                    "2022-11-08T10:59:11Z", "2022-11-08T11:41:38Z", "2022-11-08T12:49:04Z",
                                                    "2022-11-08T13:56:09Z"]),
        LunarGolden(start: (2025, 1, 1), contacts: ["2025-03-14T03:57:28Z", "2025-03-14T05:09:40Z", "2025-03-14T06:26:06Z",
                                                   "2025-03-14T06:58:43Z", "2025-03-14T07:31:26Z", "2025-03-14T08:47:52Z",
                                                   "2025-03-14T10:00:09Z"]),
    ]

    @Test func lunarContactsMatchNASA() throws {
        var worst = 0.0
        for golden in Self.lunar {
            let e = try #require(Eclipses.nextLunarEclipse(after: AstroTime(year: golden.start.0, month: golden.start.1,
                                                                             day: golden.start.2)))
            #expect(e.kind == .total)
            let ours = [e.penumbralBegin, e.partialBegin, e.totalBegin, e.peak, e.totalEnd, e.partialEnd, e.penumbralEnd]
            for (time, expected) in zip(ours, golden.contacts) {
                let diff = try #require(time).date.timeIntervalSince(Self.utc(expected))
                worst = max(worst, abs(diff))
                #expect(abs(diff) <= 60, "\(expected): \(diff) s")
            }
        }
        print("ACCURACY | lunar eclipse contacts vs NASA, 3 eclipses × 7 contacts: max \(Int(worst.rounded())) s")
    }

    @Test func solarGreatestEclipseMatchesNASA() throws {
        // (search start, greatest eclipse UT, latitude, longitude)
        let golden: [((Int, Int), String, Double, Double)] = [
            ((1999, 7), "1999-08-11T11:03:05Z", 45 + 4.0 / 60, 24 + 18.0 / 60),
            ((2017, 8), "2017-08-21T18:25:32Z", 36 + 58.0 / 60, -(87 + 40.0 / 60)),
            ((2024, 4), "2024-04-08T18:17:20Z", 25 + 17.0 / 60, -(104 + 8.0 / 60)),
            ((2026, 8), "2026-08-12T17:45:57Z", 65 + 10.0 / 60, -(25 + 13.0 / 60)),
        ]
        var worstTime = 0.0, worstPlace = 0.0
        for (start, time, lat, lon) in golden {
            let e = try #require(Eclipses.nextGlobalSolarEclipse(after: AstroTime(year: start.0, month: start.1, day: 1)))
            #expect(e.kind == .total)
            let dt = e.peak.date.timeIntervalSince(Self.utc(time))
            let dLat = try #require(e.latitude) - lat, dLon = try #require(e.longitude) - lon
            worstTime = max(worstTime, abs(dt))
            worstPlace = max(worstPlace, abs(dLat), abs(dLon))
            #expect(abs(dt) <= 60, "\(time): \(dt) s")
            #expect(abs(dLat) < 0.1 && abs(dLon) < 0.1, "\(time): \(dLat)°, \(dLon)°")
        }
        print("ACCURACY | solar greatest eclipse vs NASA, 4 eclipses: time max \(Int(worstTime.rounded())) s, "
              + "place max \(String(format: "%.3f", worstPlace))°")
    }

    @Test func centralLineCrossesTheUS() throws {
        // 2017 Aug 21: the path ran from Oregon (≈44.6°N 124°W, about 17:16 UT) to South
        // Carolina (≈33°N 79.5°W, about 18:48 UT) and passed greatest eclipse in Kentucky.
        let e = try #require(Eclipses.nextGlobalSolarEclipse(after: AstroTime(year: 2017, month: 8, day: 1)))
        let line = Eclipses.centralLine(of: e)
        #expect(line.count > 50)
        let oregon = try #require(line.min { abs($0.longitude + 124) < abs($1.longitude + 124) })
        #expect(abs(oregon.latitude - 44.6) < 0.5)
        #expect(abs(oregon.time.date.timeIntervalSince(Self.utc("2017-08-21T17:16:00Z"))) < 180)
        let carolina = try #require(line.min { abs($0.longitude + 79.5) < abs($1.longitude + 79.5) })
        #expect(abs(carolina.latitude - 33) < 0.6)
        // West to east, in time order.
        #expect(line.first!.longitude < line.last!.longitude)
    }

    @Test func eclipseSequenceAndKinds() throws {
        // 2017–2022: the lunar eclipses in order with their NASA types.
        var t = AstroTime(year: 2017, month: 1, day: 1)
        var kinds: [EclipseKind] = []
        for _ in 0..<11 {
            let e = try #require(Eclipses.nextLunarEclipse(after: t))
            kinds.append(e.kind)
            t = e.peak.addingDays(10)
        }
        #expect(kinds == [.penumbral, .partial, .total, .total, .total, .partial, .penumbral, .penumbral, .penumbral,
                          .penumbral, .total])
        // The partial eclipse of 2021 Nov 19 covered 97.4% of the Moon's diameter (umbral
        // magnitude 0.974): nearly all of its area.
        let deep = try #require(Eclipses.nextLunarEclipse(after: AstroTime(year: 2021, month: 11, day: 1)))
        #expect(deep.kind == .partial && deep.obscuration > 0.95)
        // Solar: annular 2019 Dec 26, annular 2024 Oct 02, partial 2025 Mar 29.
        let annular = try #require(Eclipses.nextGlobalSolarEclipse(after: AstroTime(year: 2019, month: 12, day: 1)))
        #expect(annular.kind == .annular)
        let partial = try #require(Eclipses.nextGlobalSolarEclipse(after: AstroTime(year: 2025, month: 3, day: 1)))
        #expect(partial.kind == .partial && partial.latitude == nil)
    }

    @Test func localCircumstances() throws {
        // Dallas, 2024 Apr 08: total, about four minutes of totality around 18:42 UT.
        let dallas = Observer(latitude: 32.7767, longitude: -96.7970, height: 140)
        let e = try #require(Eclipses.nextLocalSolarEclipse(after: AstroTime(year: 2024, month: 1, day: 1), observer: dallas))
        #expect(e.kind == .total)
        let begin = try #require(e.totalBegin), end = try #require(e.totalEnd)
        let totality = end.time.date.timeIntervalSince(begin.time.date)
        #expect(totality > 220 && totality < 245)
        #expect(e.peak.time.date.timeIntervalSince(Self.utc("2024-04-08T18:42:37Z")) < 60)
        #expect(e.partialBegin.time < begin.time && end.time < e.partialEnd.time)
        // Warsaw, 2026 Aug 12: partial, the Sun setting during the eclipse.
        let warsaw = Observer(latitude: 52.2297, longitude: 21.0122, height: 100)
        let w = try #require(Eclipses.nextLocalSolarEclipse(after: AstroTime(year: 2026, month: 1, day: 1), observer: warsaw))
        #expect(w.kind == .partial && w.totalBegin == nil)
        #expect(w.partialBegin.altitude > 0 && w.partialEnd.altitude < 0)
        #expect(w.magnitude > 0.8 && w.magnitude < 0.9)
        // An eclipse entirely at night is skipped: none of 2024 Apr 08 from Warsaw.
        #expect(Calendar(identifier: .gregorian).component(.year, from: w.peak.time.date) == 2026)
    }
}
