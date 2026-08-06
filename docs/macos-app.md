# Kaštan for macOS

[← Documentation](README.md)

Kaštan includes a native SwiftUI application for macOS 13 or newer. It imports the `Kastan` library directly,
so its IDOS requests and parsed models stay aligned with the CLI and MCP server.

## Features

- Connection searches with full-row selectable place suggestions whose icons distinguish municipalities from
  stations and stops. Suggestion metadata, including foreign country names, follows the app language.
  Choosing a suggestion also preserves its exact IDOS identity, so a station is not broadened to a same-named
  municipality. The selected field marks that identity with a subdued localized type such as municipality,
  train, or bus, clipped to the input when space is limited; editing the field removes the marker and returns it
  to a free-text search. Holding Option reveals compact field shortcuts: Here beside From and To requests the Mac's
  current location only when clicked and fills that endpoint with IDOS's exact My location object. Typing the exact
  localized My location phrase into either field does the same when the search starts. A single compact journey-time
  control replaces the separate date, time, and Departure/Arrival controls. It sits beneath a Date and time heading at
  the trailing edge of the timetable row and shows the selected mode followed by one space and either lowercase now or
  the localized date and time. Holding Option reveals a compact Now action beside that heading. The content-sized
  popover itself contains only the heading-free time-mode selector and native date and time editors and dismisses when
  focus moves outside it. Until either value is edited or a search is submitted, the launch default follows the current
  moment when the form appears, the app becomes active, and immediately before searching, so an app left open overnight
  does not silently query yesterday. Station-board searches use the same current-moment behavior and compact editor,
  with their Departures/Arrivals mode visible when the popover is closed. The Edit menu contains a Fill Current submenu
  with From Place and To Place above a separator, followed by Date and time, Date, and Time. A separate neighboring
  Swap From and To command handles route reversal without presenting it as a current value. This search-command group
  is visually separated from the native Select All command. Both search commands reveal a collapsed active search
  before applying an action; Connections support every current value and swapping, Departures support the three temporal
  values, and Station Timetables support Date and swapping while unsupported commands stay visibly disabled. Searches also
  support arrival mode and an extensible journey-options builder modeled after native macOS rule editors. Selecting
  the same exact departure and arrival shows inline guidance and disables Search before any IDOS request can start.
  Connections and Station Timetables share the same borderless 24-point direction-swap control between their fields.
  Each condition first selects either Via or Maximum number of transfers, then presents the corresponding text
  or compact, left-aligned number field with native stepper arrows. Both editors share one row height and follow the
  condition menu sized from the longest supported localized option at standard control spacing; fixed-size controls
  add and remove rows while summaries retain locale-aware transfer wording. Departure/Arrival remains visible on the
  compact journey editor. The journey-options heading shares one level with Search. Expanding it or holding Option
  reveals the Direct connections only checkbox beside the heading; after the user first toggles that checkbox, it stays
  visible for the lifetime of that search window even without Option, after collapsing the options, and after clearing
  it again. Expanded full-width conditions appear below without moving the action row. Either the arrow or heading
  toggles the conditions. Selecting the checkbox adds a zero-transfer condition or updates the existing transfer limit;
  clearing it removes that condition.
