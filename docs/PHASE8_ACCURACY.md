# Phase 8 acceptance: augmented reality

Measured with `scripts/test-packages.sh` (Swift 6.1.3, Linux x86-64). PlannerKit: 78 tests
pass. Tests: `Packages/PlannerKit/Tests/PlannerKitTests/ARTests.swift`; screenshots from
`App/UITests/ScreenshotTests.swift` (`testPhase8AR`).

## How the overlay is placed

- Attitude: Core Motion device motion in the `.xTrueNorthZVertical` frame (magnetic north
  when true north is unavailable, shown on screen). The rotation matrix rows are the device
  axes in the reference frame (north, west, up), the convention of Apple's pARk sample; the
  back camera looks along −z. `ARAttitude.fromCoreMotion` converts to east-north-up.
- Projection: pinhole (rectilinear) with the focal length in screen points taken from the
  camera's `videoFieldOfView` and the preview's aspect-fill crop (`ARLens.focalPoints`). Screen
  axes follow the interface orientation, so the horizon stays level in landscape.
- Sky positions come from AstroCore (Sun, Moon, galactic centre and plane, Polaris) with
  standard refraction; declination circles (celestial equator, star-trail circles) are
  computed from the latitude and refracted the same way. Depth-of-field lines lie on flat
  ground `atan(eye height / distance)` below the horizon.

## Tests

| Check | Result |
|---|---|
| Attitude → view azimuth, elevation, roll (5 orientations incl. 88° up, 359.5°, roll ±90°) | exact (< 1e-9°) |
| Core Motion convention: flat face up looks at the nadir; upright facing north / east | exact |
| Centre of view projects to the screen centre; half the field of view to the edge | exact |
| Screen point → direction → screen point | < 1e-9 pt |
| Landscape-left with the phone turned 90°: horizon level, up is up | exact |
| Compass +5°, horizon +2° move the view by exactly that | exact |
| 69.4° 4:3 camera in a 393 × 852 portrait preview: long side 69.4°, short side 35.4° | < 0.1° |
| Celestial equator rises at 90° and sets at 270°; pole at the latitude; Polaris 0.6–0.8° from it | pass |
| Southern sky: south pole, no Polaris; midnight sun at 78°N: path never below the horizon | pass |
| Sun marker equals AstroCore's position | exact |

## Lens frame

The frame mode draws the selected camera and focal length as the rectangle
`ARProjector.lensFrame` returns (2·focal·tan(angle/2) per side, centred). The sensor is
taken in the orientation the phone is held, so a landscape screen shows a landscape frame
(`lensFrameFollowsOrientation`: 50 mm full frame at a 491 pt focal is 235.8 × 353.5 pt
upright and the same swapped sideways).

## The ~2° outdoor criterion

Phone compasses are typically off by several degrees and the horizon by about a degree, so
the criterion is met through calibration rather than raw sensors. `calibrationShiftsAndAligns`
simulates a compass reading 7° east and a horizon 1.5° high: after centring the Sun and
tapping "Align on Sun", the Sun lands on the screen centre within 1e-6 pt and the Moon,
elsewhere in the frame, within 0.01° of its true direction. Remaining error outdoors is the
sensor drift after calibration plus how well the Sun is centred by hand (the centre circle
is 22 pt, about 1° wide in portrait), which keeps the overlay within ~2°.

Not yet done: an outdoor check on a real iPhone (the simulator has neither camera nor motion
sensors). Without sensors the view shows a drawn sky that can be dragged to look around,
which is what the screenshots use (`-arView <azimuth>,<elevation>,<roll>`).
