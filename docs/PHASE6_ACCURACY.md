# Phase 6 acceptance: geodetics, Find, obstacles

Measured with `scripts/test-packages.sh` (Swift 6.1.3, Linux x86-64). Tests:
`Packages/GeoCore/Tests/GeoCoreTests/SightlineTests.swift`,
`Packages/PlannerKit/Tests/PlannerKitTests/FindTests.swift`,
`Packages/PlannerKit/Tests/PlannerKitTests/GeodeticsPlannerTests.swift`; screenshots from
`App/UITests/ScreenshotTests.swift` (`testPhase6Geodetics`).

## Geodetics against a GIS tool

Golden: GeographicLib `GeodSolve` (Karney's algorithms, accurate to 15 nm), from its man page
example JFK → Singapore Changi.

| Quantity | GeographicLib | Lumora (Vincenty) | Difference | Target |
|---|---|---|---|---|
| Distance | 15 347 628 m | 15 347 627.66 m | 0.34 m (2e-8) | 0.1% |
| Initial bearing | 003°18'29.9" | +0.025" | 7e-6° | 0.1° |
| Final bearing | 177°29'09.2" | +0.048" | 1.3e-5° | 0.1° |
| Point 2000 km along the line | 58°34'45.1"N 71°49'36.7"W | 0.04" / 0.02" | ~1 m | — |

Short lines were already checked against Geoscience Australia's worked example (Phase 3):
54 972.271 m within 2 mm.

## Lines of sight

- Drop below the observer's horizontal plane: d²/(2kR) with k = 1.15 (refraction coefficient
  0.13). 1 km: 0.0683 m, within 2% of the levelling constant 0.0675 m/km²; k = 1 gives pure
  curvature, 0.0785 m/km². Horizon from 2 m with k = 1: 5.05 km (3.57·√h km).
- Apparent elevation of a point: atan((h₂ − h₁ − d²/(2kR)) / d), and its inverse (the height a
  point needs to appear at an angle) round-trip to 1e-9 m.
- Ground elevations come from the Open-Meteo Elevation API (Copernicus GLO-90 DEM, ~90 m grid),
  cached per ~11 m cell; failures are not cached and the panel says "Unknown (sea level used)".

## Find reproduces a known alignment

Golden: AMNH Hayden Planetarium, Manhattanhenge 2026 (street-grid azimuth 299.1°, "altitude about
half a degree"). Find for the Sun at 299.1° ± 0.15°, elevation 0.5° ± 0.5°, April–August 2026,
from 34th Street:

| AMNH | Lumora match | Difference |
|---|---|---|
| Thu 28 May 20:14 (half sun) | 20:13:19, el 0.44° | −41 s |
| Fri 29 May 20:13 (full sun) | 20:12:47, el 0.63° | −13 s |
| Sat 11 Jul 20:20 (full sun) | 20:19:49, el 0.94° | −11 s |
| Sun 12 Jul 20:21 (half sun) | 20:20:33, el 0.77° | −27 s |

The search also returns the neighbouring evenings (26–31 May, 11–16 July), when the Sun is on
the grid with the disc between 0° and 1°, as expected for that tolerance. Crossings are
bracketed on a 5-minute grid and bisected to under a second; this five-month search takes
0.9 s on Linux (debug build), run off the main thread in the app.

## Obstacle panel

- The Sun or Moon "on the line" is the moment it crosses the target's bearing today, from Find.
- Clearance = body elevation − apparent angle to the object's top. Setting the object height
  to the reported "height for the Sun on top" gives a clearance of 0 (tested to 1e-6°).
- Panels 6 and 7 show "None" until a target pin exists; the target can be anywhere, including
  across the antimeridian (lines are unwrapped like the other overlays).

## Field and depth of field on the map

The wedge is the horizontal angle of view of the chosen camera and lens along the target's
bearing (or a set bearing); arcs mark the near limit, the focus distance and the far limit
from OpticsCore's depth-of-field formulas. Tested: 50 mm on full frame draws edges at
bearing ± 19.8°, and the far arc lies at the computed far limit to 1 cm.
