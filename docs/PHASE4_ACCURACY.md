# Phase 4 acceptance: Milky Way

Measured with `scripts/test-packages.sh` (Swift 6.1.3, Linux x86-64). AstroCore: 34 tests pass,
PlannerKit: 57. Tests: `Packages/AstroCore/Tests/AstroCoreTests/MilkyWayTests.swift`,
`Packages/PlannerKit/Tests/PlannerKitTests/MilkyWayPlannerTests.swift`; screenshots from
`App/UITests/ScreenshotTests.swift` (`testPhase4MilkyWay`).

## Definitions

- Galactic centre: the origin of the galactic frame, 17h45m37.20s −28°56′10.2″ (J2000), with
  the north galactic pole at α 192.85948°, δ +27.12825° (Hipparcos Catalogue vol. 1 §1.5.3).
  Both are tested to 0.1 s / 2″ and 1e-6°.
- Visible window: Sun's geometric centre below −18° **and** the core above the horizon
  (refracted). Moon-free: visible and the Moon below the horizon or less than 10% lit.
  The thresholds live in `MilkyWayConditions`.
- Edges are found on a 10-minute grid and refined by bisection to under 15 s.

## Against Skyfield + JPL DE421 (`Tools/golden/generate_milkyway.py`)

Five sites (Joshua Tree 34°N, La Palma 29°N, Warsaw 52°N, San Pedro de Atacama 23°S,
Sydney 34°S), the ten 2026 new-moon nights from February to December.

| Quantity | Samples | Mean | Max | Target |
|---|---|---|---|---|
| Core window start/end | 86 edges | 0.19 min | 0.80 min | ±2 min |
| Number of windows per night (including nights with none) | 50 nights | exact | exact | exact |
| Core azimuth (elevation > 5°) | 13 | — | 0.0064° | 0.1° |
| Core elevation (elevation > 5°) | 13 | — | 0.0115° | 0.1° |
| Arc tilt (angle of the band to the horizon at the core) | 25 | — | 0.010° | 0.5° |

Below 5° the two refraction models differ (Skyfield stops refracting below −1°); there the
position agrees within 1° in elevation and 0.1° in azimuth.

## Season tables

Hours of core visibility per month in 2026 (`MilkyWayYearReport`, 15-minute grid), Jan → Dec:

| Site | First – last core night | Hours per month | Best months (Moon-free hours) |
|---|---|---|---|
| Joshua Tree 34°N | 13 Jan – 20 Nov | 10 52 99 133 179 182 179 136 94 58 11 0 | Jun, Jul, May |
| New York 41°N | 19 Jan – 12 Nov | 6 41 82 111 150 144 146 112 77 44 6 0 | Jun, Jul, May |
| Warsaw 52°N | 7 Feb – 22 Oct | 0 10 36 50 29 0 9 41 29 8 0 0 | Apr, May, Aug |
| Atacama 23°S | 5 Jan – 30 Nov | 32 95 174 233 307 318 313 250 175 114 38 0 | Jun, Jul, May |
| Sydney 34°S | 6 Jan – 29 Nov | 30 97 184 250 323 334 332 270 192 122 40 0 | Jun, Jul, May |
| Cape Town 34°S | 7 Jan – 29 Nov | 30 98 185 251 326 332 333 270 190 121 39 0 | Jun, Jul, May |

This matches the published season tables (e.g. the widely used "Milky Way season" guides and
calendars): the core is visible roughly February to October in the northern hemisphere and
for longer in the southern one, peaks in June and July, and is gone in December everywhere.
At 52°N there is no astronomical night from late May to late July, so the season has a summer
gap; the core also never climbs above ~9° there (90° − 52.2° − 28.9°). With a practical
minimum core elevation of 10° the edges move inward: Joshua Tree 3 Feb – 30 Oct, Sydney
18 Jan – 18 Nov, Warsaw none.

The tests assert this shape: northern season starts in January/February and ends in
October/November, December has no window, the best three months fall in May–August
(April–August in the south), Warsaw has none in June and almost none in July, and the
best nights all have the Moon less than 35% lit.

## Planner

- Panel 5 shows the core's azimuth/elevation now, the night's visible, dark and Moon-free
  windows, the Moon's interference and the arc orientation. Before local noon it shows the
  night that is ending, after noon the night that is starting.
- The map draws the core's direction and the galactic plane above the horizon (5° steps) with
  the same projection as the Sun and Moon; layers can be switched off individually.
- "Milky Way from" and "Milky Way until" jumps go to window edges that fall in the pin's day.
- At the north pole the core never rises (no window, no crash); half the band is still drawn.
