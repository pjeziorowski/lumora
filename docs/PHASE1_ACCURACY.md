# Phase 1 accuracy report: AstroCore

Measured with `scripts/test-packages.sh` (Swift 6.1.3, Linux x86-64). All 23 AstroCore tests pass.
Brief targets: rise/set ±1 min of USNO/NOAA, azimuth/elevation ±0.1°, Moon illumination ±1%.

## Six cities × eight dates (48 pairs) vs JPL DE421 with USNO definitions

| Quantity | Samples | Mean error | Max error | Target |
|---|---|---|---|---|
| Sunrise/sunset | 88 | 1.5 s | 7.9 s (Reykjavik, June solstice) | ±60 s |
| Moonrise/moonset | 83 | 0.7 s | 1.7 s | ±60 s |
| Civil/nautical/astronomical twilight | 260 | 0.5 s | 1.1 s | ±60 s |
| Azimuth (Sun and Moon, alt > −10°) | 226 | 0.001° | 0.007° | ±0.1° |
| Elevation, airless | 384 | 0.000° | 0.001° | ±0.1° |
| Elevation, refracted (alt > 5°) | 174 | 0.001° | 0.002° | ±0.1° |
| Moon illuminated fraction | 192 | <0.01% | <0.01% | ±1% |

Event counts match exactly, including no-event days: Tromsø midnight sun (June) and polar night
(December), Reykjavik days with no moonrise, and two sunsets in one local day at Reykjavik in June.

## Published USNO tables (minute-rounded, so ±30 s is rounding)

| Quantity | Samples | Mean | Max |
|---|---|---|---|
| Sun rise/set, \|lat\| ≤ 80° (60° S, 15° N, 29° N, 60° N) | 2920 | 15 s | 32 s |
| Sun rise/set at 89° N / 88° S / poles (grazing) | 68 | 18 s | 71 s |
| Moon rise/set (incl. 61° S, 45° S, 80–85° N) | 2921 | 15 s | 35 s |
| Equinoxes and solstices 1900–2100 | 804 | 24 s | 140 s (2097) |
| New/first/full/last quarter, 1900–2100 | 1038 | 37 s | 79 s |

## Other checks

- Lunar perigee/apogee 2025–2026 vs DE421: time within 18 min (flat minimum), distance within 51 km.
- Meeus examples 7.a, 7.b (Julian Day) and 12.a (sidereal time, within 0.1 s).
- ΔT (Espenak–Meeus) within 1.5 s of IERS at 1900 and 2000; runs ~2 s high by 2020 and ~5 s by 2025.
  That moves the Moon by ~2.5″ and does not affect rise/set (which uses UT).
- Edge cases: dateline (±179.9999° agree to < 1 s), 23 h and 25 h DST days, southern hemisphere
  season flip, North Pole, golden-hour bands under midnight sun, years 1900 and 2100.

## Performance (release build, same machine)

- Sun + Moon azimuth/elevation: ~6 µs per instant.
- Full Sun + Moon day (all rises, sets, twilights, golden/blue hour, transits): ~2 ms.

## Decisions made here

- Twilight and golden/blue hour thresholds use the Sun's geometric centre (USNO convention for
  twilight). Defaults: golden −4°…+6°, blue −6°…−4°; all live in `SolarThresholds`.
- Rise/set uses the USNO convention (upper limb, 34′ refraction scaled by air density, sea-level
  horizon unless `metersAboveGround` is given).
- AstroCore uses UT ≈ UTC (leap-second offsets < 0.9 s are ignored), as Astronomy Engine does.
