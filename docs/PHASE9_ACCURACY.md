# Phase 9 acceptance: meteor showers and eclipses

Measured with `scripts/test-packages.sh` (Swift 6.1.3, Linux x86-64). AstroCore: 42 tests
pass; PlannerKit: 83 tests pass. Tests: `Packages/AstroCore/Tests/AstroCoreTests/EclipseTests.swift`,
`MeteorShowerTests.swift` and `Packages/PlannerKit/Tests/PlannerKitTests/EventsTests.swift`;
screenshots from `App/UITests/ScreenshotTests.swift` (`testPhase9Events`).

## Eclipses

The search is a Swift port of Astronomy Engine's eclipse functions (`SearchLunarEclipse`,
`SearchGlobalSolarEclipse`, `SearchLocalSolarEclipse` and their helpers, MIT licence): the
Moon's or Earth's shadow axis is found at each new or full Moon, and contacts are the times the
shadow cone edge touches the Moon or the observer.

| Check (source) | Result |
|---|---|
| Lunar contacts P1, U1, U2, greatest, U3, U4, P4 for the total lunar eclipses of 2019 Jan 21, 2022 Nov 08, 2025 Mar 14 (NASA/GSFC, F. Espenak) | max 39 s |
| Solar greatest eclipse time and place, 1999 Aug 11, 2017 Aug 21, 2024 Apr 08, 2026 Aug 12 (NASA; TD → UT with NASA's ΔT) | time max 10 s, place max 0.049° |
| Lunar eclipse kinds 2017–2022, solar kinds (annular 2019 Dec 26, partial 2025 Mar 29) | all match NASA |
| Dallas 2024 Apr 08: total, totality 3 m 40 s – 4 m 05 s, greatest near 18:42:37 UT | pass |
| Warsaw 2026 Aug 12: partial, magnitude 0.86, the Sun sets during the eclipse | pass |
| Centre line 2017 Aug 21 crosses the Oregon coast at ≈44.6° N about 17:16 UT and South Carolina at ≈33° N | within 0.6° and 3 min |

Local contact heights are the Sun's or Moon's refracted altitude; a contact below 0° is
shown dimmed (the body has set). The app lists the next 12 eclipses with "Visible here"
when any contact has the body above the horizon.

## Meteor showers

- Catalogue: the 13 major showers of the IMO Meteor Shower Calendar 2026 (code, activity
  dates, peak solar longitude λ☉ J2000, radiant and daily drift, speed, population index r,
  ZHR). The peak is the time the Sun reaches λ☉, found from AstroCore's Sun position.
- Rate for one observer: `HR = ZHR · sin(h) / r^(6.5 − LM)` with h the radiant height and LM
  the limiting magnitude, 6.5 in a dark sky, brighter in twilight (Sun above −18°) and with
  the Moon up (−2 mag × illumination, scaled by its height). Counted only with the Sun below
  −12°. The sky-brightness terms are a planning heuristic, not an IMO formula. Ratings:
  Excellent ≥ 40/h, Good ≥ 15, Fair ≥ 5.

| Check | Result |
|---|---|
| λ☉ at the 2026 March equinox | 359.634° (J2000), within 0.01° |
| 2026 peak dates (QUA, LYR, ETA, PER, ORI, LEO, GEM) vs the IMO 2026 calendar | all within the IMO night |
| Perseids 2026 from Warsaw: new Moon, radiant > 50° before dawn, > 60/h, Excellent | pass |
| Perseids from Sydney: radiant never rises, Poor | pass |
| Eta Aquariids: better from Sydney than from Warsaw | pass |
| Quadrantids active across New Year; nothing active on 10 March | pass |

## Planner

Panel 8 (Meteors) lists the strongest active shower, its radiant now, the expected rate now
and at the best time of the night, and the other active showers; with none active it names
the next peak. Panel 9 (Eclipses) gives the next eclipse visible from the pin with local
contact times and heights. The map draws the radiant's direction from the pin (teal) and the
centre line of the next total or annular solar eclipse (red), each with its own layer toggle.
