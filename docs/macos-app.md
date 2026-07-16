# Kaštan for macOS

[← Project overview](../README.md)

Kaštan includes a native SwiftUI application for macOS 13 or newer. It imports the `Kastan` library directly,
so its IDOS requests and parsed models stay aligned with the CLI and MCP server.

## Features

- Connection searches with place suggestions, date, time, arrival mode, editable via places, and transfer
  limits.
- Station departures and arrivals with station-only suggestions.
- Timetable menus grouped into general rail and bus choices, integrated transport systems, and city networks,
  with persistent favorites in their own section.
- Search forms fixed above independently scrollable result areas.
- Native tabs and windows, including independent resizable service-route windows.
- Connection cards with line colors, transport symbols, platforms, tariff zones, carriers, and localized delay
  states supplied by IDOS.
- Complete service routes with the search-relevant segment highlighted without implying live vehicle position.
- Permanent result links using the IDOS language that matches the app.
- IDOS calendar export opened in the user's calendar application.
- English and Czech interface localization.
- An app-information window describing the data source and linking to IDOS, its terms, and the Kaštan repository.

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
temporary app directory before macOS opens them.

## Data Source

The app uses publicly reachable IDOS web endpoints and parses returned HTML. It is intended for occasional
personal searches and does not present IDOS data as a stable API or live vehicle tracking service.
