# Kaštan Swift Library

[← Project overview](../README.md)

The Swift package exports the `Kastan` library product used by the CLI, macOS app, and MCP server. It requires
Swift 6.3 or newer and declares macOS 12 as its minimum Apple-platform deployment target.

## Package Dependency

Until versioned releases are available, depend on the `main` branch:

```swift
dependencies: [
    .package(url: "https://github.com/Glutexo/kastan.git", branch: "main"),
]
```

Add the library product to a target:

```swift
.target(
    name: "MyTarget",
    dependencies: [
        .product(name: "Kastan", package: "kastan"),
    ]
)
```

For a local checkout, build and test it with Swift Package Manager:

```sh
swift build
swift test
```

## Example

```swift
import Kastan

let client = IDOSClient()
let timetable = try IDOSTimetable.resolve("odis")
let request = IDOSConnectionRequest(
    timetable: timetable,
    from: "Frýdek,Na Veselé",
    to: "Ostrava,Hrabůvka,Benzina",
    isArrival: true,
    onlyDirect: true,
    via: ["Místek,Anenská"],
    maxTransfers: 0,
    minimumTransferTime: 10,
    resultLimit: 8
)

let connections = try await client.findConnections(request: request)
let calendar = try await client.connectionCalendar(for: connections[0], timetable: timetable)
let pdf = try await client.connectionPDF(
    for: connections[0],
    timetable: timetable,
    language: .czech
)
let stations = try await client.searchStations(prefix: "Svinov", timetable: timetable)

let departuresRequest = IDOSDeparturesRequest(
    timetable: timetable,
    station: "Ostrava,Hrabůvka,Benzina",
    time: "16:00"
)
let departures = try await client.findDepartures(request: departuresRequest)
let service = try await client.serviceDetail(id: departures[0].id, language: .czech)
let serviceCalendar = try await client.serviceCalendar(for: service)
let servicePDF = try await client.servicePDF(for: service, language: .czech)

let pid = try IDOSTimetable.resolve("pid")
let lines = try await client.searchStationTimetableLines(prefix: "154", timetable: pid)
let stationTimetable = try await client.findStationTimetable(
    request: IDOSStationTimetableRequest(
        timetable: pid,
        line: lines[0].text,
        from: lines[0].from!,
        to: lines[0].to!,
        date: "17.7.2026",
        wholeWeek: true
    ),
    language: .english
)

let aliasFile = StopAliasFile()
var aliases = try aliasFile.load()
try aliases.upsert(
    StopAlias(
        name: "work",
        station: "Ostrava,Hrabůvka,Benzina",
        timetable: timetable
    )
)
try aliasFile.save(aliases)
```

## Public API

The main public types are:

- Client and errors: `IDOSClient`, `IDOSClienting`, and `IDOSError`.
- Requests and timetables: `IDOSConnectionRequest`, `IDOSDeparturesRequest`, `IDOSStationTimetableRequest`,
  and `IDOSTimetable`.
- Results: `IDOSSuggestion`, `IDOSConnection`, `IDOSConnectionLeg`, `IDOSDeparture`, `IDOSServiceDetail`,
  `IDOSServiceStop`, `IDOSStationTimetable`, `IDOSStationTimetableStop`, `IDOSStationTimetableSchedule`,
  `IDOSStationTimetableHour`, and `IDOSTransportMode`.
- Personal aliases: `StopAlias`, `StopAliasDatabase`, `StopAliasFile`, and `StopAliasError`.

Connection-result, service, and departure identifiers are opaque and must not be parsed by clients. Models
preserve the semantic information received from IDOS, including line colors, transport modes, platforms,
tariff zones, carriers, delay details, and localized service notes when available.

`connectionCalendar` returns IDOS iCalendar text for a search result. `serviceCalendar` and `servicePDF`
resolve a dated service's permanent result link and return the corresponding native IDOS export.
`connectionPDF` and `servicePDF` accept an explicit language for the document text.

`searchStationTimetableLines` returns the terminal pair for every matching MHD line direction.
`searchStationTimetableStops` limits suggestions to one selected line, and `findStationTimetable` returns the
route, departures grouped by service day and hour, tariff zones, platforms or stands, explanatory notes,
lockout state, and matching IDOS URL. Platform or stand numbers are exposed on their corresponding
`IDOSStationTimetableStop` instead of being duplicated in the timetable-wide notes.

## Data Source

The library calls publicly reachable IDOS web endpoints and parses HTML and internal JSONP responses. It is
intended for low-frequency personal use, not as a stable or guaranteed data API.
