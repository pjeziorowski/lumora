# Phase 10: widgets, polish, release

PlannerKit: 98 tests pass (`scripts/test-packages.sh`, Swift 6.1.3, Linux x86-64), including
`Packages/PlannerKit/Tests/PlannerKitTests/WidgetTests.swift`. Screenshots and the
accessibility audit come from `App/UITests/ScreenshotTests.swift` (`testPhase10WidgetsAndPolish`,
`testPhase10AccessibilityAudit`).

## Widgets

Extension target `LumoraWidgets` (WidgetKit), four widgets, each in five families: Home Screen
small and medium, Lock Screen circular, rectangular and inline.

| Widget | Shows |
|---|---|
| Sun | Light phase now (day, golden hour, blue hour, twilight, night), Sun height and direction, the next sunrise, sunset, golden-hour start or end and blue-hour start or end |
| Moon | Phase drawn for the hemisphere, illumination, next moonrise or moonset, next full Moon |
| Milky Way | Tonight's window with the core up and the Moon down or dim, the best moment and the core's direction; if tonight has none, the next night within three weeks |
| Next plan | The next saved plan: name, place, local date and time, expected light, Sun position, countdown |

- The numbers come from `PlannerKit/Widgets/WidgetSnapshots.swift`, built on the same reports
  as the Sun, Moon and Milky Way tools, so a widget never disagrees with the app (checked in
  `WidgetTests`: the Sun widget's next sunset equals the Sun tool's sunset to the second).
- Times are in the place's time zone. Timelines last 6 hours, with an entry every 30 minutes
  (every 5 minutes for the Next plan countdown, which shows whole minutes) and one just after
  each event a widget names, so a passed sunset or plan never lingers
  (`PlannerKit/Widgets/WidgetTimeline.swift`, tested in `WidgetTests`). The Milky Way window
  is computed again once the shown one has ended.
- The app shares the selected place, clock style and upcoming plans through the app group
  `group.com.pjeziorowski.lumora` (`WidgetStore`). The group needs a signing team; unsigned
  simulator builds fall back to "Open Lumora to choose a place."
- Settings > Widgets shows every widget at its real size for the selected place and moment.
  The screenshots come from that gallery, since UI tests cannot place widgets on the
  simulator's Home Screen.

## Onboarding

Four pages on first launch: what the app does, the place to plan for (with "Use my
location"), units and clock, and plans and widgets. It is shown once (`onboarding.completed`).

## Accessibility

- `testPhase10AccessibilityAudit` runs Xcode's accessibility audit (all audit types: contrast,
  element detection, hit regions, element descriptions, Dynamic Type, clipped text, traits) on
  the Planner, Tools, Sun, Meteor showers, My Stuff and Settings. It writes the issues to
  `p10-accessibility-audit.txt` instead of failing, so they can be worked through.
- Charts have accessibility labels; the Moon disc and eclipse glyphs are decorative and
  hidden, with the row they sit in carrying the label; rows combine label and value.
- Screenshots at the largest accessibility text size check that the Tools list, the Sun tool
  and the Planner still read. The Planner's time ruler grows with the text size and labels
  every second or third hour when the labels no longer fit an hour apart.

### Audit triage

The audit at the default text size reports about 140 issues on six screens. What they are and
what was decided:

| Issue | Where | Decision |
|---|---|---|
| Contrast failed or nearly passed | Secondary labels (coordinates, list values, section headers) in system lists | Accepted: these use the system `.secondary` style on grouped backgrounds, which follows Increase Contrast. Revisit if a custom palette is introduced. |
| Dynamic Type partially unsupported | List cells in Sun, Meteor showers, My Stuff, Settings | Accepted: the cells use text styles and scale (see the accessibility-size screenshots); the audit flags fixed-size SF Symbols and chart axes inside them. |
| Text clipped | Long dates in the Planner header and Sun tool, Settings pickers | Accepted at the default size, where the text truncates with an ellipsis and VoiceOver reads it whole; at accessibility sizes the header stacks instead. |
| Hit area too small | The nine Planner panel tabs (about 37 × 44 pt on a 6.1-inch iPhone); the map's Legal link | Accepted: the panels also page by swipe and each tab is a labelled VoiceOver button; the Legal link is drawn by MapKit. A scrolling tab bar would fix it at the cost of hiding tabs. |

## Localization

`App/Resources/Localizable.xcstrings` is the string catalog (source English) with a Polish
translation of the tabs, Tools list, Settings, onboarding, widgets and event screens. The catalog
is compiled into both the app and the widget extension. SwiftUI
literals are catalog keys, so Xcode adds new strings to the catalog when the project is built
in Xcode. Planner panel rows and pill values are built in PlannerKit as English strings and are
not localized yet.

## Privacy

- `App/Resources/PrivacyInfo.xcprivacy` and `App/Widgets/PrivacyInfo.xcprivacy`: no tracking,
  no tracking domains, no collected data. The only required-reason API is UserDefaults
  (CA92.1 for the app's own settings, 1C8F.1 for the app group shared with the widgets).
- App Store privacy label: Data Not Collected. Location is used on the device to compute
  times and is never sent anywhere; place search and elevation lookups send only the searched
  text or coordinates to Apple's geocoder and to Open-Meteo's elevation API, with no identifier.
- Usage strings: location (when in use), camera (AR), calendar (write-only, plans).

## App Store assets

- App icon: `App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` (single-size
  1024 px, no transparency), a sun on the horizon with its path and a crescent Moon.
- Store screenshots: the simulator screenshots of each phase cover every feature; pick from
  `/mnt/project-files/lumora/screenshots/` (6.9-inch iPhone captures).
- Suggested listing: name "Lumora", subtitle "Sun, Moon & Milky Way planner", category
  Photography, keywords "golden hour, blue hour, milky way, moon phase, sunset, planner,
  astrophotography, depth of field, eclipse, meteor".

## Release (needs the owner's Apple Developer account)

TestFlight uploads run from `.github/workflows/testflight.yml` once the owner has done the
one-time setup in `docs/TESTFLIGHT.md` (Team ID, identifiers, distribution certificate, app
record, API key, repository secrets). The same guide covers uploading from Xcode instead.

## Not done (stretch goals in the brief)

Drone mode, 3D terrain AR, the panorama helper and offline maps.
