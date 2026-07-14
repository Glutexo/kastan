# 🌰 Kaštan

Kaštan (`kastan`) is a personal Swift CLI and importable Swift library for occasional one-off IDOS queries.
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

Line names in connection output use the same terminal color as IDOS sends in the HTML result.
Connection legs also include transport emoji such as 🚆 for trains and 🚌 for buses when IDOS exposes the transport type.
Connection and departure times are bold in text and markdown output.
Use `--verbose` to show IDOS tariff zones, platforms, carriers, and current delay information when IDOS includes them.
Departure headings use the station name resolved by IDOS, not necessarily the exact query text.
When a connection place, departure station, or alias station is not an exact match and IDOS returns multiple candidates, Kaštan reports the ambiguous name and lists the possible IDOS choices.

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
swift run kastan timetables --format json
swift run kastan aliases list --format json
```

Common options also have short switches: `-f` (`--from`), `-t` (`--to`), `-s` (`--station`), `-T` (`--timetable`), `-d` (`--date`), `-m` (`--time`), `-a` (`--arrival`), `-p` (`--departure`), `-V` (`--via`), `-x` (`--direct`), `-c` (`--add-to-calendar`), `-v` (`--verbose`), `-X` (`--max-transfers`), `-M` (`--min-transfer-time`), `-o` (`--format`), and `-l` (`--limit`).
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

let aliasFile = StopAliasFile()
var aliases = try aliasFile.load()
try aliases.upsert(StopAlias(name: "work", station: "Ostrava,Hrabůvka,Benzina", timetable: timetable))
try aliasFile.save(aliases)
```

The public API includes `IDOSClient`, `IDOSClienting`, `IDOSConnectionRequest`, `IDOSDeparturesRequest`, `IDOSTimetable`, `IDOSSuggestion`, `IDOSConnection`, `IDOSConnectionLeg`, `IDOSDeparture`, `IDOSTransportMode`, `StopAlias`, `StopAliasDatabase`, `StopAliasFile`, `StopAliasError`, and `IDOSError`.

## 🌰 Development

```sh
swift build
swift test
swift run kastan
```
