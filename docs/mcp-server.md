# Kaštan MCP Server

[← Documentation](README.md)

The `kastan-mcp` executable gives local MCP clients read-only access to Kaštan's IDOS searches. It communicates
over standard input and output using the official Swift MCP SDK and does not expose any tools that change remote
or local data.

## Requirements and Building

The MCP server requires Git and Swift 6.3 or newer. It supports macOS 13 or newer and Linux. Build and test its
separate Swift package from the repository root:

```sh
swift build --package-path MCPServer -c release
swift test --package-path MCPServer
```

Print the directory containing the resulting `kastan-mcp` executable:

```sh
swift build --package-path MCPServer -c release --show-bin-path
```

## Client Configuration

Configure the MCP client to launch the absolute path of the built executable. Clients that use a JSON server map
commonly accept an entry shaped like this:

```json
{
  "mcpServers": {
    "kastan": {
      "command": "/absolute/path/to/kastan-mcp"
    }
  }
}
```

The client must reserve standard input and output for MCP communication. Kaštan does not require credentials or
environment variables.

## Tools

The server advertises these read-only tools:

| Tool | Required arguments | Behavior |
| --- | --- | --- |
| `suggest_places` | `prefix` | Suggests stops, addresses, municipalities, and other IDOS places. |
| `search_stations` | `prefix` | Searches only stations and stops. |
| `search_station_timetable_lines` | `prefix` | Suggests MHD or integrated-transport lines together with their terminal pairs. |
| `search_station_timetable_stops` | `prefix`, `line` | Suggests stops served by one line returned by the line search. |
| `find_connections` | `from`, `to` | Finds public-transport connections between two places. |
| `find_departures` | `station` | Finds departures or arrivals on a station board. |
| `find_station_timetable` | `line`, `from`, `to` | Loads a Station Timetable for one line, direction, date, and selected stop. |
| `get_service_detail` | `id` | Loads the complete route, stop times, and information for a returned service. |
| `list_timetables` | none | Lists known timetable slugs and their English display names. |

### Place, Station, Line, and Stop Search

The four suggestion tools accept a `timetable` and a `limit` in addition to their required arguments. The default
limit is 8, and callers can request from 1 through 20 results. `search_station_timetable_stops` expects the exact
`line` value returned by `search_station_timetable_lines`, preserving its direction context.

### Connections

`find_connections` accepts these optional arguments:

- `timetable` selects the IDOS catalog.
- `date` uses the IDOS `d.M.yyyy` format; omission lets IDOS use the current date.
- `time` uses the IDOS `H:mm` format; omission lets IDOS use the current time.
- `isArrival` interprets the requested time as arrival rather than departure when `true`.
- `onlyDirect` returns only direct connections when `true`.
- `via` is an ordered array of places through which the connection must travel.
- `maxTransfers` sets a non-negative maximum number of transfers, including zero.
- `minimumTransferTime` sets a non-negative minimum transfer time in minutes.
- `limit` defaults to 5 and accepts values from 1 through 20.

Kaštan asks IDOS for later connections until it reaches the requested limit or no more results are available.
Returned legs include the opaque service IDs accepted by `get_service_detail`.

### Departures and Arrivals

`find_departures` accepts `timetable`, `date`, and `time` with the same meaning and format as connection searches.
Set `isArrival` to `true` for arrivals; the default is departures. `limit` defaults to 8 and accepts values from
1 through 20.

### Station Timetables

Use `search_station_timetable_lines` and `search_station_timetable_stops` to obtain an unambiguous line and its
stops before calling `find_station_timetable`. In the final call, `from` is the stop whose departures are displayed
and `to` selects the line direction. The optional arguments are:

- `timetable` selects an MHD or integrated-transport catalog.
- `date` uses the IDOS `d.M.yyyy` format and defaults to the current date.
- `wholeWeek` returns schedules for the whole week when `true`.
- `language` selects `en` or `cs` for IDOS text and defaults to English.

The result includes the complete route, minute offsets, tariff zones, platforms or stands, departures grouped by
service day and hour, lockout state, explanatory notes, and the matching IDOS URL.

### Service Details

Pass an opaque ID returned by a connection leg or departure to `get_service_detail`; clients must not parse or
construct IDs themselves. Current IDs contain their timetable. The optional `timetable` argument supplies context
for legacy IDs that do not, while `language` selects `en` or `cs` and defaults to English.

Service details include every stop supplied by IDOS, arrival and departure times, tariff zones, platforms or
tracks, distance, stop notes, and service information.

## Timetables

Unless a tool says otherwise, `timetable` accepts a known Kaštan alias, an English IDOS catalog name, or a custom
IDOS URL slug. It defaults to `vlakyautobusymhdvse`, called **All timetables** by English IDOS. Use
`list_timetables` to discover the built-in values. Select an MHD or integrated-system catalog such as `pid`,
`odis`, or `idsjmk` for Station Timetable searches.

## Results and Errors

Every successful tool call returns readable JSON text and the same value as structured MCP content. Each tool
also publishes a matching output schema. Result models preserve semantic IDOS information such as line colors,
transport modes, platforms, tariff zones, carriers, delay details, and localized notes when available.

Invalid, missing, unknown, or out-of-range arguments return an MCP tool error without making an IDOS request.
Network and parsing failures are likewise returned as tool errors.

## Data Source

The server uses publicly reachable IDOS web endpoints and parses HTML and internal JSONP responses through the
shared `Kastan` library. It is intended for low-frequency personal use, not as a stable or guaranteed data API.
