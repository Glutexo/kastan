# Kaštan CLI

[← Project overview](../README.md)

The `kastan` executable provides personal, low-frequency IDOS queries from a terminal. It supports macOS,
Windows, and Linux, with the exception of direct calendar opening, which is available only on macOS.

## Requirements and Building

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

Connection searches support direct journeys, one or more via places, arrival or departure time, maximum
transfers including zero, and a minimum transfer time:

```sh
swift run kastan connections Praha Brno --direct
swift run kastan connections Praha Brno --via Pardubice --via Olomouc
swift run kastan connections Praha Brno --time 15:00 --arrival
swift run kastan connections Praha Brno --max-transfers 0
swift run kastan connections Praha Brno --min-transfer-time 10
swift run kastan connections Praha Brno --limit 3
```

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
```

`--from` selects the stop whose departures are displayed, while `--to` selects the line direction. The result
includes the complete route with minute offsets and tariff zones, departures grouped by service day and hour,
lockout status, and explanatory notes. `station-timetable` is accepted as a singular command alias. Select an
MHD or integrated-system catalog such as `pid`, `odis`, or `idsjmk` for unambiguous line results.

### Service Details

Load a complete route from an opaque service ID shown by verbose connection or departure output:

```sh
swift run kastan service 'vlaky:0-74552-14.07.2026 20:41:00'
swift run kastan service 'vlaky:0-74552-14.07.2026 20:41:00' --format json
```

Quote the ID because it contains a space. Current IDs contain their timetable; `--timetable` remains available
as context for legacy IDs. Scripts must treat connection-result, service, and departure IDs as opaque values.

Service details include all stops supplied by IDOS, arrival and departure times, tariff zones, platforms or
tracks, distance, stop notes, and service information.

## Output Formats

Data and alias commands support `text`, `markdown`, and `json`; text is the default. Connections also support
`ics` for the first returned connection. On macOS, `--add-to-calendar` opens that IDOS calendar file in the
system calendar application.

```sh
swift run kastan suggest Praha --format json
swift run kastan connections Praha Brno --format markdown
swift run kastan connections Praha Brno --verbose
swift run kastan connections Praha Brno --format ics > connection.ics
swift run kastan connections Praha Brno --add-to-calendar
swift run kastan departures --station Praha --format json
swift run kastan station-timetables -L 154 -f "Strašnická" -t "Sídliště Libuš" -T pid --format markdown
swift run kastan timetables --format json
```

Text and Markdown retain IDOS line colors as ANSI colors, use transport and status emoji, and emphasize times.
Connection headings identify direct and shortest displayed results. `--verbose` adds IDs, tariff zones,
platforms, carriers, and delay information when IDOS supplies them. JSON exposes the corresponding stable
fields without relying on terminal styling.

Unknown options are rejected. Network failures are returned as normal command errors in the selected format.
Ambiguous place names are reported together with the possible IDOS choices.

## Common Options

Common short switches are `-f` (`--from`), `-t` (`--to`), `-s` (`--station`), `-L` (`--line`), `-T`
(`--timetable`), `-d` (`--date`), `-m` (`--time`), `-w` (`--whole-week`), `-a` (`--arrival`), `-p`
(`--departure`), `-V` (`--via`), `-x` (`--direct`),
`-c` (`--add-to-calendar`), `-v` (`--verbose`), `-X` (`--max-transfers`), `-M`
(`--min-transfer-time`), `-o` (`--format`), and `-l` (`--limit`).

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
keys and domain values, and iCalendar data remain language-independent. Names and status details received from
IDOS remain in the form supplied by IDOS.

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
every used alias. The default database is `~/.config/kastan/aliases.json`; set `KASTAN_ALIAS_DATABASE` to use a
different JSON file.

## Timetables

The default is `vlakyautobusymhdvse`, called **All timetables** by English IDOS. Select a known alias, English
catalog name, or custom IDOS URL slug with `--timetable`:

```sh
swift run kastan connections Praha Beroun --timetable pid
swift run kastan connections Ostrava "Frýdek-Místek" --timetable odis
swift run kastan timetables
```

Kaštan is intended for low-frequency personal use. Changes to IDOS HTML or its internal JSONP suggestion
endpoint can require parser updates.
