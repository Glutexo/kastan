# Kaštan Swift Library

[← Documentation](README.md)

The Swift package exports the `Kastan` library product used by the CLI, macOS app, and MCP server. It requires
Swift 6.3 or newer and declares macOS 12 as its minimum Apple-platform deployment target.

## Package Dependency

Depend on the latest compatible `0.7.x` release:

```swift
dependencies: [
    .package(
        url: "https://github.com/Glutexo/kastan.git",
        .upToNextMinor(from: "0.7.0")
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

let dataSource = IDOSDataSource()
let timetable = try dataSource.resolveTimetable("odis")
let request = TransitConnectionRequest(
    timetable: timetable,
    from: "Frýdek,Na Veselé",
    to: "Ostrava,Hrabůvka,Benzina",
    serviceDate: TransitDate(year: 2026, month: 7, day: 17),
    serviceTime: TransitTime(hour: 16, minute: 0),
    isArrival: true,
    onlyDirect: true,
    via: ["Místek,Anenská"],
    maxTransfers: 0,
    minimumTransferTime: 10,
    maximumTransferTime: 360,
    maximumWalkingTime: 45,
    maximumCityWalkingTime: 20,
    walkToNearbyStops: true,
    sameNameWalkingTransfersOnly: false,
    resultLimit: 8
)

let connections = try await dataSource.findConnections(request: request)
let calendar = try await dataSource.connectionCalendar(
    for: connections[0],
    timetable: timetable,
    language: .czech
)
let pdf = try await dataSource.connectionPDF(
    for: connections[0],
    timetable: timetable,
    language: .czech
)
let stations = try await dataSource.searchStations(prefix: "Svinov", timetable: timetable)

let departuresRequest = TransitDeparturesRequest(
    timetable: timetable,
    station: "Ostrava,Hrabůvka,Benzina",
    serviceTime: TransitTime(hour: 16, minute: 0)
)
let departures = try await dataSource.findDepartures(request: departuresRequest)
let service = try await dataSource.serviceDetail(
    id: departures[0].id,
    timetable: timetable,
    language: .czech
)
let serviceInformation = service.serviceInformation
let firstInformationCategory = serviceInformation.first?.category
let firstInformationText = serviceInformation.first?.displayText
let validity = try await dataSource.timetableValidity(for: service.timetable, language: .czech)
let operatingDays = try await dataSource.serviceDateLimits(for: service, language: .czech)
let selectedDayStatus = operatingDays.status(on: operatingDays.referenceServiceDate)
let serviceCalendar = try await dataSource.serviceCalendar(for: service, language: .czech)
let servicePDF = try await dataSource.servicePDF(for: service, language: .czech)

let municipality = try dataSource.resolveStationTimetableMunicipality(
    "Frýdek-Místek",
    timetable: timetable
)
let lines = try await dataSource.searchStationTimetableLines(
    prefix: "301",
    timetable: timetable,
    municipality: municipality
)
let stationTimetable = try await dataSource.findStationTimetable(
    request: TransitStationTimetableRequest(
        timetable: timetable,
        municipality: municipality,
        line: lines[0].text,
        from: lines[0].from!,
        to: lines[0].to!,
        serviceDate: TransitDate(year: 2026, month: 7, day: 17),
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

## Data Sources and Public API

New integrations should depend on the complete `TransitDataSource` protocol or on the narrow capability protocols
needed by their interface:

- `TransitDataSourceDescribing` supplies a `TransitDataSourceDescriptor` with the provider's stable
  `TransitDataSourceID`, display name, and advertised `TransitDataSourceCapability` values.
- `TransitTimetableProviding` owns the provider's timetable catalog and resolves user-facing timetable values.
- `TransitPlaceSearching`, `TransitConnectionSearching`, `TransitDepartureBoardProviding`, and
  `TransitStationTimetableProviding` cover suggestions and the three search surfaces.
- `TransitStationTimetableDepartureResolving` lets a provider interpret one of its own rendered timetable values
  and return the corresponding station-board page, request, civil date, and local time.
- `TransitServiceDetailProviding`, `TransitConnectionExporting`, `TransitServiceExporting`, and
  `TransitConnectionEmailSending` cover service metadata, native exports, and provider-generated email.

The complete protocol composes all of these facets. Default implementations for unimplemented primary operations
report `TransitDataSourceError.unsupported`; convenience adapters supply catalogs, language overloads, and one-shot
page wrappers where the narrower operation is implemented. Adjacent-page defaults likewise report the corresponding
unsupported paging capability rather than silently returning an empty result. A future provider can therefore
implement and advertise only the operations it actually supports. Every new `TransitDataSource` supplies its
descriptor explicitly, so
persisted source IDs never depend on a Swift type name. Consumers can inspect `descriptor.supports(_:)` before
presenting a capability.

Connection-search controls use a second, fine-grained contract. A descriptor lists its supported
`TransitConnectionOption` values in `connectionOptions`, covering Direct connections only, Via, transfer-count and
transfer-time limits, walking limits, and the two walking-transfer policies independently. Advertising
`TransitDataSourceCapability.connections` does not imply support for any of these request options. Interfaces should
therefore check `descriptor.supports(_:)` for the individual option before presenting its control or accepting its
value. IDOS declares the complete set; descriptors created without `connectionOptions`, including descriptors decoded
from older stored JSON, conservatively declare none.

`stationTimetableDepartureResolution` is a separate capability from `stationTimetables` and `departures`. It means
that a consumer may pass a `TransitStationTimetableDepartureResolutionRequest` to
`resolveStationTimetableDeparture(request:language:)` and receive the provider's
`TransitStationTimetableDepartureResolution`. The request identifies the rendered value by indices and does not
interpret its text. Supporting both source surfaces does not imply that their identifiers, dates, display values,
or line and direction semantics can be matched. IDOS keeps its minute, weekday-label, and line matching inside
`IDOSDataSource`; another provider can use completely different display syntax when it implements and advertises
this capability.

`TransitDataSourceRegistry` resolves providers by stable ID and exposes descriptors without coupling callers to
concrete implementations. Registration rejects duplicate provider IDs, case-insensitive duplicate timetable
identifiers within one provider, a default timetable absent from its catalog, a missing default provider, and any
default or catalog timetable whose `dataSourceID` differs from its
provider descriptor. `TransitDataSourceRegistry.builtIn` currently contains one provider, `IDOSDataSource`, with
`.idos` as the default. `IDOSDataSource` implements all currently advertised capabilities through publicly reachable
IDOS endpoints.

Timetables are provider-owned values. `TransitTimetable.dataSourceID` identifies their source, while `identifier`
is the provider-neutral spelling of IDOS's historical `slug`. Older encoded timetables without a source ID decode
as IDOS values, and IDOS timetable JSON retains its existing representation.

Connection and departure paging is provider-owned too. `TransitConnectionPage` and `TransitDeparturePage` carry
their `dataSourceID` plus an opaque `TransitPageContinuation`. A caller passes the complete page back to the same
source with a `TransitPageDirection`; only that provider recovers and interprets its private continuation value.
Passing a page to another provider fails with `TransitDataSourceError.pageBelongsToDifferentSource`.

The main provider-neutral model types are:

- Requests and timetables: `TransitConnectionRequest`, `TransitDeparturesRequest`,
  `TransitStationTimetableRequest`, `TransitStationTimetableMunicipality`, `TransitPlaceSelection`,
  `TransitStationTimetableDepartureResolutionRequest`, `TransitDate`, `TransitTime`, `TransitTimetable`,
  `TransitTimetableValidity`, `TransitLanguage`, and `TransitPageDirection`.
- Results: `TransitSuggestion`, `TransitConnection`, `TransitConnectionEmailDraft`, `TransitConnectionLeg`,
  `TransitDeparture`, `TransitServiceDetail`, `TransitServiceInformation`, `TransitServiceStop`,
  `TransitStationTimetable`, `TransitStationTimetableStop`, `TransitStationTimetableSchedule`,
  `TransitStationTimetableHour`, `TransitStationTimetableDepartureResolution`, `TransitServiceDateLimits`,
  `TransitConnectionPage`, `TransitDeparturePage`, and `TransitTransportMode`.
- Personal aliases: `StopAlias`, `StopAliasDatabase`, `StopAliasFile`, and `StopAliasError`.

`IDOSClient` remains a source-compatible type alias for `IDOSDataSource`. The earlier model names prefixed with
`IDOS`, such as `IDOSTimetable`, `IDOSConnectionRequest`, and `IDOSConnection`, are likewise aliases for their
canonical `Transit` names. Existing custom `IDOSClienting` implementations remain compatible through that
protocol's IDOS defaults. Its fallback descriptor advertises the operations that the original protocol required,
plus its timetable and coordinate adapters; historical optional defaults such as paging and exports stay hidden
until a conformer declares them explicitly. The legacy empty adjacent-page fallback remains available. New
integrations should use `TransitDataSource` or its capability protocols.

`IDOSDataSource.timetables` mirrors the current IDOS catalog, including all ten integrated systems and all 106
standalone Urban Public Transport cities. Prague is represented by its `pid` catalog instead of a duplicate
standalone city. `resolveTimetable(_:)` accepts each built-in display name or URL slug and continues to accept a
valid custom IDOS slug.

Connection-result, service, and departure identifiers are opaque and must not be parsed by clients. Pass the exact
owning timetable back to `serviceDetail(id:timetable:language:)`; the shorter compatibility overload is suitable only
for historical IDOS identifiers that carry their own timetable context. Connection, departure, and suggestion values
retain a non-default IDOS timetable identifier when encoded, while values in the
historical default timetable keep their previous JSON representation. Older IDOS connection or suggestion JSON
without that field remains deliberately unscoped, so a caller can supply the original non-default timetable instead
of having compatibility decoding invent the global default as its owner. An explicitly non-IDOS value must include
both its source and timetable namespace when decoded. Models preserve the semantic information
received from IDOS, including line colors, transport modes, platforms,
tariff zones, carriers, delay details, and localized service notes when available. `TransitConnectionLeg` and
`TransitDeparture` expose the facilities and restrictions printed beside a result through their ordered
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

`TransitServiceDetail.information` preserves every original IDOS information line as a writable compatibility view.
Its canonical `serviceInformation` storage adds a `TransitServiceInformation.Category` and the same semantic symbol
used by Kaštan's human-readable interfaces without replacing that text. Structured providers can supply exact
categories with `TransitServiceInformation(text:category:)` without imitating IDOS wording; encoded details retain
the raw field and add structured categories only
when text classification cannot recover that meaning. Categories distinguish passenger-facing meanings
such as replacement transport, accommodation, seating-class availability, onboard services, accessibility including
low-floor vehicles, tickets and reservations, operating calendars, restrictions, routes including skipped-stop
instructions, and carriers; unrecognized text remains in the `general` category.

Create a `TransitPlaceSelection` from a chosen `TransitSuggestion` and pass it as `fromSelection`, `toSelection`,
`stationSelection`, or the corresponding element of `viaSelections` when the query must target that exact IDOS
object. The selection retains both the source and the timetable in which its opaque identifier is valid; IDOS
rejects a known timetable mismatch before interpreting that identifier. The historical IDOS initializer remains
usable as an unscoped compatibility value. This distinguishes, for example, a railway station from a municipality
with the same visible name.
`viaSelections` follows the order of `via`; use `nil` for any element that should retain free-text interpretation.
Leave endpoint or station selections unset for the same free-text interpretation as typing into the IDOS form
without choosing a suggestion.

Use `serviceDate` and `serviceTime` on search requests to pass a Gregorian civil date and local wall-clock time
without depending on any provider's wire format. A new data source reads these `TransitDate` and `TransitTime`
values directly and translates them only in its own transport adapter. The older `date` and `time` string fields
remain available for source compatibility with callers that already supply IDOS-formatted values; they are an
IDOS compatibility surface rather than an input format for new providers. When both representations are present,
`IDOSDataSource` gives the semantic value precedence.

Calendar-backed provider results make their civil zone explicit. Construct `TransitTimetableValidity` and
`TransitServiceDateLimits` with the `timeZone:` overload; `TransitServiceDateLimits.status(on:)` also accepts a
`TransitDate`, so consumers do not have to reinterpret the provider's day in the device time zone. The historical
two-argument IDOS date-limits initializer and older JSON without zone metadata retain Europe/Prague semantics.
IDOS JSON continues to omit that default identifier, while another provider's zone is encoded for a stable
round trip. `TransitDataSourceDescribing.serviceTimeZone` supplies the same zone to presentation that needs to
interpret provider text without an accompanying calendar model.

Connection requests expose the complete IDOS transfer panel. `maxTransfers` includes zero, while
`minimumTransferTime` accepts minute values or `-1` for the timetable's standard. `maximumTransferTime`,
`maximumWalkingTime`, and `maximumCityWalkingTime` use minutes. `walkToNearbyStops` controls whether the journey may
start or end at a stop reached on foot, and `sameNameWalkingTransfersOnly` restricts walking transfers to stops with
the same name. Leave any of these values as `nil` to retain the corresponding IDOS default.

For a connection endpoint obtained from a device's WGS-84 coordinates, first check the source's
`coordinatePlaceSelection` capability. Then call
`coordinatePlaceSelection(text:latitude:longitude:timetable:)` and pass the returned value together with its `text`
as `fromSelection` or `toSelection`. The caller supplies the localized visible text, such as `My location`; the
selected source owns the coordinate representation. The older `TransitPlaceSelection.currentLocation` convenience
remains available only as an IDOS compatibility surface.

`connectionCalendar` returns IDOS iCalendar text for a search result. `serviceCalendar` and `servicePDF`
resolve a dated service's permanent result link and return the corresponding native IDOS export. Calendar and PDF
exports accept an explicit language for their human-readable text; calendar calls without one retain the historical
English default for source compatibility.
`timetableValidity` returns the inclusive first and last dates published by the selected IDOS timetable together
with its civil service-day zone.
`serviceDateLimits` returns the exact `runs`, `doesNotRun`, or `informationUnavailable` state that IDOS publishes
for every civil day in its native service date-restriction calendar. Its `referenceDate` anchors the first returned
month, while `firstDate`, `lastDate`, `firstServiceDate`, `lastServiceDate`, and both `status(on:)` overloads let a
client present only the interval actually supplied by IDOS instead of interpreting operating rules from prose. The
call throws `IDOSError.dateLimitsUnavailable` when
IDOS does not expose a usable native calendar for that service.

`connectionEmailDraft` loads IDOS's localized default message and the PDF and calendar attachment names for one
connection result. After an application has collected one or more recipient addresses and received explicit user
confirmation, `sendConnectionByEmail` asks IDOS to generate and deliver those attachments:

```swift
let draft = try await dataSource.connectionEmailDraft(
    for: connections[0],
    timetable: timetable,
    language: .czech
)