- Station departures and arrivals with station-only suggestions that retain the selected station or stop identity.
- MHD station timetables with line and direction suggestions, single-day or whole-week schedules, selectable
  route stops, optional tariff zones and platforms or stands, lockout labels, keyed departure explanations,
  timetable-wide notes, and links back to the matching IDOS result. Schedule headings keep the numeric date and
  follow the selected language's weekday capitalization, such as lowercase Czech `středa` and uppercase English
  `Wednesday`. The route, explanations, and notes use icon headings. Route stops use the same connected circular
  timeline as complete service routes. Its neutral section
  leads into an accent-colored continuation from
  the selected stop through the final stop, with centered marks at the route endpoints and selection. Selection
  accents do not dim the stop content: optional metadata and expanded notes retain the same adaptive secondary color,
  including on the selected row. Explanations such as `A: …` are separated only when their key occurs beside a
  concrete departure. Each marker appears as smaller secondary information attached to its minute and reveals the
  matching explanation on hover. Explanations also appear in their own collapsed disclosure immediately below the
  timetable, while general notes remain in a separate collapsed disclosure at the very bottom of the complete result
  in both wide and compact layouts. Both expand into selectable text while retaining their interactive links. At
  readable widths, route stops and the selected stop's timetable each receive exactly half of the available result
  width. When two readable columns no longer fit, a Stops/Timetable switch appears between the route heading and its
  content and displays one section at a time instead of stacking the timetable below the stops.
  Schedule tables expand evenly within their half and fall back to horizontal scrolling only when their readable
  minimum widths no longer fit. A direction that
  wraps across lines remains vertically centered beside the line name, while single-line headings retain baseline
  alignment. Notes saying that a service skips listed stops use the route symbol instead of a generic information
  marker. Expanded stop-note text shares the leading edge of the stop name and optional metadata. Common stop
  properties appear directly after the stop name as semantic emoji: request
  stops use 🔔, wheelchair accessibility uses ♿, rail stations use 🚉, Metro transfers use 🚇, and traffic
  restrictions use 🚧. Hovering a symbol reveals the original IDOS note, VoiceOver reads that note, and unrecognized
  operational notes retain their complete text. Their service date uses the same compact popover treatment as the
  other search modes while
  exposing only the date supported by IDOS; its fixed caption height keeps the search header's top inset aligned with
  the other modes. Whole week lives in that popover and remains visible in the closed control.
  Dated service notes such as a connection that runs or does not run on listed dates, or
  runs through a named date such as `3.XII.`, open an operating calendar. Working-day rules compose with dated
  exceptions and exclude weekends and Czech public holidays, while numbered weekday rules such as `v 6,7`
  or `v 1-6` restrict a dated operating range to the selected weekdays. The IDOS `+` symbol adds Sundays and Czech
  public holidays, so `v 6,+` means Saturdays, Sundays, and public holidays. An operating-day clause after a dated
  non-running range likewise restricts only that exclusion. Positive and negative dated exceptions then override
  the recurring rule. One-sided boundaries such as `od 2.X.` extend to the corresponding timetable-validity edge
  even when combined with other listed dates. The calendar marks running and non-running days only within the
  validity interval printed by IDOS for the current timetable; days outside that interval remain visibly out of scope.
  Notes whose subject applies only on numbered weekdays, such as refreshments `v 1-5,7`, open a separate note
  calendar whose legend says whether the note applies instead of implying that the service itself runs. Only the
  numbered-weekday clause is linked in these notes; notes describing whether a service runs remain linked in full.
  Web addresses and phone numbers in timetable notes, service information, and route-stop notes open as links.
- A genuine AppKit toolbar centers a complete mode control for switching between Connections, Departures, and
  Station Timetables while preserving each search's state. Stable toolbar identifiers and visibility priorities
  keep that control intact, and its natural width follows the localized labels without stretching the final
  segment. macOS moves secondary actions into its native overflow menu when a compact window cannot show them
  directly. The same actions remain available from the app menus. Search-mode commands stay in View, while
  Favorite timetables belongs to Window and remains available from every app window. These actions open the
  timetable-favorites manager and app information in their own windows, with concise labels that name their content.
- Timetable menus grouped into general rail and bus choices, integrated transport systems, and city networks,
  with Trains selected initially in every search mode. Station Timetables offer that shared rail default together
  with integrated systems and city networks while omitting unsupported broad combinations such as All timetables.
  Persistent favorites repeat in their own first section without disappearing from the catalog, and the favorite
  button stays consistently close to its picker across all three search modes without overlapping it, with the
  standard wider separation retained in the wide search layout.
  Right-clicking that star opens a single Favorite timetables command, marked with a star icon, for the complete
  favorites manager.
  Every editable search presents this timetable choice first, above its route or station fields, so the transport
  context is visible as part of the basic query before any place is entered.
- Search forms stay only as tall as their current controls above independently scrollable result areas, with matching
  visible insets for their leading controls and an equally wide trailing Search action in all three modes, then collapse
  into low query summaries after
  submission with an explicit action for returning to the editable form. A main window without a saved size defaults
  to a compact 522-point width without moving the connection or station-board time mode below the date and time
  controls or clipping fields and actions at the window edge. macOS restores the last user-selected supported size
  thereafter; a legacy saved width below 522 points expands to that minimum when its window opens.
