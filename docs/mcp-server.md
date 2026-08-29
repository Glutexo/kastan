# Kaštan MCP Server

[← Documentation](README.md)

The `kastan-mcp` executable gives local and remote MCP clients read-only access to Kaštan's IDOS searches. It
uses the official Swift MCP SDK and supports local standard input and output or authenticated Streamable HTTP.
Neither transport exposes tools that change remote or local data.

## Requirements and Building

Users with Docker can run the prebuilt AMD64 or ARM64 Linux image instead of installing Swift. The
[container guide](containers.md#mcp-image) provides the complete `docker run` client configuration and image-tag
policy.

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

## Local stdio Configuration

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

## Remote Streamable HTTP

HTTP mode exposes a stateless MCP endpoint at `/mcp` and an unauthenticated liveness endpoint at `/health`.
Kaštan returns one JSON response for each MCP POST request and returns HTTP 405 for `GET /mcp`; it does not hold
an SSE stream or send server-initiated messages. This makes the server suitable for request-based container
platforms while retaining all tools and structured results from stdio mode.

For a local HTTP smoke test, generate a private token and bind the server only to localhost:

```sh
export KASTAN_MCP_BEARER_TOKEN="$(openssl rand -hex 32)"
swift run --package-path MCPServer kastan-mcp \
  --transport http \
  --host 127.0.0.1 \
  --port 8080
```

This default `static` authorization mode requires `Authorization: Bearer <token>` on every `/mcp` request. Tokens
must contain at least 32 non-whitespace bytes. It is useful for local development and controlled migrations, but
OAuth is the recommended mode for an internet-facing MCP server because compatible clients can discover the
authorization server and open an interactive sign-in flow.

Remote MCP client configurations commonly use this shape:

```json
{
  "mcpServers": {
    "kastan": {
      "url": "https://example.run.app/mcp",
      "headers": {
        "Authorization": "Bearer <private-token>"
      }
    }
  }
}
```

The exact syntax for secret or environment-variable interpolation depends on the client. Do not commit the token
inside a client configuration file.

An OAuth deployment normally needs only its MCP URL in the client:

```json
{
  "mcpServers": {
    "kastan": {
      "url": "https://example.run.app/mcp"
    }
  }
}
```

On the first request, Kaštan returns a Bearer challenge pointing to its public RFC 9728 metadata. The client then
discovers the configured authorization server, runs Authorization Code with PKCE, and sends the resulting access
token on subsequent requests. Kaštan validates the RS256 signature from the configured JWKS, exact issuer, exact
resource audience, expiry, not-before time, nonempty subject, and every configured scope. It never needs an OAuth
client secret.

`KASTAN_MCP_AUTH_MODE` controls the accepted credentials:

- `static` is the backward-compatible default and accepts only `KASTAN_MCP_BEARER_TOKEN`.
- `hybrid` accepts either the static token or a valid OAuth access token. Use it only while migrating clients.
- `oauth` accepts only OAuth access tokens and does not read the static token.

Hybrid and OAuth modes expose `/.well-known/oauth-protected-resource` and the path-specific
`/.well-known/oauth-protected-resource/mcp`. They also proxy and cache the authorization server's public
`/.well-known/oauth-authorization-server` document for older MCP clients. The protected-resource document,
authorization-server metadata, and `/health` are public; `/mcp` remains protected.

HTTP configuration is available through these English command-line options and environment variables:

| Setting | Default | Behavior |
| --- | --- | --- |
| `--transport stdio\|http` / `KASTAN_MCP_TRANSPORT` | `stdio` | Selects the local or remote transport. |
| `--host` / `KASTAN_MCP_HOST` | `127.0.0.1` | Selects the HTTP bind address; Cloud Run requires `0.0.0.0`. |
| `--port` / `KASTAN_MCP_PORT` / `PORT` | `8080` | Selects the listener port in precedence order; Cloud Run supplies `PORT`. |
| `KASTAN_MCP_AUTH_MODE` | `static` | Accepts `static`, `hybrid`, or `oauth` credentials. |
| `KASTAN_MCP_BEARER_TOKEN` | required in `static` and `hybrid` | Supplies the pre-shared Bearer credential; ignored by `oauth`. |
| `KASTAN_MCP_OAUTH_ISSUER` | required in `hybrid` and `oauth` | Supplies the exact HTTPS issuer URL expected in access tokens. |
| `KASTAN_MCP_OAUTH_RESOURCE` | required in `hybrid` and `oauth` | Supplies the exact public HTTPS resource URL; its path must be `/mcp`. |
| `KASTAN_MCP_OAUTH_JWKS_URL` | `<issuer>/oauth2/jwks` | Overrides the HTTPS public-key endpoint when the provider uses another path. |
| `KASTAN_MCP_OAUTH_REQUIRED_SCOPES` | none | Requires every listed OAuth scope; accepts comma- or space-separated values. |
| `KASTAN_MCP_ALLOWED_ORIGINS` | none | Allows exact comma-separated HTTP origins; requests without `Origin` remain valid. |
| `--requests-per-minute` / `KASTAN_MCP_REQUESTS_PER_MINUTE` | `60` | Caps all authenticated `/mcp` requests in one process. |

Wildcard origins are rejected. An unlisted `Origin` receives HTTP 403. Missing, expired, incorrectly signed, or
misaddressed credentials receive 401 with the appropriate challenge; a valid token missing a required scope
receives 403 with `insufficient_scope`. An exhausted request window receives 429 with `Retry-After`, and request
bodies larger than 1 MiB receive 413. JWKS and compatibility discovery responses are bounded to 1 MiB, fetched
only over the configured HTTPS URLs, and cached; verification fails closed when keys are unavailable.

The [WorkOS OAuth guide](workos-oauth.md) documents AuthKit setup and safe migration from a static token. The
[Cloud Run guide](cloud-run.md) provides the complete hosted deployment.

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
The two Station Timetable suggestion tools also accept `municipality`; use the same value for both calls and the
final Station Timetable request when searching ODIS.

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
Returned legs include the opaque service IDs accepted by `get_service_detail` and any ordered service-information
items printed in the result, each with its complete IDOS text and classified category.

### Departures and Arrivals

`find_departures` accepts `timetable`, `date`, and `time` with the same meaning and format as connection searches.
Set `isArrival` to `true` for arrivals; the default is departures. `limit` defaults to 8 and accepts values from
1 through 20. Each returned row likewise includes the service-information text and category when IDOS supplies
compact facilities or restrictions beside the service.

### Station Timetables

Use `search_station_timetable_lines` and `search_station_timetable_stops` to obtain an unambiguous line and its
stops before calling `find_station_timetable`. In the final call, `from` is the stop whose departures are displayed
and `to` selects the line direction. The optional arguments are:

- `timetable` selects an MHD or integrated-transport catalog.
- `municipality` selects a local catalog inside ODIS. It accepts a displayed name or short IDOS identifier and
  defaults to Ostrava when omitted.
- `date` uses the IDOS `d.M.yyyy` format and defaults to the current date.
- `wholeWeek` returns schedules for the whole week when `true`.
- `language` selects `en` or `cs` for IDOS text and defaults to English.

The result includes the complete route, minute offsets, tariff zones, platforms or stands, departures grouped by
service day and hour, lockout state, keyed `explanations` for markers used beside concrete departures, general
`notes`, and the matching IDOS URL.
Both suggestion results and the final request and result retain the resolved municipality as structured data.
ODIS offers Bruntál, Český Těšín, Frýdek-Místek, Havířov, Karviná, Krnov, Nový Jičín, Opava,
Orlová, Ostrava, Studénka, and Třinec. A municipality supplied for another timetable is rejected before IDOS
is called.

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
