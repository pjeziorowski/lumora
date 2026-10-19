# Phase 2 acceptance: Sun and Moon pills

Measured with `scripts/test-packages.sh` (Swift 6.1.3, Linux x86-64). PlannerKit: 31 tests pass.
Tests: `Packages/PlannerKit/Tests/PlannerKitTests/ReferenceSitesTests.swift` and `PillsTests.swift`.

## Reference sites (USNO "Sun and Moon Data for One Day", retrieved 2026-10-19)

The pill reports (the exact values the screens show) against USNO for six places. USNO publishes
to the minute and assumes a sea-level observer, so test observers have elevation 0.

| Place | Date | Notes |
|---|---|---|
| Warsaw | 2026-03-29 | Day of the switch to summer time (23 h day) |
| New York | 2026-07-04 | Western hemisphere, summer time |
| Sydney | 2026-01-15 | Southern hemisphere, UTC+11 |
| Quito | 2026-09-23 | Equator, near the equinox |
| Tromsø | 2026-06-10 | Midnight sun: no sunrise/sunset, solar noon only |
| Tromsø | 2026-12-10 | Polar night: Sun and Moon below the horizon all day; civil twilight 09:15–13:59 |
| Cape Town | 2026-06-21 | Southern winter; no moonset that day |

| Quantity | Samples | Mean error | Max error | Target |
|---|---|---|---|---|
| Sunrise, sunset, civil dawn/dusk, solar noon | 28 | 16 s | 30 s | ±60 s |
| Moonrise, moonset, moon transit | 17 | 13 s | 28 s | ±60 s |
| Moon illumination | 7 | 0.16 % | 0.41 % | ±1 % |

Every "no event" case matches USNO exactly (event lists are empty and the polar state is right).

## Moon phase lists

- New and full moons 2026 vs USNO "Phases of the Moon" (UT, to the minute): 25 events, mean 41 s,
  max 78 s. Phase 1 measured the same engine against USNO 1900–2100 (1038 quarters, max 79 s).
- Supermoons use timeanddate.com's definition (new or full moon closer than 360,000 km;
  micromoon beyond 405,000 km). Their "next super full moon 24 Dec 2026" and "next super new moon
  16 May 2026" both match. The thresholds live in `SupermoonRule`.
- Blue moons: 31 May 2026 is the monthly blue moon (second full moon in May) in Warsaw and at
  UTC+14; 18 May 2019 is the seasonal blue moon (third of four in spring), as timeanddate.com lists.

## Other checks

- Midnight sun at Tromsø 2026: 19 May – 25 July; polar night 28 Nov 2026 – 14 Jan 2027
  (upper-limb rule with 34′ refraction; sanity range only, no external table).
- Seasons flip for the southern hemisphere; month tables and phase calendars cover DST days and
  the right number of days; the coordinate parser handles decimal, hemisphere letters and DMS.

## Decisions made here

- The Moon calendar shows the phase at local noon of each day, and marks the day holding each
  principal phase instant.
- Monthly blue moons are counted in the pin's time zone (they can differ by place);
  seasonal blue moons use the global equinox/solstice instants.
- Golden/blue hour spans are split into morning and evening at solar noon.
- The location picker takes the time zone from MapKit (search) or reverse geocoding (current
  location, typed coordinates). Offline or at sea it falls back to the 15° nautical zone.