- Submitting changed connection criteria replaces the previous result list with a progress indicator until the
  fresh response arrives. A completed search without matches shows dedicated no-results guidance instead of retaining
  the initial instruction to start a search. Connection and station-board paging still extends results chronologically
  without replacement: pulling past the top loads earlier results, while pulling past the bottom loads the following
  results and removes duplicate rows. If connection paging fails after its IDOS session expires, the error banner
  can repeat the unchanged search, replace the stale list with progress, and establish a fresh paging session.
- Native tabs and windows, including independent favorite-timetable, complete-connection, and resizable
  service-route windows. A connection opened in its own window presents its email, export, and sharing actions as
  individually visible controls in the native toolbar instead of repeating the result-card action menu, and
  each of its services can still open a separate complete route. The active connection or service detail repeats
  every toolbar action in the File menu, with all commands disabled while an export or Mail draft is being prepared
  and email disabled until IDOS supplies a permanent link. Complete connections and service routes both open at their
  compact 400-point minimum. When scrolling hides the connection's main time range, that range moves into the window
  title until its content label is visible again.
- Connection cards, complete connections, and complete service routes share their permanent link by default.
  Holding Option changes that same action to Share Text. The shared text follows the app language and the CLI's
  default human-readable layout, including its semantic emoji and the complete route for a service, while omitting
  terminal-only ANSI color and emphasis codes. Share Text remains available when IDOS does not supply a permanent
  result link.
- Connection cards and complete connections offer Send by Email when IDOS supplies the data needed for that result.
  Activating it normally opens a confirmation sheet with IDOS's localized default message and generated PDF and
  calendar attachment names, extends the IDOS website attribution with Kaštan's GitHub project URL, and keeps the
  complete message editable. Holding Option while activating Send by Email bypasses that sheet and opens an unsent
  draft directly in Mail, with IDOS's localized description as its subject, the same credited message followed by a
  rich HTML summary of the selected connection, and both generated attachments. The summary follows the app language
  and the CLI HTML layout, including semantic transport symbols, emphasized times, and IDOS line colors. Its route
  metadata uses aligned labels and values, and the complete draft keeps one system typeface while retaining the visual
  hierarchy; Mail leaves the recipient for the passenger to enter. Inside Kaštan's sheet, each attachment
  opens independently in the default macOS application when selected, without sending the email. Holding Option there
  changes the attachment rows to Download; selecting one then saves it through the native macOS save panel instead of
  opening it. The sheet accepts one or more recipient addresses separated by commas or semicolons. Kaštan sends the
  address list and message to IDOS only after explicit confirmation and does not retain them after the sheet closes.
  IDOS generates and delivers the in-app attachments; delivery and attachment errors stay in the sheet for retry.
