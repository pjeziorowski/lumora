# CLAUDE.md

Lumora is an iOS photography planner built phase by phase from `PHOTOPILLS_REBUILD_BRIEF.md`
(project Library). Do not start a phase until the previous one is accepted by the owner.

- Computation lives in `Packages/*` (AstroCore, OpticsCore, GeoCore, CameraCatalog, PlannerKit),
  which never import UIKit or SwiftUI. `App/` only formats and displays.
- Swift 6, iOS 17+. Every file starts with a comment giving its repo path.
- Engine functions ship with tests; each golden value cites its source in a comment.
- Ports from Astronomy Engine (MIT) name the original function. No GPL code.
- Never use the PhotoPills name, assets or copy.

Commands:
- `scripts/test-packages.sh` runs all package tests (macOS or Linux) and prints ACCURACY lines.
- `xcodegen generate` creates `Lumora.xcodeproj` (not committed); scheme `Lumora` runs app + package tests.
- `python3 Tools/golden/generate_golden.py` regenerates golden data (needs `pip install skyfield skyfield-data`).
