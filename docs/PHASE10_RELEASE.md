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
- Screenshots at accessibility text sizes check that the Tools list, the Sun tool and the
  Planner still read (`testAccessibilityLargeText`, files `a11y-NN-…`, at AX5 and AX3). The
  Planner's time ruler grows with the text size and labels every second or third hour when
  the labels no longer fit an hour apart.

### Large text in the Planner

The nine panel buttons used to sit in a fixed row. At accessibility sizes the row needed
more than the screen width, which made the whole Planner wider than the phone and cut off the
panel rows, the date line and the jump buttons at both edges. Now:

- Each panel button is at least 44 × 44 pt. The buttons share the width when they fit and
  scroll sideways when they don't, and the selected one stays in view. Their icons stop
  growing at AX1, and a long press shows the large content viewer, as in a tab bar.
- At accessibility sizes, panel rows put the label above the value, the panel area is
  280 pt tall (236 pt otherwise), and the date line is shortened to "Jun 21 · UTC+2". The
  time bar stops growing at AX3, so the map keeps some room at AX5. The audit reports its
  labels as "Dynamic Type partially unsupported" for that reason. Without the cap, the map
  has no room left at AX5.
- Rows in the Sun, Moon and other tools (`ValueRow`) stack the same way at accessibility
  sizes.

### Audit triage

`testPhase10AccessibilityAudit` writes every issue, a screenshot (`audit-NN-…`) and the
element tree (`audit-element-trees.txt`) for each screen. Contrast and hit-area issues on
the app's own elements fail the test. Before this pass the audit reported about 140 issues,
and the Planner's audit timed out. Its "0 issues" was that timeout. The test now audits one
type at a time when the full audit runs out of time. After this pass about 80 remain:

| Issue | Fixed | Remaining, and why |
|---|---|---|
| Contrast | Secondary text, section headers and footers, list values and Settings choices use `Color.subdued` (6.0:1 light, 7.7:1 dark, darker with Increase Contrast; `App/Sources/Accessibility/Palette.swift`). The light-mode accent orange is darker (5.2:1 on grouped backgrounds). Status text uses accessible green, orange and red, and the meteor rating badges are white on dark fills. | Text the audit samples while it scrolls under the translucent tab bar (every remaining named element sits below the tab bar's top edge). The two unnamed issues per scrolling screen follow the same pattern: none on the Planner or My Stuff, where nothing scrolls under the bar. |
| Contrast (map badges) | The Planner's map badges ("Golden hour", "Device time") sit on a nearly opaque capsule instead of a material that let bright map tiles show through. | — |
| Hit area too small | Planner panel buttons are now 44 × 44 pt (checked in `testAccessibilityLargeText`). | MapKit's Legal link, which MapKit draws and the app cannot resize. |
| Dynamic Type unsupported | Meteor badges and the hour and eclipse-altitude columns scale. Plan thumbnails (map pictures) are hidden from accessibility. | UIKit controls that use the large content viewer instead of growing: tab bar items, segmented controls, navigation bar buttons and the compact date picker. The audit names no element for these, and the counts match the controls on each screen (Sun: 4 tabs, 5 segments, back button, 2 date picker buttons). |
| Text clipped | Settings pickers are inline rows (the menu style clipped "Decimal degrees"). The meteor badge has no fixed frame. | Unnamed issues on the same UIKit controls and large navigation titles, plus the combined meteor rows, whose merged VoiceOver label is longer than any one line. |

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

1. In Xcode, set the team for the Lumora and LumoraWidgets targets; let Xcode register the
   app group `group.com.pjeziorowski.lumora` for both bundle ids.
2. `xcodegen generate`, open `Lumora.xcodeproj`, choose Any iOS Device, Product > Archive.
3. In the Organizer, Distribute App > App Store Connect > Upload, then add the build to a
   TestFlight group.

## Not done (stretch goals in the brief)

Drone mode, 3D terrain AR, the panorama helper and offline maps.
