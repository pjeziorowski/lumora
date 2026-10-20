# AstroCore golden data

| File | Source | Used by |
|---|---|---|
| `cities.json` | Skyfield 1.55 + JPL DE421, USNO rise/set definitions (aa.usno.navy.mil/faq/RST_defs). Warsaw, Reykjavik, Tromsø, Sydney, Quito, Honolulu × 2025/2026 equinox and solstice dates. Regenerate with `Tools/golden/generate_golden.py`. | `CityGoldenTests` |
| `apsides.json` | Same generator: lunar perigee/apogee 2025–2026 from DE421. | `EdgeCaseTests.lunarApsides` |
| `usno_seasons.txt` | USNO "Earth's Seasons" 1900–2100, via Astronomy Engine `generate/seasons/seasons.txt` (MIT). | `USNOTests.seasons1900to2100` |
| `usno_moonphases.txt` | USNO "Phases of the Moon", one year per decade 1900–2100, via Astronomy Engine `generate/moonphase/moonphases.txt`. | `USNOTests.moonPhases1900to2100` |
| `usno_riseset.txt` | USNO "Rise/Set Table for One Year" for 15 site-and-body series incl. 89° N, 88° S, the poles, 61° S, 60° S and 45° S, via Astronomy Engine `generate/riseset/riseset.txt`. | `USNOTests.riseSetTables` |

## Why the city table is DE421, not USNO directly

The build container that produced Phase 1 could not reach `aa.usno.navy.mil` (or NOAA,
timeanddate, JPL Horizons). DE421 is the JPL ephemeris family USNO itself uses, and Skyfield's
almanac follows USNO's published rise/set definitions, so it is an independent, higher-accuracy
reference than USNO's minute-rounded tables. The USNO tables above still cover rise/set,
seasons and phases with genuine USNO numbers.

To spot-check a row against USNO by hand: https://aa.usno.navy.mil/data/RS_OneDay
(enter the city's latitude/longitude, height 0, and the UTC offset in `cities.json`).
