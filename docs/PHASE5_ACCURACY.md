# Phase 5 acceptance: photography calculators

Measured with `scripts/test-packages.sh` (Swift 6.1.3, Linux x86-64). OpticsCore: 26 tests,
CameraCatalog: 5 tests. Tests: `Packages/OpticsCore/Tests/OpticsCoreTests/OpticsCoreTests.swift`,
`Packages/CameraCatalog/Tests/CameraCatalogTests/CameraCatalogTests.swift`; screenshots from
`App/UITests/ScreenshotTests.swift` (`testPhase5Optics`). All arithmetic lives in OpticsCore;
the app screens only lay results out.

## Against published values

Each calculator family is checked against at least two independent public sources
(retrieved 2026-10-20). Details and exact inputs are in the test file header.

| Calculator | Source 1 | Source 2 | Matrix | Worst agreement |
|---|---|---|---|---|
| Depth of field | Bob Atkins, "Depth of field" (24 mm f/8 hyperfocal 2.88 m; 50 mm f/11 at 3 m; behind/front ratios at 1:10 and 1:50 for 50 and 200 mm at f/5.6 and f/16) | ZEISS Milvus 1.4/50 datasheet DoF table (c 0.033 mm) | 5 distances (0.5–5 m) × 4 f-numbers (1.4–16) from ZEISS, 8 cases from Bob Atkins | near 0.7%; far 1% of focus distance in reciprocal terms (5 m f/16, close to the hyperfocal) |
| Hyperfocal | Wikipedia, "Hyperfocal distance" (50 mm f/8: 10 417 mm) | Bob Atkins (24 mm f/8: 2.88 m, near 1.44 m) | 2 cases + Greenleaf identities at 3 lenses | 0.5% (the "+ f" term) |
| Field of view | Canon EF 50mm f/1.8 STM and EF 85mm f/1.8 USM specifications (H, V, diagonal) | Nikon AF-S 85mm f/1.8G and ZEISS Milvus 1.4/50 specifications; standard 50/24 mm angles | 4 lenses × 3 angles | 1.0° (makers round to whole degrees) |
| Exposure value | ISO 2720 / sunny-16 (f/1 1 s = 0; f/16 1/125 ≈ 15) | Wikipedia "Exposure value", Table 1 | 7 aperture/shutter pairs + ISO offset | 0.17 EV (marked f-numbers are rounded) |
| NPF | Light Stalking, "NPF rule" (D750, 24 mm f/2.8: 11.54 s) | Fstoppers, NPF article (5D Mark IV and α7R IV, 16 mm f/2.8: 16.2 s, 13.1 s) | 3 bodies | 0.06 s (the article truncates) |
| NPF accurate | Light Stalking: the accurate mode comes out at about half the simple rule (11.02 → 5.51 s) | — (no second published value found; formula: F. Michaud's full NPF rule, Société Astronomique du Havre) | 1 case | ratio 0.47 vs 0.5 |
| 500 rule | Light Stalking (24 mm ≈ 21 s) | astrophotography.utils.com formula t = 500/(f × crop) | 2 | exact |
| ND filters | factor 2^stops (1/30 s + 10 stops = 34 s) | brand factors and optical densities (ND1000 = 3.0) | 22 filters | 0.01 stop |
| Star trails | sidereal day 86 164 s (IERS) | star-trail.utils.com: 15°/h rotation | full circle, 30 s | 2 s per day |
| Diffraction / print CoC | Bob Atkins (Airy 2.7/30/43 µm; 0.025 mm at 8×) | brief §3.2 formula 2.44·λ·N | 3 apertures | 0.5 µm |

Time lapse has no published calculator to compare with; it is plain arithmetic (photos,
clip length, frame rate, interval and memory) and each of the four unknowns is solved back
from the other three in the tests.

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
- Focus at or inside the focal length is clamped to 1 mm beyond it, so near and far stay
  positive; the distance fields accept 1 cm (macro) upward.
- Lens barrels engrave distance from the image plane; `objectDistance(fromImagePlane:)`
  converts for comparison with maker tables.
- Pole declination (±90°) does not divide by zero; equator gives the shortest time.
- Time-lapse interval shorter than exposure plus write time, clips under 2 s and runs
  longer than one battery are warned about.
