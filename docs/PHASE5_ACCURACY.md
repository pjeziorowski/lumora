# Phase 5 acceptance: photography calculators

Measured with `scripts/test-packages.sh` (Swift 6.1.3, Linux x86-64). OpticsCore: 20 tests,
CameraCatalog: 5 tests. Tests: `Packages/OpticsCore/Tests/OpticsCoreTests/OpticsCoreTests.swift`,
`Packages/CameraCatalog/Tests/CameraCatalogTests/CameraCatalogTests.swift`; screenshots from
`App/UITests/ScreenshotTests.swift` (`testPhase5Optics`). All arithmetic lives in OpticsCore;
the app screens only lay results out.

## Against published values

| Calculator | Case | Published | Lumora | Source |
|---|---|---|---|---|
| Hyperfocal | 50 mm f/8, c 0.03 mm | 10 417 mm (f²/Nc) | 10 467 mm (f²/Nc + f), 0.5% | Wikipedia "Hyperfocal distance" |
| Hyperfocal | 24 mm f/8, c 0.025 mm | 2.88 m, near limit 1.44 m | 2.904 m, 1.452 m (within 1%) | Bob Atkins, "Depth of field" |
| Depth of field | 50 mm f/11 at 3 m, c 0.025 mm | ~0.7 m in front, ~1.4 m behind | 0.735 m / 1.441 m | Bob Atkins |
| Airy disc | f/2, f/22, f/32 (550 nm) | 2.7, 30, 43 µm | 2.68, 29.5, 42.9 µm | Bob Atkins |
| Print CoC | 8× enlargement, 25 cm, 5 lp/mm | 0.025 mm | 0.025 mm | Bob Atkins |
| NPF | D750 (5.97 µm), 24 mm f/2.8 | 11.54 s | 11.55 s | Light Stalking, "NPF rule" |
| 500 rule | 24 mm full frame | ≈ 21 s | 20.8 s | Light Stalking |
| Field of view | 50 mm on 36 × 24 mm | 39.6° × 27.0°, diag 46.8° | 39.60° × 26.99°, 46.79° | standard lens tables |
| Field of view | 24 mm diagonal | 84.1° | 84.06° | standard lens tables |
| Exposure value | f/1 1 s; f/16 1/125 | EV 0; ≈ EV 15 | EV 0; EV 15.0 | ISO 2720 EV table |
| ND filters | 1/30 s + 10 stops | 34 s | 34.1 s | factor 2^10 = 1024 |
| Star trails | full circle | 86 164 s (sidereal day) | 86 164 s | sidereal rate 15.041″/s |
| Camera specs | D750, α7R IV, X-T5 pixel pitch | 5.97, 3.76, 3.04 µm | same | manufacturers' specifications |

## Formulas

- Depth of field: Greenleaf thin-lens formulas as in DOFMaster. H = f²/(N·c) + f;
  near = s(H − f)/(H + s − 2f); far = s(H − f)/(H − s), infinite once s ≥ H. Calculators that
  drop the "+ f" term agree within 1% at normal distances (tested).
- Default circle of confusion = sensor diagonal / 1500 (0.0288 mm full frame); cameras can
  override it, and Advanced mode derives it from print size, viewing distance and acuity.
- Diffraction: Airy disc 2.44·λ·N with λ = 550 nm; the lens is flagged as diffraction-limited
  when the disc exceeds two pixel pitches.
- Spot stars: NPF (35·N + 30·p)/(f·cos δ) and the accurate form
  (16.856·N + 0.0997·f + 13.713·p)/(f·cos δ); |δ| is capped at 89° so the pole stays finite.
- Time lapse: photos = ⌊duration ÷ interval⌋ + 1; any one of duration, interval, frame rate
  and clip length is solved from the other three.

## Camera catalogue

151 bodies (95 mirrorless, 36 DSLR, 9 compact, 6 phone main cameras, 3 drones, 2
rangefinders; full frame to medium format and 1-inch) generated from manufacturers'
specifications by `Tools/cameras/build_catalog.py`. Every entry is valid, has a unique id,
a pixel pitch between 0.5 and 10 µm, and an image aspect within 3% of its sensor's. Users can
add, edit and delete custom cameras, mark favourites and pick the default camera; search
ignores case, accents and "α"/"a".

## Edge cases

- Distance at or beyond the hyperfocal: far limit is infinity, total is infinity.
- Pole declination (±90°) does not divide by zero; equator gives the shortest time.
- Time-lapse interval shorter than exposure plus write time, clips under 2 s and runs
  longer than one battery are warned about.
