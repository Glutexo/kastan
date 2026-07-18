# Kaštan for macOS

[← Project overview](../README.md)

Kaštan includes a native SwiftUI application for macOS 13 or newer. It imports the `Kastan` library directly,
so its IDOS requests and parsed models stay aligned with the CLI and MCP server.

## Features

- Connection searches with place suggestions, date, time, arrival mode, editable via places, and transfer
  limits with locale-aware plural wording and a consistently aligned stepper.
- Station departures and arrivals with station-only suggestions.
- MHD station timetables with line and direction suggestions, single-day or whole-week schedules, selectable
  route stops, tariff zones, platforms or stands, lockout labels, explanatory notes, and links back to the
  matching IDOS result.
- A toolbar control switches directly between Connections, Departures, and Station Timetables while preserving
  each search's state. It stays centered and fully visible at compact widths; secondary actions remain directly
  visible at regular widths and available from the app menus at every width. These actions open the
  timetable-favorites manager and app information in their own windows.
- Timetable menus grouped into general rail and bus choices, integrated transport systems, and city networks,
  with persistent favorites repeated in their own first section without disappearing from the catalog, and a
  favorite button kept next to the picker at every window width.
- Search forms fixed above independently scrollable result areas, then collapsed into low query summaries after
  submission with an explicit action for returning to the editable form. The main window remains usable down to
  a compact 560-point width by stacking controls where needed.
- Connection and station-board results extend chronologically without replacement: pulling past the top loads
  earlier results, while pulling past the bottom loads the following results and removes duplicate rows.
- Native tabs and windows, including independent favorite-timetable and resizable service-route windows.
- Connection cards with line colors, transport symbols, platforms, tariff zones, carriers, and localized delay
  states supplied by IDOS.
- Complete service routes with the search-relevant segment highlighted without implying live vehicle position.
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