- The View menu's Show connection badges setting is off initially, applies to every app window, and persists across
  launches. When enabled, connection cards use semantic emoji to mark direct journeys and every connection tied for
  the shortest displayed duration; complete-connection windows follow the same setting. Badge text never wraps or
  forces the connection time and duration onto extra lines: each badge collapses to its semantic emoji when the
  complete localized title does not fit, and hovering that compact badge reveals the title. The neighboring Show item
  details setting is likewise off initially, global, and persistent. Enabling it reveals carriers and localized Czech
  or English IDOS punctuality states, including live delay minute counts. Connection-service rows always show their
  departure platform beside the service symbols as a compact source value such as `1`; hovering it or using VoiceOver
  reveals localized wording such as `platform 1`. A railway pair remains compact as `2/3`, while its hover and
  VoiceOver wording expands to `platform 2, track 3`, so the two numbers remain unambiguous. Slash-containing platform
  or stand identifiers on other transport modes remain unchanged. Connection rows omit tariff zones, which the compact
  summary cannot associate clearly with either endpoint and IDOS does not show in connection results. Station-board
  rows still reveal via descriptions, station-scoped
  tariff zones, and platforms or stands. Both row types always preserve the passenger facilities and restrictions
  printed beside a service by IDOS. They show semantic emoji by default, expose the complete wording to VoiceOver and
  on hover, and Option-clicking an emoji opens a selectable popover with the exact phrase, regular-expression, or
  structural classifier rule that matched the IDOS wording. The concise popover neither repeats that wording nor
  substitutes the resulting category name or emoji for the rule. The global, persistent Replace symbols with text
  setting replaces those service symbols and recognized
  stop-note emoji with the complete wording supplied by IDOS; the setting is off initially. It applies equally to
  connection results, station boards, station timetables, complete result windows, and Force Click previews. Station
  timetables, complete service windows, and previews continue to show tariff zones, platforms, tracks, and distances
  beside concrete stops. With item details enabled and symbols retained, zones and stop positions move directly after
  the stop name and emoji as smaller secondary values such as `50,51` and `2/3`; hovering or VoiceOver expands them
  to localized wording such
  as two individually listed zones or `platform 2, track 3`. Replacing symbols with text instead keeps that expanded
  wording below the stop name, while distances remain below it in either form. Hovering a
  compact stop-note emoji shows the original IDOS note. Option-clicking that emoji opens a selectable popover with
  only the exact phrase-matching rule that selected the emoji, without repeating the note.
  Complete-route markers remain centered beside each stop title whether optional metadata is visible or hidden.
  Stop-note meaning remains visible independently of the item-details choice and the selected symbol-or-text form.
  Show alternating row backgrounds is another global, persistent setting and is enabled initially. Its subtle adaptive
  bands distinguish neighboring station-board rows, connection-service rows, complete and station-timetable route
  stops, and station-timetable hour rows. Turning it off restores uniform data-row backgrounds without changing cards,
  search forms, suggestions, or the native favorite-timetable list. Complete-route bands keep balanced vertical space
  around each stop and inset the timeline, stop content, and time from their horizontal edges.
  Complete service information is independent of the compact row setting and starts collapsed beneath its own
  route-level disclosure heading.
  Cards always retain line colors and transport symbols. Right-clicking anywhere on a connection card
  opens the same complete action menu as its ellipsis button, with Open connection in new window ahead of email,
  calendar, PDF, sharing, and IDOS actions. Right-clicking a particular service row stays scoped to that service and
  offers its own preview and new-window actions followed by calendar, PDF, sharing, and IDOS actions rather
  than falling through to the enclosing connection. All available detail actions are selectable on the first menu opening;
  the chosen action loads the complete service data only when needed and then continues automatically. The same
  service-specific menu is available on station-board rows. A trackpad Force Click on either kind of service row
  opens the identical complete-route preview. Double-clicking anywhere across a connection's time or route summary
  opens that complete connection in an independent window; holding Option reveals the window button in the connection
  header as an alternative. An ordinary service click opens the selected service's detail window, including while
  another service-detail window is already open.
- Long service routes in independent windows and Force Click previews initially bring the departure stop from the
  originating search toward the top. The window leaves a safe clearance below its toolbar, while the preview leaves
  slightly more against its rounded edge. The scroll position is limited by the route's real end: a departure near
  the final stop remains lower when there is not enough following content, with no artificial trailing space. When
  the departure is already the first stop or the complete route fits in the viewport, the natural position is
  preserved. The search-relevant segment remains highlighted without implying live vehicle position. When scrolling hides a
  service date, the date moves into the window title until its content label is visible again.
