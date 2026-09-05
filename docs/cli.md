# Kaštan CLI

[← Documentation](README.md)

The `kastan` executable provides personal, low-frequency IDOS queries from a terminal. It supports macOS,
Windows, and Linux, with the exception of direct calendar opening, which is available only on macOS.

## Requirements and Building

A prebuilt AMD64 and ARM64 Linux image is available for users who have Docker but do not need a local Swift
toolchain. The [container guide](containers.md#cli-image) documents direct commands, tags, and persistent aliases.
The source builds below remain the supported route for native macOS, Windows, and Linux executables.

Kaštan requires Git and Swift 6.3 or newer. Download Swift only from the
[official Swift installation page](https://www.swift.org/install/); development snapshots are not required.

### macOS

Install Apple's command-line developer tools if necessary:

```sh
xcode-select --install
```

Install the latest stable Swift release with Swiftly:

```sh
curl -O https://download.swift.org/swiftly/darwin/swiftly.pkg
installer -pkg swiftly.pkg -target CurrentUserHomeDirectory
~/.swiftly/bin/swiftly init --quiet-shell-followup
. "${SWIFTLY_HOME_DIR:-$HOME/.swiftly}/env.sh"
hash -r
```

These commands are also available in the [official macOS instructions](https://www.swift.org/install/macos/).
Clone and build Kaštan after verifying the tools:

```sh
swift --version
git --version
git clone https://github.com/Glutexo/kastan.git
cd kastan
swift build -c release
swift test
"$(swift build -c release --show-bin-path)/kastan" --help
```

The package declares macOS 12 as its minimum deployment target.

### Windows

This installation route requires Windows 10 version 1809 or newer and WinGet. Enable **Developer Mode** in
Windows Settings, then install the Visual Studio C++ toolchain, Windows SDK, and stable Swift toolchain from
PowerShell:

```powershell
winget install --id Microsoft.VisualStudio.2022.Community --exact --force --custom "--add Microsoft.VisualStudio.Component.Windows11SDK.22621 --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.VC.Tools.ARM64" --source winget
winget install --id Swift.Toolchain --exact --source winget
```

See the official [WinGet](https://learn.microsoft.com/en-us/windows/package-manager/winget/),
[Developer Mode](https://learn.microsoft.com/en-us/windows/advanced-settings/developer-mode), and
[Swift for Windows](https://www.swift.org/install/windows/) instructions if a prerequisite is missing. Close
and reopen PowerShell after installation, then build Kaštan:

```powershell
swift --version
git --version
git clone https://github.com/Glutexo/kastan.git
Set-Location kastan
swift build -c release
swift test
$binPath = swift build -c release --show-bin-path
& "$binPath\kastan.exe" --help
```

### Linux

Swiftly supports Ubuntu, Debian, Fedora, Red Hat Enterprise Linux, and Amazon Linux. On Ubuntu or Debian,
install the download and verification tools first:

```sh
sudo apt update
sudo apt install -y curl ca-certificates gnupg tar git
```

Install the latest stable Swift release:

```sh
curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz
tar zxf swiftly-$(uname -m).tar.gz
./swiftly init --quiet-shell-followup
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
hash -r
```

See the [official Linux instructions](https://www.swift.org/install/linux/) for distribution-specific
dependencies, then clone and build Kaštan:

```sh
swift --version
git --version
git clone https://github.com/Glutexo/kastan.git
cd kastan
swift build -c release
swift test
"$(swift build -c release --show-bin-path)/kastan" --help
```

All query, alias, and output-format commands build on all three platforms. On Windows and Linux, use
`--format ics` instead of macOS-only `--add-to-calendar`.

## Commands

Ask the executable for the complete current command reference:

```sh
swift run kastan --help
```

### Places and Stations

Suggest any IDOS place or search stations only:

```sh
swift run kastan suggest Praha
swift run kastan suggest Svinov --timetable ostrava
swift run kastan stations Praha
swift run kastan stations Svinov -T ostrava -l 5
```

### Connections

Search with named options, positional endpoints, or a route expression:

```sh
swift run kastan connections --from Praha --to Brno --date 18.6.2026 --time 12:00
swift run kastan connections --from "Frýdek-Místek" --to Ostrava --timetable odis
swift run kastan connections Praha Brno --time 12:00
swift run kastan connections "Praha → Brno"
swift run kastan Praha→Brno
```

Connection searches support the complete library journey-option contract. For example:

```sh
swift run kastan connections Praha Brno --direct
swift run kastan connections Praha Brno --via Pardubice --via Olomouc
swift run kastan connections Praha Brno --time 15:00 --arrival
swift run kastan connections Praha Brno --max-transfers 0
swift run kastan connections Praha Brno --min-transfer-time -1 --max-transfer-time 360
swift run kastan connections Praha Brno --transport-mode only:regional-train --transport-mode exclude:city-trolleybus
swift run kastan connections Praha Brno --wheelchair-accessible-connections-only true
swift run kastan connections Praha Košice --timetable vlaky --bed-or-couchette-preference use
swift run kastan connections Praha Brno --limit 3
```

Every library option has a stable English CLI spelling:

| CLI option | Value and behavior |
| --- | --- |
| `--direct`, `--only-direct`, `-x` | Flag that returns direct connections only. |
| `--via`, `-V` | Via place; repeat the option to preserve an ordered list. |
| `--transport-mode` | `only:<mode>` or `exclude:<mode>`; repeat it to combine detailed means-of-transport rules. |
| `--max-transfers`, `-X` | Non-negative maximum number of transfers, including zero. |
| `--min-transfer-time`, `-M` | Minimum transfer time in minutes; `-1` selects the timetable standard. |
| `--max-transfer-time` | Non-negative maximum transfer time in minutes. |
| `--max-walking-time` | Non-negative walking-transfer limit in minutes. |
| `--max-city-walking-time` | Separate non-negative walking-transfer limit where Urban Public Transport is available. |
| `--walk-to-nearby-stops` | `true` or `false`; controls walking to a nearby stop at the beginning or end. |
| `--same-name-walking-transfers-only` | `true` or `false`; limits walking transfers to stops with the same name. |
| `--wheelchair-accessible-connections-only` | `true` or `false`; limits results to wheelchair-accessible connections. |
| `--low-floor-connections-only` | `true` or `false`; limits results to low-floor connections. |
| `--prefer-trains-over-buses` | `true` or `false`; prefers trains over bus alternatives. |
| `--train-connections-for-wheelchair-passengers` | `true` or `false`; applies the train-only wheelchair-passenger filter. |
| `--train-connections-for-passengers-with-children` | `true` or `false`; applies the train-only passengers-with-children filter. |
| `--connections-for-passengers-with-bicycles` | `true` or `false`; applies the bicycle filter to trains and buses. |
| `--prefer-busy-routes` | `true` or `false`; prefers routes served more frequently. |
| `--bed-or-couchette-preference` | `no-limitation`, `use`, or `do-not-use`; available only for compatible train timetables. |

Multiple `only` transport-mode rules form a union. Every `exclude` rule is removed from that union, or from the full
catalog when no `only` rule is present. The grouped mode values are:

- Trains: `highest-quality-train`, `higher-quality-train`, `interregional-train`, `regional-train`, `train-bus`,
  `train-ship`, and `train-other`.
- Buses: `local-bus`, `long-distance-bus`, and `international-bus`.
- City transport: `city-tram`, `city-bus`, `city-cableway`, and `city-trolleybus`.

Omitting a value-backed option preserves the IDOS default, while an explicit `false` or `no-limitation` preserves
an active negative or unrestricted condition. IDOS offers Bed / Couchette only for All timetables, Trains + Buses +
Urban Public Transport, Trains, and Trains + Buses. Kaštan rejects it for other timetables before making an IDOS
request.

Kaštan asks IDOS for later connections until the requested limit is reached or no more results are available.

### Departures

Search a station board by departures or arrivals:

```sh
swift run kastan departures --station "Ostrava,Hrabůvka,Benzina" --timetable odis --time 16:00
swift run kastan departures --station "Ostrava,Hrabůvka,Benzina" --timetable odis --arrival
swift run kastan "Ostrava,Hrabůvka,Benzina" --timetable odis --time 16:00
```

### Station Timetables

Search the third IDOS mode, **Station Timetables**, for an MHD or integrated-transport line and direction:

```sh
swift run kastan station-timetables --line 154 --from "Strašnická" --to "Sídliště Libuš" --timetable pid
swift run kastan station-timetables -L "Bus 154" -f "Strašnická" -t "Sídliště Libuš" -T pid -d 17.7.2026
swift run kastan station-timetables -L "Bus 154" -f "Strašnická" -t "Sídliště Libuš" -T pid --whole-week
swift run kastan station-timetables -L "Bus 301" -f "Řepiště,,U kříže" -t "Místek,Riviéra" -T odis -u "Frýdek-Místek"
```

`--from` selects the stop whose departures are displayed, while `--to` selects the line direction. The result
includes the complete route with minute offsets, tariff zones, and platforms or stands, departures grouped by
service day and hour, lockout status, keyed explanations for markers used beside concrete departures, and general
notes. Human-readable output places explanations directly after the schedules and keeps notes at the very bottom.
Platform legends are attached directly to their route stops instead of being repeated as notes.
`station-timetable` is accepted as a singular command alias.
The built-in integrated-system catalog mirrors the current IDOS choices: `pid`, `idsjmk`, `odis`, `idol`, `idsok`,
`iredo`, `duk`, `idpk`, `idzk`, and `ideska`. Select one of these or an MHD catalog for unambiguous line results.
For a catalog with local networks, `--municipality` / `-u` selects the municipality used for line and stop
suggestions. The choices and defaults follow the corresponding IDOS Station Timetable forms:

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

Names are case- and diacritic-insensitive, and short IDOS identifiers such as `FM`, `DvurKral`, `UL`, or `CesBud`
are also accepted. Omitting the option uses the listed IDOS default. Supplying a municipality for a timetable
without that chooser is rejected before a network request.

### Service Details

Load a complete route from an opaque service ID shown by verbose connection or departure output:

```sh
swift run kastan service 'vlaky:0-74552-14.07.2026 20:41:00'
swift run kastan service 'vlaky:0-74552-14.07.2026 20:41:00' --format json
```

Quote the ID because it contains a space. Current IDs contain their timetable; `--timetable` remains available
as context for legacy IDs. Scripts must treat connection-result, service, and departure IDs as opaque values.

Service details include all stops supplied by IDOS, arrival and departure times, tariff zones, platforms or
tracks, distance, stop notes, and service information. Human-readable details mark service metadata and every
information line with a semantic emoji for details such as replacement buses, sleeping and couchette cars,
through coaches, train-designation changes, first-class availability and second-class-only restrictions,
onboard amenities, accessibility including low-floor vehicles, family and bicycle services, tickets, baggage,
passenger and reservation restrictions, cancellation policies, routes including skipped-stop instructions,
carriers, and operating rules;
carrier contact rows are recognized from their `name; address[; phone]` structure rather than operator names.
Dining and bistro cars are visually distinct from lighter refreshment trolley or vending-machine service.
Tickets accepted from integrated transport systems are distinct from carrier fares and broader fare conditions.
Uncategorized information keeps its full text and uses a generic information marker.

## Output Formats

Data and alias commands support `text`, `markdown`, `html`, and `json`; text is the default. HTML output is a
self-contained UTF-8 document with the same localized semantic labels, transport symbols, line colors, and
result details as the other human-readable formats. Redirect it to a file to open the result in a browser or
use it as a rich message body. Connections also support `ics` for the first returned connection. On macOS,
`--add-to-calendar` opens that IDOS calendar file in the system calendar application. Human-readable text in
either calendar form follows the selected CLI language.

```sh
swift run kastan suggest Praha --format json
swift run kastan connections Praha Brno --format markdown
swift run kastan connections Praha Brno --format html > connections.html
swift run kastan connections Praha Brno --verbose
swift run kastan connections Praha Brno --format ics > connection.ics
swift run kastan connections Praha Brno --add-to-calendar
swift run kastan departures --station Praha --format json
swift run kastan station-timetables -L 154 -f "Strašnická" -t "Sídliště Libuš" -T pid --format markdown
swift run kastan timetables --format json
```

Text retains IDOS line colors as ANSI colors. Markdown and HTML retain them as portable inline styles. All
three human-readable formats use transport and status emoji and emphasize times; HTML escapes values received
from IDOS before placing them in the document. Connection headings identify direct and shortest displayed
results. `--verbose` adds IDs, tariff zones, platforms, carriers, and delay information when IDOS supplies
them. Human-readable connection rows use semantic markers for their time summary, identifiers, carrier, delay
status, and transport mode; an unknown transport mode uses a generic route marker. Text output expands a compact
railway value such as `2/3` to localized `platform 2 track 3`, while JSON, Markdown, and HTML retain the original
compact value in their structured fields or table cells. Known Czech and English
IDOS on-time and delayed arrival or departure states follow the selected language in text, Markdown, and HTML,
while JSON exposes the original stable fields without relying on presentation styling. Connection-leg and
station-board JSON also includes each compact IDOS service-information item with its complete text and classified
category when available.

Unknown options are rejected. Network failures are returned as normal command errors in the selected format.
Ambiguous place names are reported together with the possible IDOS choices.

## Common Options

Common short switches are `-f` (`--from`), `-t` (`--to`), `-s` (`--station`), `-L` (`--line`), `-T`
(`--timetable`), `-d` (`--date`), `-m` (`--time`), `-w` (`--whole-week`), `-a` (`--arrival`), `-p`
(`--departure`), `-V` (`--via`), `-x` (`--direct`),
`-c` (`--add-to-calendar`), `-v` (`--verbose`), `-X` (`--max-transfers`), `-M`
(`--min-transfer-time`), `-o` (`--format`), and `-l` (`--limit`).
The remaining connection-search controls are long-only and are listed in [Connections](#connections).

Short flags can be combined. For example, `-vx` is the same as `-v -x`; an option with a value can end the
group, as in `-vxT odis`.

## Language

Human-readable text, Markdown, help, and errors are available in English and Czech. Kaštan selects a supported
system language and falls back to English. Override it with `--language en`, `--language cs`, or `--lang`:

```sh
swift run kastan --language cs --help
swift run kastan connections Praha Brno --lang en
```

Regional identifiers such as `en-US`, `cs-CZ`, and `cs_CZ.UTF-8` are accepted. Command and option names, JSON
keys, and domain values remain language-independent. Human-readable iCalendar text follows the selected language;
other names and status details received from IDOS remain in the form supplied by IDOS.

## Stop Aliases

Store personal station aliases together with their timetable:

```sh
swift run kastan aliases add home --station "Frýdek,Na Veselé" --timetable odis
swift run kastan aliases add work --station "Ostrava,Hrabůvka,Benzina" --timetable odis
swift run kastan aliases list
swift run kastan aliases remove home
swift run kastan aliases path
```

Use aliases anywhere a station or place is accepted:

```sh
swift run kastan connections home→work --time 16:00
swift run kastan departures --station work --time 16:00
```

When all aliases use the same timetable, Kaštan selects it automatically. An explicit `--timetable` must match
every used alias. Each persisted alias remains bound to its data source and stable timetable identifier; Kaštan
refreshes its display name from the active catalog and refuses to send an alias to another source. The default
database is `~/.config/kastan/aliases.json`; set `KASTAN_ALIAS_DATABASE` to use a different JSON file.

## Timetables

The default is `vlakyautobusymhdvse`, called **All timetables** by English IDOS. Select a known alias, English
catalog name, or custom IDOS URL slug with `--timetable`:

```sh
swift run kastan connections Praha Beroun --timetable pid
swift run kastan connections Ostrava "Frýdek-Místek" --timetable odis
swift run kastan timetables
```

The built-in catalog mirrors all 106 standalone Urban Public Transport city catalogs currently published by IDOS,
in addition to the general and integrated-system choices. Prague is represented by `pid` instead of a duplicate
standalone city catalog. Run `timetables` to list every built-in slug and display name.

## Data Source

Select a registered provider by its stable ID with the global `--source` option. Both separated and attached forms
are accepted, and the option may appear before or after the command:

```sh
swift run kastan --source idos connections Praha Beroun
swift run kastan timetables --source=idos
```

When the registry contains one regular provider, `--source` is optional and Kaštan uses that provider by default.
The shipped registry currently has only IDOS as a regular provider, so omitting the option selects `idos`. Once two
or more regular providers are available, every command must select one explicitly. `--help` and `--version` remain
available without a source; provider-neutral help then lists the regular IDs and marks `--source` as required.

Kaštan also ships a deterministic mock source for automated tests. It is deliberately absent from the regular source
list, never becomes the default, and does not make `--source` mandatory while IDOS remains the only regular provider.
Tests can select it explicitly without making a network request:

```sh
swift run kastan --source mock timetables --format json
```

An unknown ID or a missing option value produces a localized error that lists the regular provider IDs.
Every connection-specific option is accepted only when the selected provider advertises the corresponding
`TransitConnectionOption` for the selected timetable; otherwise Kaštan reports a localized error before making a
provider request. The exhaustive CLI-to-library mapping is checked by tests so adding a future library option cannot
silently leave the command-line interface incomplete.

`CommandRunner` depends on the provider-neutral `TransitDataSourceRegistry`, resolves timetables from the selected
provider's catalog, and checks the capability required by a command or native export. This composition boundary lets
a future built-in provider reuse CLI parsing and presentation without imitating IDOS identifiers.
`CommandRunner` itself remains an implementation detail of the executable rather than a public library API.

For compatibility with the existing CLI and its structured output, timetable catalog and alias fields continue to
call the provider-owned timetable identifier a `slug`. A non-IDOS provider can use any value in that field; Kaštan
preserves its display name instead of applying IDOS catalog localization to a coincidentally matching identifier.

Kaštan is intended for low-frequency personal use. Changes to IDOS HTML or its internal JSONP suggestion
endpoint can require parser updates.
