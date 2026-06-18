# jizdni-nerady

jizdni-nerady is a personal Swift CLI and importable Swift library for occasional one-off IDOS queries.
It uses publicly reachable IDOS web endpoints and parses returned HTML, so it is not a stable or guaranteed data API.

## Usage

Suggest a station or place:

```sh
swift run jizdni-nerady suggest Praha
swift run jizdni-nerady suggest Svinov --timetable ostrava
```

Search connections:

```sh
swift run jizdni-nerady connections --from Praha --to Brno --date 18.6.2026 --time 12:00
swift run jizdni-nerady connections --from "Frýdek-Místek" --to Ostrava --timetable odis
```

Line names in connection output use the same terminal color as IDOS sends in the HTML result.
Connection legs also include transport emoji such as 🚆 for trains and 🚌 for buses when IDOS exposes the transport type.

### Output Format

All data commands support `--format text`, `--format markdown`, and `--format json`. The default is `text`.
Unknown command-line options are rejected.

```sh
swift run jizdni-nerady suggest Praha --format json
swift run jizdni-nerady connections --from Praha --to Brno --format markdown
swift run jizdni-nerady timetables --format json
```

Limit the number of printed results:

```sh
swift run jizdni-nerady connections --from Praha --to Brno --limit 3
```

Search direct connections only:

```sh
swift run jizdni-nerady connections --from Praha --to Brno --direct
```

Search connections via one or more places:

```sh
swift run jizdni-nerady connections --from Praha --to Brno --via Pardubice
swift run jizdni-nerady connections --from Praha --to Brno --via Pardubice --via Olomouc
```

Search by departure time explicitly, or by arrival time instead:

```sh
swift run jizdni-nerady connections --from Praha --to Brno --time 12:00 --departure
swift run jizdni-nerady connections --from Praha --to Brno --time 15:00 --arrival
```

Limit the maximum transfers permitted, including `0`:

```sh
swift run jizdni-nerady connections --from Praha --to Brno --max-transfers 0
```

Require a minimum transfer time in minutes, including `0`:

```sh
swift run jizdni-nerady connections --from Praha --to Brno --min-transfer-time 10
```

### Timetable

The default timetable is `vlakyautobusymhdvse`, IDOS English `All timetables`. Select another timetable with `--timetable`:

```sh
swift run jizdni-nerady connections --from Praha --to Beroun --timetable pid
swift run jizdni-nerady connections --from Ostrava --to "Frýdek-Místek" --timetable odis
swift run jizdni-nerady connections --from Praha --to Brno --timetable vlaky
```

Print known timetable choices:

```sh
swift run jizdni-nerady timetables
```

The parameter also accepts a custom IDOS URL slug, such as `karlovyvary`, when IDOS supports it. Besides slugs, catalog names work too, for example `--timetable "Urban Public Transport Karlovy Vary"` or `--timetable "Zlín a Otrokovice"`.

This tool is intended for low-frequency personal use. If IDOS changes its HTML or internal JSONP suggestions endpoint, the parser will need an update.

## Swift Library

The package exports the `JizdniNerady` library product:

```swift
import JizdniNerady

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
```

The public API includes `IDOSClient`, `IDOSConnectionRequest`, `IDOSTimetable`, `IDOSSuggestion`, `IDOSConnection`, `IDOSConnectionLeg`, `IDOSTransportMode`, and `IDOSError`.

## Development

```sh
swift build
swift test
swift run jizdni-nerady
```