// Call only after the user confirms both the recipients and editable message.
try await dataSource.sendConnectionByEmail(
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
`TransitStationTimetableStop` instead of being duplicated in the timetable-wide notes. Human-readable text
received from IDOS uses the Unicode `→` symbol instead of an ASCII substitute; opaque identifiers and URLs
remain unchanged.

To open a concrete run from one rendered value, first check `stationTimetableDepartureResolution`, then call
`resolveStationTimetableDeparture(request:language:)`. The provider returns the exact `TransitDeparture`, the page
that contains it, the `TransitDeparturesRequest` suitable for handing to a station-board interface, and semantic
`TransitDate`/`TransitTime` values. Callers do not parse timetable hour labels or departure text themselves.

Eight integrated systems contain separate municipal Station Timetable catalogs. Use
`stationTimetableMunicipalities(for:)` on the selected data source to present the supported choices or
`resolveStationTimetableMunicipality(_:timetable:)` to accept either an IDOS municipality name or identifier. Pass
the same `TransitStationTimetableMunicipality` to the line and stop suggestion overloads and to
`TransitStationTimetableRequest`; the parsed `TransitStationTimetable` retains that choice.

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

The built-in `IDOSDataSource` calls publicly reachable IDOS web endpoints and parses HTML and internal JSONP
responses. It is intended for low-frequency personal use, not as a stable or guaranteed data API.
