# Kaštan Swift Library

[← Documentation](README.md)

The Swift package exports the `Kastan` library product used by the CLI, macOS app, and MCP server. It requires
Swift 6.3 or newer and declares macOS 12 as its minimum Apple-platform deployment target.

## Package Dependency

Depend on the latest compatible `0.5.x` release:

```swift
dependencies: [
    .package(
        url: "https://github.com/Glutexo/kastan.git",
        .upToNextMinor(from: "0.5.0")
    ),
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
let calendar = try await client.connectionCalendar(
    for: connections[0],
    timetable: timetable,
    language: .czech
)
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
let serviceInformation = service.serviceInformation
let firstInformationCategory = serviceInformation.first?.category
let firstInformationText = serviceInformation.first?.displayText
let validity = try await client.timetableValidity(for: service.timetable, language: .czech)
let operatingDays = try await client.serviceDateLimits(for: service, language: .czech)
let selectedDayStatus = operatingDays.status(on: operatingDays.referenceDate)
let serviceCalendar = try await client.serviceCalendar(for: service, language: .czech)
let servicePDF = try await client.servicePDF(for: service, language: .czech)

let municipality = try IDOSStationTimetableMunicipality.resolve(
    "Frýdek-Místek",
    timetable: timetable
)
let lines = try await client.searchStationTimetableLines(
    prefix: "301",
    timetable: timetable,
    municipality: municipality
)
let stationTimetable = try await client.findStationTimetable(
    request: IDOSStationTimetableRequest(
        timetable: timetable,
        municipality: municipality,
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
  `IDOSStationTimetableMunicipality`, `IDOSPlaceSelection`, `IDOSTimetable`, and `IDOSTimetableValidity`.
- Results: `IDOSSuggestion`, `IDOSConnection`, `IDOSConnectionEmailDraft`, `IDOSConnectionLeg`, `IDOSDeparture`, `IDOSServiceDetail`,
  `IDOSServiceInformation`, `IDOSServiceStop`, `IDOSStationTimetable`, `IDOSStationTimetableStop`,
  `IDOSStationTimetableSchedule`, `IDOSStationTimetableHour`, and `IDOSTransportMode`.
- Personal aliases: `StopAlias`, `StopAliasDatabase`, `StopAliasFile`, and `StopAliasError`.

`IDOSTimetable.known` mirrors the current IDOS catalog, including all ten integrated systems and all 106 standalone
Urban Public Transport cities. Prague is represented by its `pid` catalog instead of a duplicate standalone city.
`IDOSTimetable.resolve(_:)` accepts each built-in display name or URL slug and continues to accept a valid custom
IDOS slug.

Connection-result, service, and departure identifiers are opaque and must not be parsed by clients. Models
preserve the semantic information received from IDOS, including line colors, transport modes, platforms,
tariff zones, carriers, delay details, and localized service notes when available. `IDOSConnectionLeg` and
`IDOSDeparture` expose the facilities and restrictions printed beside a result through their ordered
`serviceInformation` arrays. Each item keeps the complete IDOS tooltip text together with its classified category
and semantic symbol. Its computed `classificationRule` exposes the concrete ordered phrase, regular-expression, or
structural predicates that matched, while `.fallback` records that no specific text rule selected the retained
fallback meaning. Because the rule is recomputed from the source text rather than encoded, stored results remain
compatible; an absent service-information field in older encoded results decodes as an empty array. Encoded
connection-leg platform values retain IDOS's compact source notation, while `summaryLine` expands railway pairs such
as `2/3` to the unambiguous human-readable `platform 2 track 3`.

The language-aware `findConnectionsPage(request:language:)` and
`findDeparturesPage(request:language:)` overloads request platform-supplied result text in English or Czech and
retain that language while loading adjacent pages. The overloads without a language keep their historical English
default, and custom `IDOSClienting` implementations remain compatible through the default protocol adapters.

`IDOSServiceDetail.information` preserves every original IDOS information line for stable decoding and display.
Its `serviceInformation` view adds an `IDOSServiceInformation.Category` and the same semantic symbol used by
Kaštan's human-readable interfaces without replacing that text. Categories distinguish passenger-facing meanings
such as replacement transport, accommodation, seating-class availability, onboard services, accessibility,
tickets and reservations, operating calendars, restrictions, routes including skipped-stop instructions, and
carriers; unrecognized text remains in the `general` category.

Create an `IDOSPlaceSelection` from a chosen `IDOSSuggestion` and pass it as `fromSelection`, `toSelection`,
`stationSelection`, or the corresponding element of `viaSelections` when the query must target that exact IDOS
object. This distinguishes, for example, a railway station from a municipality with the same visible name.
`viaSelections` follows the order of `via`; use `nil` for any element that should retain free-text interpretation.
Leave endpoint or station selections unset for the same free-text interpretation as typing into the IDOS form
without choosing a suggestion.

For a connection endpoint obtained from a device's WGS-84 coordinates, use
`IDOSPlaceSelection.currentLocation(text:latitude:longitude:)` and pass the returned value together with its `text`
as `fromSelection` or `toSelection`. The caller supplies the localized visible text, such as `My location`; Kaštan
formats the coordinate identity expected by IDOS.

`connectionCalendar` returns IDOS iCalendar text for a search result. `serviceCalendar` and `servicePDF`
resolve a dated service's permanent result link and return the corresponding native IDOS export. Calendar and PDF
exports accept an explicit language for their human-readable text; calendar calls without one retain the historical
English default for source compatibility.
`timetableValidity` returns the inclusive first and last dates published by the selected IDOS timetable.
`serviceDateLimits` returns the exact `runs`, `doesNotRun`, or `informationUnavailable` state that IDOS publishes
for every civil day in its native service date-restriction calendar. Its `referenceDate` anchors the first returned
month, while `firstDate`, `lastDate`, and `status(on:)` let a client present only the interval actually supplied by
IDOS instead of interpreting operating rules from prose. The call throws `IDOSError.dateLimitsUnavailable` when
IDOS does not expose a usable native calendar for that service.

`connectionEmailDraft` loads IDOS's localized default message and the PDF and calendar attachment names for one
connection result. After an application has collected one or more recipient addresses and received explicit user
confirmation, `sendConnectionByEmail` asks IDOS to generate and deliver those attachments:

```swift
let draft = try await client.connectionEmailDraft(
    for: connections[0],
    timetable: timetable,
    language: .czech
)

