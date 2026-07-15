# 🌰 Kaštan

Kaštan is a native macOS app, personal Swift CLI (`kastan`), importable Swift library, and local MCP server for occasional IDOS queries.
It uses publicly reachable IDOS web endpoints and parses returned HTML, so it is not a stable or guaranteed data API.

## 🌰 Building

Kaštan requires Git and Swift 6.3 or newer. Download Swift only from the [official Swift installation page](https://www.swift.org/install/); development snapshots are not required.

### macOS

Open Terminal. If Git and Apple's command-line developer tools are not installed yet, request their installer first:

```sh
xcode-select --install
```

Download the official Swiftly toolchain manager from swift.org and let it install the latest stable Swift release for the current user:

```sh
curl -O https://download.swift.org/swiftly/darwin/swiftly.pkg
installer -pkg swiftly.pkg -target CurrentUserHomeDirectory
~/.swiftly/bin/swiftly init --quiet-shell-followup
. "${SWIFTLY_HOME_DIR:-$HOME/.swiftly}/env.sh"
hash -r
```

These commands are also available in the [official macOS instructions](https://www.swift.org/install/macos/). Verify that Swift 6.3 or newer and Git are available:

```sh
swift --version
git --version
```

Then clone and build Kaštan. The package declares macOS 12 as its minimum deployment target.

```sh
git clone https://github.com/Glutexo/kastan.git
cd kastan
swift build -c release
swift test
"$(swift build -c release --show-bin-path)/kastan" --help
```

The release executable is in the directory printed by `swift build -c release --show-bin-path`.

### Windows

This WinGet installation route requires Windows 10 version 1809 or newer. WinGet is included with current Windows 10 and Windows 11 installations as part of App Installer; follow the [Microsoft WinGet instructions](https://learn.microsoft.com/en-us/windows/package-manager/winget/) if the `winget` command is missing.

Enable **Developer Mode** in Windows Settings before installing Swift. Search Settings for "Developer Mode" and turn it on; Microsoft documents the current location in its [Developer Mode instructions](https://learn.microsoft.com/en-us/windows/advanced-settings/developer-mode).

Open PowerShell and install the Visual Studio C++ toolchain and Windows SDK. Accept an administrator elevation prompt if Windows shows one:

```powershell
winget install --id Microsoft.VisualStudio.2022.Community --exact --force --custom "--add Microsoft.VisualStudio.Component.Windows11SDK.22621 --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.VC.Tools.ARM64" --source winget
```

Install the latest stable Swift toolchain. The Swift WinGet package also installs compatible Git and Python dependencies when they are missing:

```powershell
winget install --id Swift.Toolchain --exact --source winget
```

These commands come from the [official Windows instructions](https://www.swift.org/install/windows/). Close and reopen PowerShell after installation, then verify the tools:

```powershell
swift --version
git --version
```

Clone and build Kaštan in PowerShell:

```powershell
git clone https://github.com/Glutexo/kastan.git
Set-Location kastan
swift build -c release
swift test
$binPath = swift build -c release --show-bin-path
& "$binPath\kastan.exe" --help
```

### Linux

The official Swiftly installer supports Ubuntu, Debian, Fedora, Red Hat Enterprise Linux, and Amazon Linux. First install Git and the small set of tools used to download and verify Swift. For example, on Ubuntu or Debian:

```sh
sudo apt update
sudo apt install -y curl ca-certificates gnupg tar git
```

Use the equivalent package names and package manager on other supported distributions. Then download Swiftly directly from swift.org and let it install the latest stable Swift release and any additional distribution dependencies:

```sh
curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz
tar zxf swiftly-$(uname -m).tar.gz
./swiftly init --quiet-shell-followup
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
hash -r
```

These are the commands from the [official Linux instructions](https://www.swift.org/install/linux/). Follow any package-installation prompts from Swiftly, then verify the tools:

```sh
swift --version
git --version
```

Clone and build Kaštan:

```sh
git clone https://github.com/Glutexo/kastan.git
cd kastan
swift build -c release
swift test
"$(swift build -c release --show-bin-path)/kastan" --help
```

All query, alias, and output-format commands build on the three platforms. Direct calendar opening with `--add-to-calendar` is available only on macOS; use `--format ics` to save a calendar file on Windows or Linux.

## 🌰 Usage

Suggest a station or place:

```sh
swift run kastan suggest Praha
swift run kastan suggest Svinov --timetable ostrava
```

Search stations by name:

```sh
swift run kastan stations Praha
swift run kastan stations Svinov -T ostrava -l 5
```

Search connections:

```sh
swift run kastan connections --from Praha --to Brno --date 18.6.2026 --time 12:00
swift run kastan connections --from "Frýdek-Místek" --to Ostrava --timetable odis
swift run kastan connections -f Praha -t Brno -T vlaky -m 12:00 -v
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

Load a service's complete route from an ID shown by `connections --verbose` or `departures --verbose`:

```sh
swift run kastan service 'vlaky:0-74552-14.07.2026 20:41:00'
swift run kastan service 'vlaky:0-74552-14.07.2026 20:41:00' -o json
```

Quote the ID because it contains a space. Current IDs embed the timetable slug, so `service` does not need `--timetable`. The option remains available only as timetable context for legacy IDs produced by older Kaštan versions. The detail includes every stop supplied by IDOS, arrival and departure times, tariff zones, platforms or tracks, distance, stop notes, and service information. The selected output language, resolved from the system locale or `--language`, is also used for notes and information supplied by IDOS. Text and Markdown output add semantic emoji to common stop notes, such as ♿ for wheelchair accessibility and 🚉 for rail stations; JSON retains the original IDOS text in the selected language.

Line names in connection output use the same terminal color as IDOS sends in the HTML result.
Connection legs also include transport emoji such as 🚆 for trains and 🚌 for buses when IDOS exposes the transport type.
Connection result headings mark connections without a transfer as `➡️  Direct` and the shortest displayed connection as `⚡ Shortest`.
When multiple displayed connections share the shortest duration, Kaštan marks all of them. JSON output exposes the same information as `isDirect` and `isShortest`.
Connection and departure times are bold in text and markdown output.
Use `--verbose` to show each result ID together with IDOS tariff zones, platforms, carriers, and current delay information when IDOS includes them.
Each connection leg also shows a service ID. It is the same opaque ID that `departures` returns for the corresponding service and can be passed to `kastan service` to load the service's complete route.
Connection-result, service, and departure IDs are opaque values, so scripts should not parse their internal structure.
JSON output includes connection-result and departure IDs in each result's `id` field and service IDs in `connections[].legs[].id` regardless of `--verbose`.
Departure headings use the station name resolved by IDOS, not necessarily the exact query text.
When a connection place, departure station, or alias station is not an exact match and IDOS returns multiple candidates, Kaštan reports the ambiguous name and lists the possible IDOS choices.

### Language

Human-readable text and Markdown output is available in English and Czech.
Kaštan selects the first supported language from the system preferences or POSIX locale variables and falls back to English when neither language is configured.
Override that choice for any invocation with `--language en`, `--language cs`, or the `--lang` alias; the option can appear before or after the command.
Regional locale identifiers such as `en-US`, `cs-CZ`, and `cs_CZ.UTF-8` are accepted too.

```sh
swift run kastan --language cs --help
swift run kastan connections Praha Brno --lang en
swift run kastan timetables --language cs --format markdown
```

Command names, option names, JSON keys and domain data values, and iCalendar data stay language-independent so scripts keep a stable interface; the human-readable JSON `error` value follows the selected language.
Names and status details received from IDOS remain in the form supplied by IDOS; Kaštan localizes its own headings, labels, help, and error messages.

### Output Format

All data and alias commands support `--format text`, `--format markdown`, and `--format json`. The default is `text`.
The `connections` command also supports `--format ics`, which prints the IDOS iCalendar file for the first returned connection.
Use `--add-to-calendar` to open that IDOS iCalendar file directly in the system calendar application.
Unknown command-line options are rejected.
Network failures, including missing internet connectivity, are printed as normal command errors in the selected format.

```sh
swift run kastan suggest Praha --format json
swift run kastan stations Praha --format json
swift run kastan connections --from Praha --to Brno --format markdown
swift run kastan connections --from Praha --to Brno --verbose
swift run kastan connections --from Praha --to Brno --format ics > connection.ics
swift run kastan connections --from Praha --to Brno --add-to-calendar
swift run kastan departures --station "Ostrava,Hrabůvka,Benzina" --format json
swift run kastan service 'vlaky:0-74552-14.07.2026 20:41:00' --format markdown
swift run kastan timetables --format json
swift run kastan aliases list --format json
```

Common options also have short switches: `-f` (`--from`), `-t` (`--to`), `-s` (`--station`), `-T` (`--timetable`), `-d` (`--date`), `-m` (`--time`), `-a` (`--arrival`), `-p` (`--departure`), `-V` (`--via`), `-x` (`--direct`), `-c` (`--add-to-calendar`), `-v` (`--verbose`), `-X` (`--max-transfers`), `-M` (`--min-transfer-time`), `-o` (`--format`), and `-l` (`--limit`).
Language uses the long `--language` option or its `--lang` alias.
Short flags can be combined, for example `-vx` is the same as `-v -x`; a short option with a value can be the last item in the group, such as `-vxT odis`.

Limit the number of printed results:

```sh
swift run kastan connections --from Praha --to Brno --limit 3
```

For connections, Kaštan asks IDOS for later connections until the requested limit is reached or IDOS has no more results to add.
For suggestions, station search, and departures, `--limit` controls how many returned rows are printed.

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
swift run kastan aliases add s "Sídliště Petrovice" --timetable pid
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

## 🌰 macOS App

The repository includes a native SwiftUI application for macOS 13 or newer. It imports the `Kastan` library directly, so its IDOS requests and parsed models stay aligned with the CLI and MCP server.

The first app release supports:

- connection searches with IDOS place suggestions, date, time, arrival mode, direct journeys, individually editable via-place rows, and transfer limits;
- station departures and arrivals with station-only suggestions;
- timetable menus grouped into general rail and bus choices, integrated transport systems, and individual city networks;
- native search workspaces with flat macOS-style option rows that avoid repeated page headings, use the full detail width, and adapt to narrow windows;
- line colors, transport symbols, platforms, tariff zones, carriers, and delay details supplied by IDOS;
- complete service routes opened from connection legs and station-board rows, presented as a neutral stop sequence rather than a live-position indicator;
- IDOS calendar export opened in the user's macOS calendar application;
- an in-app information panel covering the data source and limitations, with links to IDOS, its terms, and the Kaštan repository;
- English and Czech user-interface localization.

Open the shared Xcode project and run the `KastanApp` scheme:

```sh
open KastanApp/KastanApp.xcodeproj
```

The project requires an Xcode toolchain with Swift 6.3 or newer. It can also be built and tested from Terminal:

```sh
xcodebuild build -project KastanApp/KastanApp.xcodeproj -scheme KastanApp -destination 'platform=macOS'
xcodebuild test -project KastanApp/KastanApp.xcodeproj -scheme KastanApp -destination 'platform=macOS'
```

The app target is sandboxed and permits outgoing network connections for IDOS. Calendar files are written to a temporary app directory before macOS opens them.

## 🌰 MCP Server

The repository includes a native `kastan-mcp` server that lets MCP clients query the Kaštan library directly over standard input and output. It uses the official Swift MCP SDK and exposes read-only tools; it does not parse or invoke the `kastan` CLI.

The MCP server requires macOS 13 or newer, or Linux. It lives in a separate Swift package so the main CLI and library retain their macOS 12 and Windows support.

Build a release executable and print its directory:

```sh
swift build --package-path MCPServer -c release
swift build --package-path MCPServer -c release --show-bin-path
```

Configure an MCP client to launch the `kastan-mcp` executable from that directory. MCP client configuration formats differ, but clients that use a JSON server map commonly accept an entry shaped like this:

```json
{
  "mcpServers": {
    "kastan": {
      "command": "/absolute/path/to/kastan-mcp"
    }
  }
}
```

The server exposes these tools:

| Tool | Purpose |
| --- | --- |
| `suggest_places` | Suggest stops, addresses, and other IDOS places by prefix. |
| `search_stations` | Search only stations and stops by prefix. |
| `find_connections` | Find connections with timetable, date, time, arrival, direct, via, and transfer options. |
| `find_departures` | Find station departures or arrivals. |
| `get_service_detail` | Load a service's complete route and localized information from its opaque ID. |
| `list_timetables` | List accepted timetable slugs and English names. |

Query tools accept an optional `timetable` alias, English catalog name, or IDOS URL slug. `get_service_detail` reads the timetable from current service IDs and accepts `timetable` only as context for legacy IDs. Its optional `language` argument selects English (`en`, the default) or Czech (`cs`) names, notes, and information supplied by IDOS. Tools return the library's JSON model both as readable JSON text and as MCP structured content, and every tool advertises the matching output schema. Result limits default to 8 for suggestions, stations, and departures, and 5 for connections; an MCP request can raise a limit up to 20.

As with the CLI, MCP queries use publicly reachable IDOS web endpoints and are intended for low-frequency personal use.

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
    minimumTransferTime: 10,
    resultLimit: 8
)
let connections = try await client.findConnections(request: request)
let calendar = try await client.connectionCalendar(for: connections[0], timetable: timetable)
let stations = try await client.searchStations(prefix: "Svinov", timetable: timetable)

let departuresRequest = IDOSDeparturesRequest(
    timetable: timetable,
    station: "Ostrava,Hrabůvka,Benzina",
    time: "16:00"
)
let departures = try await client.findDepartures(request: departuresRequest)
let service = try await client.serviceDetail(id: departures[0].id, language: .czech)

let aliasFile = StopAliasFile()
var aliases = try aliasFile.load()
try aliases.upsert(StopAlias(name: "work", station: "Ostrava,Hrabůvka,Benzina", timetable: timetable))
try aliasFile.save(aliases)
```

The public API includes `IDOSClient`, `IDOSClienting`, `IDOSConnectionRequest`, `IDOSDeparturesRequest`, `IDOSTimetable`, `IDOSSuggestion`, `IDOSConnection`, `IDOSConnectionLeg`, `IDOSDeparture`, `IDOSServiceDetail`, `IDOSServiceStop`, `IDOSTransportMode`, `StopAlias`, `StopAliasDatabase`, `StopAliasFile`, `StopAliasError`, and `IDOSError`.

## 🌰 Development

```sh
swift build
swift test
swift run kastan
swift test --package-path MCPServer
```
