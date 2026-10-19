# Phase 7 acceptance: plans and My Stuff

Measured with `scripts/test-packages.sh` (Swift 6.1.3, Linux x86-64). PlannerKit: 69 tests
pass. Tests: `Packages/PlannerKit/Tests/PlannerKitTests/PlanTests.swift`; screenshots from
`App/UITests/ScreenshotTests.swift` (`testPhase7Plans`).

## What a plan holds

`Plan` (PlannerKit) stores the place (name, coordinates, elevation, time zone), the moment,
the target pin with its ground elevation and object height, eye height, map field/depth of
field settings, the camera, map layers and style, the open panel, and the user's name, notes
and reminder. `PlannerState.plan(named:)` captures it and `PlannerState.apply(_:)` restores
it, recentring the map.

The app keeps each plan in SwiftData (`PlanRecord`) as a few sortable columns plus the whole
`Plan` as JSON, so the stored form and the exchange form are the same value.

## Export and import

- File: JSON, `{"format": "lumora.plans", "version": 1, "plans": [...], "places": [...]}`,
  keys sorted, dates as seconds since 2001-01-01 (exact `Double`, no rounding).
- Round trip: export → import → export is byte-identical, and every decoded plan equals the
  original (`roundTripsUnchanged`: a southern-hemisphere place on the antimeridian with a
  target across it, sub-second instants, a Polish and emoji name, quotes and newlines in the
  notes, map optics and a reminder, next to a plan with every optional field empty).
- Files that are not plan files, or come from a newer version, are refused with a message
  (`rejectsOtherFiles`); importing a plan whose id already exists replaces it instead of
  duplicating it.
- Capture and restore through `PlannerState` give back the same place, moment, target, optics,
  layers, style and panel (`stateCapturesAndRestores`).

## Sharing, reminders, calendar

- Share as text: name, place and coordinates, local date and time with the time zone, the
  target's distance and bearing when there is one, and notes.
- Share map image: the plan's thumbnail (an `MKMapSnapshotter` image with the pin and the
  line to the target).
- Reminder: a local notification at `instant − minutes`, replaced when the plan is saved
  again and removed when the plan is deleted. No reminder is scheduled for a time already
  past.
- Calendar: a one-hour event in the plan's time zone, with write-only access (iOS 17).
  Refused permissions are reported in the save sheet instead of failing silently.

## My Stuff

Plans (thumbnail, date and time in the plan's own time zone, reminder and target badges;
tap to open in the Planner, swipe to duplicate or delete, context menu to share or export;
import and export all from the toolbar), saved places (tap to move the Planner there), and
the camera list, whose default camera is also reachable from Settings.
