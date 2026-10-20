# Lumora

Lumora (working name) is an iOS photography planning app: Sun, Moon and Milky Way planner,
AR viewers, and exposure/optics calculators. The product spec and phased plan live in
`PHOTOPILLS_REBUILD_BRIEF.md` (project Library); this repo follows it phase by phase.

## Layout

```
App/                    SwiftUI app target (views only format and display)
  Sources/  Resources/  Tests/
Packages/               Local SPM packages, no UIKit/SwiftUI imports
  AstroCore/            Time scales, Sun/Moon ephemeris, rise/set, phases, seasons
  OpticsCore/           Exposure, DoF, FoV, spot stars, star trails, time lapse (Phase 5)
  GeoCore/              Geodesy, elevation, time zones (Phases 3 and 6)
  CameraCatalog/        Camera bodies JSON (Phase 5)
  PlannerKit/           Planner state, formatting, day summaries
Tools/golden/           Scripts that regenerate golden test data
project.yml             XcodeGen spec (the .xcodeproj is generated, not committed)
```

## Build and test

Requirements: Xcode 16+ (Swift 6), iOS 17+ simulator, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Lumora.xcodeproj           # run the "Lumora" scheme; ⌘U runs app + package tests
```

Packages only (macOS or Linux, Swift 6.0+):

```sh
scripts/test-packages.sh        # prints ACCURACY lines for AstroCore
```

## Status

- Phase 0 (skeleton) and Phase 1 (AstroCore) are done. See `docs/PHASE1_ACCURACY.md`.
- Settings: units, clock, coordinate format persist with `@AppStorage`.

## Licences

Astronomy code is ported from [Astronomy Engine](https://github.com/cosinekitty/astronomy)
(MIT, Don Cross). See `THIRD_PARTY_NOTICES.md`. No GPL code.
