# 🌰 Kaštan

Kaštan (`kastan`) is a personal Swift CLI and importable Swift library for occasional one-off IDOS queries.
It uses publicly reachable IDOS web endpoints and parses returned HTML, so it is not a stable or guaranteed data API.

## 🌰 Usage

Suggest a station or place:

```sh
swift run kastan suggest Praha
swift run kastan suggest Svinov --timetable ostrava
```

Search connections:

```sh
swift run kastan connections --from Praha --to Brno --date 18.6.2026 --time 12:00
swift run kastan connections --from "Frýdek-Místek" --to Ostrava --timetable odis
swift run kastan connections Praha-Brno --time 12:00
swift run kastan connections Praha Brno --time 12:00
swift run kastan connections "Praha -> Brno"
swift run kastan connections "Praha → Brno"
swift run kastan Praha Brno --time 12:00
swift run kastan Praha→Brno
```

Search station departures:

```sh
swift run kastan departures --from "Ostrava,Hrabůvka,Benzina" --timetable odis --time 16:00
swift run kastan departures --station "Ostrava,Hrabůvka,Benzina" --timetable odis --time 16:00
swift run kastan departures --station "Ostrava,Hrabůvka,Benzina" --timetable odis --arrival
swift run kastan "Ostrava,Hrabůvka,Benzina" --timetable odis --time 16:00
```

Line names in connection output use the same terminal color as IDOS sends in the HTML result.
Connection legs also include transport emoji such as 🚆 for trains and 🚌 for buses when IDOS exposes the transport type.
Connection and departure times are bold in text and markdown output.
Connection and departure results show IDOS tariff zones and platforms when IDOS includes them.
Departure headings use the station name resolved by IDOS, not necessarily the exact query text.

### Output Format

All data and alias commands support `--format text`, `--format markdown`, and `--format json`. The default is `text`.
The `connections` command also supports `--format ics`, which prints the IDOS iCalendar file for the first returned connection.
Use `--add-to-calendar` to open that IDOS iCalendar file directly in the system calendar application.
Unknown command-line options are rejected.
Network failures, including missing internet connectivity, are printed as normal command errors in the selected format.

```sh
swift run kastan suggest Praha --format json
swift run kastan connections --from Praha --to Brno --format markdown
swift run kastan connections --from Praha --to Brno --format ics > connection.ics
swift run kastan connections --from Praha --to Brno --add-to-calendar
swift run kastan departures --station "Ostrava,Hrabůvka,Benzina" --format json
swift run kastan timetables --format json
swift run kastan aliases list --format json
```

Limit the number of printed results:

```sh
swift run kastan connections --from Praha --to Brno --limit 3
```

Search direct connections only:

```sh
swift run kastan connections --from Praha --to Brno --direct
```

Search connections via one or more places:

```sh
swift run kastan connections --from Praha --to Brno --via Pardubice
swift run kastan connections --from Praha --to Brno --via Pardubice --via Olomouc
```

Search by departure time explicitly, or by arrival time instead:

```sh
swift run kastan connections --from Praha --to Brno --time 12:00 --departure
swift run kastan connections --from Praha --to Brno --time 15:00 --arrival
```

Limit the maximum transfers permitted, including `0`:

```sh
swift run kastan connections --from Praha --to Brno --max-transfers 0
```

Require a minimum transfer time in minutes, including `0`:

```sh
swift run kastan connections --from Praha --to Brno --min-transfer-time 10
```

### Stop Aliases

Store personal stop aliases with the IDOS timetable they belong to:

```sh
swift run kastan aliases add home --station "Frýdek,Na Veselé" --timetable odis
swift run kastan aliases add work --station "Ostrava,Hrabůvka,Benzina" --timetable odis
swift run kastan aliases list
swift run kastan aliases remove home
swift run kastan aliases path
```

Aliases can be used anywhere a station or place is accepted:

```sh
swift run kastan connections --from home --to work --time 16:00
swift run kastan connections home→work --time 16:00
swift run kastan connections home work --time 16:00
swift run kastan home work --time 16:00
swift run kastan departures --from work --time 16:00
swift run kastan departures --station work --time 16:00
swift run kastan work --time 16:00
```

When all used aliases belong to the same timetable, Kaštan uses that timetable automatically.
If `--timetable` is provided, every used alias must belong to that timetable.
The default database is `~/.config/kastan/aliases.json`; set `KASTAN_ALIAS_DATABASE` to use another JSON file.

### Timetable

The default timetable is `vlakyautobusymhdvse`, IDOS English `All timetables`. Select another timetable with `--timetable`:

```sh
swift run kastan connections --from Praha --to Beroun --timetable pid
swift run kastan connections --from Ostrava --to "Frýdek-Místek" --timetable odis
swift run kastan connections --from Praha --to Brno --timetable vlaky
```

Print known timetable choices:

```sh
swift run kastan timetables
```

The parameter also accepts a custom IDOS URL slug, such as `karlovyvary`, when IDOS supports it. Besides slugs, catalog names work too, for example `--timetable "Urban Public Transport Karlovy Vary"` or `--timetable "Zlín a Otrokovice"`.

This tool is intended for low-frequency personal use. If IDOS changes its HTML or internal JSONP suggestions endpoint, the parser will need an update.

## 🌰 Swift Library

The package exports the `Kastan` library product:

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
    minimumTransferTime: 10
)
let connections = try await client.findConnections(request: request)
let calendar = try await client.connectionCalendar(for: connections[0], timetable: timetable)

let departuresRequest = IDOSDeparturesRequest(
    timetable: timetable,
    station: "Ostrava,Hrabůvka,Benzina",
    time: "16:00"
)
let departures = try await client.findDepartures(request: departuresRequest)

let aliasFile = StopAliasFile()
var aliases = try aliasFile.load()
try aliases.upsert(StopAlias(name: "work", station: "Ostrava,Hrabůvka,Benzina", timetable: timetable))
try aliasFile.save(aliases)
```

The public API includes `IDOSClient`, `IDOSConnectionRequest`, `IDOSDeparturesRequest`, `IDOSTimetable`, `IDOSSuggestion`, `IDOSConnection`, `IDOSConnectionLeg`, `IDOSDeparture`, `IDOSTransportMode`, `StopAlias`, `StopAliasDatabase`, `StopAliasFile`, `StopAliasError`, and `IDOSError`.

## 🌰 Development

```sh
swift build
swift test
swift run kastan
```
