# Phase 3 acceptance: Planner v1

Measured with `scripts/test-packages.sh` (Swift 6.1.3, Linux x86-64) and on CI (Xcode 16.4,
iPhone simulator). Tests: `Packages/PlannerKit/Tests/PlannerKitTests/PlannerTests.swift`,
`Packages/GeoCore/Tests/GeoCoreTests/GeodesyTests.swift`, `App/Tests/AppSmokeTests.swift`;
screenshots from `App/UITests/ScreenshotTests.swift` (`testPhase3Planner`).

## Overlays match the Sun and Moon tools

| Check | Result | Target |
|---|---|---|
| Planner snapshot vs Sun/Moon pill reports (rise, set, noon, transit, az/el, illumination, twilights), 6 places | identical values (same engine calls) | match |
| Bearing of each drawn line (now, rise, set) vs the azimuth the tools report, 6 places | max 1e-6° | match |
| Path projection: horizon crossing on the radius circle, zenith at the pin | exact (1e-4 m) | — |

Lines are WGS84 geodesics (Vincenty). Golden: Geoscience Australia's Flinders Peak → Buninyong
worked example, distance within 2 mm, azimuths within 0.5″, direct problem within 1 cm; WGS84
meridian quadrant within 1 cm.

## Dateline and polar regions

- `pinSweepAcrossDatelineAndPoles`: 210 cases (10 latitudes from −90° to 90°, including ±89.9°,
  ±66.6° and 89.99°; 7 longitudes 179.9°…−179.9° across the antimeridian plus 0°; a midnight-sun
  date, a polar-night date and an equinox) build overlays and panels with no NaN or infinite
  coordinates and no crash.
- Lines crossing the antimeridian stay continuous (longitudes are unwrapped next to the pin, and
  the map shifts points by whole world widths): no line wraps round the map (`datelineOverlaysAreContinuous`,
  `mapPointsUnwrapAcrossAntimeridian` in the app tests). Polar points are clamped to MapKit's
  ±85.05° (`polarPointsStayOnTheMap`).
- Longyearbyen in June shows the midnight sun: no sunrise or sunset lines, a full path above the
  horizon and plain-language panel rows.

## Scrubbing cost

| Step | Debug build, Linux x86-64 | Budget |
|---|---|---|
| New minute, day cached | 0.96 ms | 16.7 ms (60 fps frame) |
| Day change (rise/set searches, paths, light bands) | 95 ms, prefetched for the neighbouring days | once per drag across midnight |

Scrub requests are coalesced: while one computation runs, only the latest instant is kept
(`coalescesRapidScrubs`). Snapshots are memoized per (place, minute) and days per (place, local day).
**Not verified:** 60 fps on an iPhone 12-class device; there is no device in this setup.

## Time zone from coordinates

A dropped pin resolves its name and time zone by reverse geocoding (cached per ~1 km cell);
when that fails or returns no zone, the pin falls back to the nautical zone for its longitude
and the panel says so. A bundled tz-boundary fallback is left for later, as the brief allows.
