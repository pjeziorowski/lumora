// Packages/PlannerKit/Tests/PlannerKitTests/EventsTests.swift
//
// Phase 9: meteor shower nights and calendars, eclipse lists for a place, and the Planner's
// panels 8 and 9 with their map overlays.

import AstroCore
import Foundation
import Testing
@testable import PlannerKit

struct EventsTests {
    let warsaw = PillLocation.samples[0]
    let newYork = PillLocation.samples[1]
    let sydney = PillLocation.samples[2]

    func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test func perseids2026() throws {
        let year = MeteorShowerCalendar.year(2026, location: warsaw)
        #expect(year.count == MeteorShowers.all.count)
        #expect(year.map(\.peak) == year.map(\.peak).sorted())
        let perseids = try #require(year.first { $0.shower.code == "PER" })
        // New Moon on 12 Aug 2026 (the day of the solar eclipse): a dark peak night, the
        // radiant high before dawn.
        #expect(perseids.peakNight.moonIllumination < 0.05)
        let best = try #require(perseids.peakNight.best)
        #expect(best.radiantAltitude > 50 && best.rate > 60)
        #expect(perseids.peakNight.rating == .excellent)
        // From Sydney the Perseid radiant (Dec +58°) never rises.
        let south = MeteorNightReport.compute(shower: perseids.shower, location: sydney, day: perseids.peakNight.day)
        #expect(south.best == nil && south.rating == .poor)
    }

    @Test func etaAquariidsFavourTheSouth() throws {
        let north = try #require(MeteorShowerCalendar.year(2026, location: warsaw).first { $0.shower.code == "ETA" })
        let south = try #require(MeteorShowerCalendar.year(2026, location: sydney).first { $0.shower.code == "ETA" })
        #expect((south.peakNight.best?.rate ?? 0) > (north.peakNight.best?.rate ?? 0))
    }

    @Test func activeShowersAndYearEnd() {
        let august = MeteorShowerCalendar.active(at: utc("2026-08-12T22:00:00Z"), timeZone: warsaw.timeZone)
        #expect(august.first?.shower.code == "PER")
        #expect(Set(august.map(\.shower.code)).isSuperset(of: ["PER", "SDA", "CAP"]))
        // The Quadrantids run across New Year.
        for date in ["2025-12-30T22:00:00Z", "2026-01-02T22:00:00Z"] {
            #expect(MeteorShowerCalendar.active(at: utc(date), timeZone: warsaw.timeZone).contains { $0.shower.code == "QUA" })
        }
        #expect(MeteorShowerCalendar.active(at: utc("2026-03-10T22:00:00Z"), timeZone: warsaw.timeZone).isEmpty)
    }

    @Test func eclipseCalendar() throws {
        let list = EclipseCalendar.upcoming(location: warsaw, from: utc("2026-01-01T00:00:00Z"), count: 4)
        #expect(list.map(\.title) == ["Annular solar eclipse", "Total lunar eclipse", "Partial solar eclipse", "Partial lunar eclipse"])
        // 17 Feb 2026 is annular in Antarctica, nothing from Warsaw; the 3 Mar total lunar
        // eclipse happens in Warsaw's daytime.
        #expect(!list[0].visibleHere && !list[1].visibleHere)
        // 12 Aug 2026: partial from Warsaw with the Sun setting.
        let august = list[2]
        #expect(august.visibleHere && august.kind == .total && august.localKind == .partial)
        #expect(august.contacts.first?.label == "Partial begins")
        #expect((august.magnitude ?? 0) > 0.8)
        // The 3 Mar total lunar eclipse is seen from New York before dawn.
        let ny = EclipseCalendar.upcoming(location: newYork, from: utc("2026-02-20T00:00:00Z"), count: 1)
        #expect(ny.first?.title == "Total lunar eclipse" && ny.first?.visibleHere == true)
    }

    @MainActor
    @Test func plannerPanelsAndOverlays() async throws {
        let events = PlannerEvents.compute(location: warsaw, instant: utc("2026-08-12T20:00:00Z"))
        #expect(events.active.first?.shower.code == "PER")
        #expect(events.nextCentral?.kind == .total)
        #expect(events.centralLine.count > 40)
        #expect(events.visibleEclipses.first?.title == "Partial solar eclipse")
        let session = PillSession(defaults: nil, fallback: warsaw) { self.utc("2026-08-12T22:30:00Z") }
        let state = PlannerState(session: session)
        state.refresh()
        await state.settle()
        await state.settleEvents()
        let panels = state.panels(options: PlannerDisplayOptions(deviceTimeZone: warsaw.timeZone))
        let meteors = try #require(panels.first { $0.kind == .meteors })
        #expect(meteors.rows.first?.value.hasPrefix("Perseids") == true)
        #expect(meteors.rows.contains { $0.label == "Radiant" })
        let eclipse = try #require(panels.first { $0.kind == .eclipse })
        #expect(eclipse.rows.contains { $0.label == "Partial begins" })
        let overlays = try #require(state.events).overlays(instant: session.instant, radius: 2000, layers: .all)
        #expect(overlays.lines.contains { $0.body == .radiant } && overlays.lines.contains { $0.body == .eclipse })
        #expect(overlays.markers.contains { $0.body == .radiant })
        // A quiet night: nothing active, the next shower is named.
        let march = PlannerEvents.compute(location: warsaw, instant: utc("2026-03-10T20:00:00Z"))
        #expect(march.active.isEmpty && march.nextShower?.shower.code == "LYR")
    }
}
