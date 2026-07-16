# Kaštan for macOS

[← Project overview](../README.md)

Kaštan includes a native SwiftUI application for macOS 13 or newer. It imports the `Kastan` library directly,
so its IDOS requests and parsed models stay aligned with the CLI and MCP server.

## Features

- Connection searches with place suggestions, date, time, arrival mode, editable via places, and transfer
  limits with locale-aware plural wording and a consistently aligned stepper.
- Station departures and arrivals with station-only suggestions.
- Sidebar navigation divided into Search and Favorites, including a timetable-favorites manager that keeps
  every entry in its catalog group and marks the selected entries with filled stars.
- Timetable menus grouped into general rail and bus choices, integrated transport systems, and city networks,
  with persistent favorites in their own first section and a favorite button kept next to the picker at every
  window width.
- Search forms fixed above independently scrollable result areas, then collapsed into low query summaries after
  submission with an explicit action for returning to the editable form.
- Native tabs and windows, including independent resizable service-route windows.
- Connection cards with line colors, transport symbols, platforms, tariff zones, carriers, and localized delay
  states supplied by IDOS.
- Complete service routes with the search-relevant segment highlighted without implying live vehicle position.
- Permanent connection and service-detail links using the IDOS language that matches the app, available from
  their action menus for opening in IDOS or sharing through the standard macOS share sheet.
- IDOS calendar export opened in the user's calendar application and localized IDOS PDFs saved through the
  native macOS save panel.
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
