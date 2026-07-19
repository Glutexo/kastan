# Kaštan for macOS

[← Project overview](../README.md)

Kaštan includes a native SwiftUI application for macOS 13 or newer. It imports the `Kastan` library directly,
so its IDOS requests and parsed models stay aligned with the CLI and MCP server.

## Features

- Connection searches with full-row selectable place suggestions whose icons distinguish municipalities from
  stations and stops. Suggestion metadata, including foreign country names, follows the app language.
  Choosing a suggestion also preserves its exact IDOS identity, so a station is not broadened to a same-named
  municipality. The selected field marks that identity with a subdued localized type such as municipality,
  train, or bus; editing the field removes the marker and returns it to a free-text search. Searches also support
  date, time, arrival mode, and an extensible journey-options builder modeled after native macOS rule editors.
  Each condition first selects either Via or Maximum number of transfers, then presents the corresponding text
  or compact, left-aligned number field with native stepper arrows. Both editors share one row height and follow the
  naturally sized condition menu at standard control spacing; fixed-size controls add and remove rows while summaries
  retain locale-aware transfer wording.
- Station departures and arrivals with station-only suggestions that retain the selected station or stop identity.
- MHD station timetables with line and direction suggestions, single-day or whole-week schedules, selectable
  route stops, tariff zones, platforms or stands, lockout labels, explanatory notes, and links back to the
  matching IDOS result. Dated service notes such as a connection that runs or does not run on listed dates, or
  runs through a named date such as `3.XII.`, open an operating calendar. Working-day rules compose with dated
  exceptions and exclude weekends and Czech public holidays, while numbered weekday rules such as `v 6,7`
  restrict a dated operating range to Saturdays and Sundays. The calendar marks running and non-running days only
  within the validity interval printed by IDOS for the current timetable; days outside that interval remain visibly
  out of scope. Phone numbers in timetable notes, service information, and route-stop notes open as `tel:` links.
- A genuine AppKit toolbar centers a complete mode control for switching between Connections, Departures, and
  Station Timetables while preserving each search's state. Stable toolbar identifiers and visibility priorities
  keep that control intact, and its natural width follows the localized labels without stretching the final
  segment. macOS moves secondary actions into its native overflow menu when a compact window cannot show them
  directly. The same actions remain available from the app menus. These actions open the
  timetable-favorites manager and app information in their own windows, with concise labels that name their
  content.
- Timetable menus grouped into general rail and bus choices, integrated transport systems, and city networks,
  with persistent favorites repeated in their own first section without disappearing from the catalog, and a
  favorite button whose small visible gap adapts to the compact and wide search layouts.
- Search forms fixed above independently scrollable result areas, then collapsed into low query summaries after
  submission with an explicit action for returning to the editable form. The main window remains usable down to
  a compact 522-point width without moving the connection or station-board time mode below the date and time
  controls.
- Connection and station-board results extend chronologically without replacement: pulling past the top loads
  earlier results, while pulling past the bottom loads the following results and removes duplicate rows.
- Native tabs and windows, including independent favorite-timetable, complete-connection, and resizable
  service-route windows. A connection opened in its own window presents its export and sharing actions as
  individually visible controls in the native toolbar instead of repeating the result-card action menu, and
  each of its services can still open a separate complete route. When scrolling hides the connection's main
  time range, that range moves into the window title until its content label is visible again.
- Connection cards with line colors, transport symbols, platforms, tariff zones, carriers, and localized delay
  and expected-punctuality states supplied by IDOS.
- Complete service routes open at the departure stop from the originating search, with the search-relevant
  segment highlighted without implying live vehicle position. When scrolling hides a service date, the date
  moves into the window title until its content label is visible again.
- Selectable service-information text that supports the standard macOS copy command while retaining clickable
  phone-number links. Dated operating exceptions, including abbreviated ranges such as `17. to 20.VIII.` and
  same-month lists such as `18.,19.IX.`, open the same running/non-running calendar using the exact validity
  interval published by the current IDOS timetable. When opened, the calendar scrolls to the current month or
  to the nearest month covered by that timetable. Option-clicking a calendar note also lists the operating rule
  and every individual date or range recognized from it.
- Permanent connection and service-detail links using the IDOS language that matches the app, available for
  opening in IDOS or sharing through the standard macOS share sheet. Every service-detail action is an
  individually visible control in that window's native toolbar.
- IDOS calendar and localized PDF exports for connection results and dated service details, opened in the
  user's calendar application or saved through the native macOS save panel.
- English and Czech interface localization.
- An app-information window describing the data source and linking to IDOS, its terms, and the Kaštan repository.
- A Help menu that repeats the About window's maintained links to IDOS, its terms, and the Kaštan repository
  instead of showing an unavailable system help book.

## Run from Xcode

The project requires Xcode with Swift 6.3 or newer. Open the shared project and run the `KastanApp` scheme:

```sh
open KastanApp/KastanApp.xcodeproj
```

## Build and Test from Terminal

```sh
xcodebuild build \
  -project KastanApp/KastanApp.xcodeproj \
  -scheme KastanApp \
  -destination 'platform=macOS'

xcodebuild test \
  -project KastanApp/KastanApp.xcodeproj \
  -scheme KastanApp \
  -destination 'platform=macOS'
```

The app target is sandboxed and permits outgoing network connections for IDOS. Calendar files are written to a
temporary app directory before macOS opens them; PDF exports can be written only to a location explicitly
selected by the user.

## Data Source

The app uses publicly reachable IDOS web endpoints and parses returned HTML. It is intended for occasional
personal searches and does not present IDOS data as a stable API or live vehicle tracking service.