- Complete service information starts collapsed beneath a disclosure heading at the same level as Stops. Expanding it
  reveals selectable text whose visibly separated rows use semantic emoji for replacement buses,
  onboard amenities, sleeping and couchette cars, through coaches, on-route train-designation changes,
  first-class availability and second-class-only restrictions, self-service passenger handling, accessibility,
  family and bicycle services,
  tickets, baggage, passenger and reservation restrictions, cancellation policies, routes including skipped-stop
  instructions, carriers, and calendar-backed operating rules.
  Carrier contact rows use their `name; address[; phone]`
  structure instead of an operator-name list. Dining and bistro cars are visually distinct from lighter
  refreshment trolley or vending-machine service, while tickets accepted from integrated transport systems
  are distinct from carrier fares and broader fare conditions. A single selection can span multiple rows while
  retaining clickable web-address and phone-number links and the standard macOS copy command. Each leading semantic
  emoji is an Option-click target for the same classifier popover used by compact service summaries. The popover opens
  beside the selected emoji instead of attaching to the edge of the complete text flow. Dated operating
  exceptions, including abbreviated ranges such as `17. to 20.VIII.` and
  same-month lists such as `18.,19.IX.`, open the same running/non-running calendar using the exact validity
  interval published by the current IDOS timetable. When opened, the calendar scrolls to the current month or
  to the nearest month covered by that timetable. Option-clicking a calendar note also lists the operating rule
  or note-applicability rule and every individual date or range recognized from it.
- Permanent connection and service-detail links using the IDOS language that matches the app, shared through
  the standard macOS picker. Alongside the system sharing services, that picker offers Open in IDOS without a
  redundant standalone result action. Every service-detail action is an individually visible control in that
  window's native toolbar.
- Localized IDOS calendar and PDF exports matching the app language for connection results and dated service
  details. Add to Calendar opens the generated event in the user's calendar application from result menus, service
  menus, detail toolbars, and the File menu. Holding Option changes that action everywhere to Download ICS File and
  saves the same calendar through the native macOS save panel. Open PDF in Preview opens the generated document in
  Apple's Preview application from the same locations. Holding Option changes that action everywhere to Download PDF
  File and saves the document through its own native panel.
- English and Czech interface localization.
- An app-information window describing the data source and linking to IDOS, its terms, and the Kaštan repository.
- A Help menu that repeats the About window's maintained links to IDOS, its terms, and the Kaštan repository
  instead of showing an unavailable system help book.

## Run from Xcode

The project requires Xcode with Swift 6.3 or newer. Open the shared project and run the `KastanApp` scheme:

```sh
open KastanApp/KastanApp.xcodeproj
```

## Build and Test from Terminal

```sh
xcodebuild build \
  -project KastanApp/KastanApp.xcodeproj \
  -scheme KastanApp \
  -destination 'platform=macOS'

xcodebuild test \
  -project KastanApp/KastanApp.xcodeproj \
  -scheme KastanApp \
  -destination 'platform=macOS'
```

## Create Download Archives

Create both download archives from the repository root, or select either artifact separately:

```sh
make
make dmg
make source-zip
```

Plain `make` is equivalent to `make dist` and creates both downloads. The artifact names use the app's current
marketing version and are written to `dist/`. For version `0.1.0`,
`make dmg` creates `kastan-0.1.0-macos.dmg` with a Release build of `Kaštan.app` for both Apple Silicon and Intel
Macs. The image also contains an Applications shortcut. Xcode gives this local build an ad-hoc signature that
preserves the app sandbox and hardened runtime, but it is not signed with an Apple Developer ID or notarized.
Gatekeeper can therefore require the user to explicitly approve the first launch; a seamless public download
requires a Developer ID certificate and Apple notarization outside this workflow.

`make source-zip` creates `kastan-0.1.0-source.zip` from the current Git `HEAD`. The archive has a top-level
`kastan-0.1.0/` directory and contains the tracked, buildable sources and documentation for every Kaštan interface.
It intentionally excludes uncommitted changes, Git metadata, dependency caches, and build or distribution artifacts.
To keep the two downloads aligned, `make dist` requires a clean Git worktree before it creates either artifact.
The individual `make dmg` target can still package an app with local changes during development.

The app target is sandboxed and permits outgoing network connections for IDOS. Location access is requested only
after the user clicks a Here shortcut or searches with the exact localized My location phrase. The first request
opens the localized macOS permission prompt, and the decision can later be changed in System Settings. Calendar and
PDF files, including attachments passed to Mail, are written to a temporary app directory before macOS opens them;
downloaded PDF and ICS files and downloaded email attachments can be written only to a location explicitly selected
by the user.

## Data Source

The app uses publicly reachable IDOS web endpoints and parses returned HTML. It is intended for occasional
personal searches and does not present IDOS data as a stable API or live vehicle tracking service.