// Call only after the user confirms both the recipients and editable message.
try await client.sendConnectionByEmail(
    connections[0],
    to: "passenger@example.com",
    message: draft.message,
    timetable: timetable,
    language: .czech
)
```

The recipient string may contain comma- or semicolon-separated addresses accepted by IDOS. The library sends that
string and the message directly to IDOS and does not persist either value. Email preparation requires the opaque
sharing data carried by a connection returned from an IDOS search; clients that construct or decode a connection
without that transient data receive `IDOSError.emailUnavailable`.

`searchStationTimetableLines` returns the terminal pair for every matching MHD line direction.
`searchStationTimetableStops` limits suggestions to one selected line, and `findStationTimetable` returns the
route, departures grouped by service day and hour, tariff zones, platforms or stands, keyed departure
`explanations`, general `notes`, lockout state, and matching IDOS URL. An explanation is separated only when its
key occurs beside a concrete departure. Platform or stand numbers are exposed on their corresponding
`IDOSStationTimetableStop` instead of being duplicated in the timetable-wide notes. Human-readable text
received from IDOS uses the Unicode `→` symbol instead of an ASCII substitute; opaque identifiers and URLs
remain unchanged.

Eight integrated systems contain separate municipal Station Timetable catalogs. Use
`IDOSStationTimetableMunicipality.available(for:)` to present the supported choices or `resolve(_:timetable:)`
to accept either an IDOS municipality name or identifier. Pass the same municipality to the line and stop
suggestion overloads and to `IDOSStationTimetableRequest`; the parsed `IDOSStationTimetable` retains that choice.

| Timetable | Municipalities | Default |
| --- | --- | --- |
| ODIS | Bruntál, Český Těšín, Frýdek-Místek, Havířov, Karviná, Krnov, Nový Jičín, Opava, Orlová, Ostrava, Studénka, Třinec | Ostrava |
| IDOL | Česká Lípa, Jablonec nad Nisou, Liberec, Turnov | Česká Lípa |
| IDSOK | Hranice, Olomouc, Prostějov, Přerov, Šumperk, Zábřeh | Hranice |
| IREDO | Dvůr Králové nad Labem, Chrudim, Náchod, Přelouč, Rychnov nad Kněžnou, Týniště nad Orlicí, Vrchlabí | Dvůr Králové nad Labem |
| DÚK | Bílina, Děčín, Chomutov, Klášterec nad Ohří, Most-Litvínov, Roudnice nad Labem, Teplice, Ústí nad Labem, Varnsdorf | Ústí nad Labem |
| IDPK | Domažlice, Klatovy, Plzeň, Rokycany, Stříbro, Tachov | Plzeň |
| IDZK | Uherské Hradiště, Vsetín | Uherské Hradiště |
| IDESKA | České Budějovice, Český Krumlov, Jindřichův Hradec, Milevsko, Písek, Strakonice, Tábor, Vimperk | České Budějovice |

Timetables without a municipality chooser return an empty choice list and continue to use the
municipality-free overloads.

## Data Source

The library calls publicly reachable IDOS web endpoints and parses HTML and internal JSONP responses. It is
intended for low-frequency personal use, not as a stable or guaranteed data API.
