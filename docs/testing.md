# Testing Kaštan

[Documentation index](README.md) · [Project overview](../README.md)

Kaštan separates deterministic tests from checks that depend on the public IDOS service. The regular suite uses
local fixtures and test doubles, so it remains suitable for development and pull-request validation:

```sh
make test
```

## Live IDOS contract tests

Run the opt-in smoke suite when you need to verify that Kaštan still communicates with and parses the current IDOS
service:

```sh
make test-live-idos
```

Without Make, select the same suite directly:

```sh
KASTAN_RUN_LIVE_IDOS_TESTS=1 swift test --filter IDOSLiveTests
```

The suite sends read-only requests to `https://idos.cz` through the public `IDOSDataSource` library API. It checks
the published timetable-validity form, both browser autocomplete variants, connection results, departure boards,
service details, and Station Timetable line, stop, and result parsing. It also reads the current advanced connection
form and verifies that Kaštan sends the same published transport-mode controls, inverted checkbox values, default
select values, and hidden form state as the browser. The client negotiates and validates browser-equivalent HTML or
JavaScript response media types, so a changed response representation fails explicitly instead of reaching a parser
as unrelated data. Kaštan keeps its own identifying user agent instead of impersonating Safari, so a differential
request checks that IDOS returns identical autocomplete data, media type, and advanced-form contract to both user
agents. Search dates are generated at runtime, and Station Timetable terminals come from the live line suggestions
instead of being hard-coded.

Live tests are skipped unless `KASTAN_RUN_LIVE_IDOS_TESTS=1` is set. They are intentionally not part of `make test`:
an internet outage, temporary IDOS failure, or live timetable-data gap should not make the deterministic suite fail.
A failure in the live suite means either the service is temporarily unavailable or its contract no longer matches
Kaštan; rerun the suite before changing the integration.

The **Live IDOS contract** GitHub Actions workflow runs the same command every day and also supports a manual
`workflow_dispatch` run. No credential is required, and the suite never invokes IDOS email delivery or another
state-changing operation.
