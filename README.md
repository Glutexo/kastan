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
```

Search station departures:

```sh
swift run kastan departures --station "Ostrava,Hrabůvka,Benzina" --timetable odis --time 16:00
swift run kastan departures --station "Ostrava,Hrabůvka,Benzina" --timetable odis --arrival
```

Line names in connection output use the same terminal color as IDOS sends in the HTML result.
Connection legs also include transport emoji such as 🚆 for trains and 🚌 for buses when IDOS exposes the transport type.

### Output Format

All data commands support `--format text`, `--format markdown`, and `--format json`. The default is `text`.
Unknown command-line options are rejected.

```sh
swift run kastan suggest Praha --format json
swift run kastan connections --from Praha --to Brno --format markdown
swift run kastan departures --station "Ostrava,Hrabůvka,Benzina" --format json
swift run kastan timetables --format json
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

let departuresRequest = IDOSDeparturesRequest(
    timetable: timetable,
    station: "Ostrava,Hrabůvka,Benzina",
    time: "16:00"
)
let departures = try await client.findDepartures(request: departuresRequest)
```

The public API includes `IDOSClient`, `IDOSConnectionRequest`, `IDOSDeparturesRequest`, `IDOSTimetable`, `IDOSSuggestion`, `IDOSConnection`, `IDOSConnectionLeg`, `IDOSDeparture`, `IDOSTransportMode`, and `IDOSError`.

## 🌰 Development

```sh
swift build
swift test
swift run kastan
```
