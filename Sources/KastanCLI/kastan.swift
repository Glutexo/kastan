import Foundation
import Kastan
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct KastanApp {
    static func main() async {
        let runner = CommandRunner()
        print(await runner.output(for: CommandLine.arguments.dropFirst()))
    }
}

struct CommandRunner {
    let version = "0.1.0"
    let client: IDOSClienting
    let aliasFile: StopAliasFile
    let calendarImporter: CalendarImporting

    init(
        client: IDOSClienting = IDOSClient(),
        aliasFile: StopAliasFile = StopAliasFile(),
        calendarImporter: CalendarImporting = SystemCalendarImporter()
    ) {
        self.client = client
        self.aliasFile = aliasFile
        self.calendarImporter = calendarImporter
    }

    func output<S: Sequence<String>>(for arguments: S) async -> String {
        let arguments = CommandOptions.normalized(Array(arguments))

        if arguments.contains("--help") || arguments.contains("-h") {
            return helpText
        }

        if arguments.contains("--version") {
            return version
        }

        guard let command = arguments.first else {
            return """
            🌰 Kaštan

            Search occasional IDOS connections, stations, or suggested places.
            Run kastan --help for usage.
            """
        }

        do {
            switch command {
            case "suggest":
                return try await suggestOutput(for: Array(arguments.dropFirst()))
            case "stations":
                return try await stationsOutput(for: Array(arguments.dropFirst()))
            case "connections":
                return try await connectionsOutput(for: Array(arguments.dropFirst()))
            case "departures":
                return try await departuresOutput(for: Array(arguments.dropFirst()))
            case "aliases":
                return try await aliasesOutput(for: Array(arguments.dropFirst()))
            case "timetables":
                return try timetablesOutput(for: Array(arguments.dropFirst()))
            default:
                if let output = try await shorthandOutput(for: arguments) {
                    return output
                }

                return "❌ Unknown command: \(command)\n\n\(helpText)"
            }
        } catch {
            return OutputFormat.preferredErrorFormat(in: arguments).renderError(Self.errorMessage(for: error))
        }
    }

    private static func errorMessage(for error: Error) -> String {
        let localized = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localized.isEmpty else {
            return "The operation failed, but no error details were provided."
        }

        return localized
    }

    private func suggestOutput(for arguments: [String]) async throws -> String {
        let options = CommandOptions(arguments)
        try options.rejectUnknownOptions(allowedValueOptions: ["--timetable", "-T", "--format", "-o", "--limit", "-l"])
        let format = try options.outputFormat()
        let limit = options.integerValue(for: "--limit", short: "-l") ?? 8
        let timetable = try options.timetable()
        let prefix = options.positional.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !prefix.isEmpty else {
            throw CommandError.usage("Usage: kastan suggest <text> [--timetable alias] [--format text|markdown|json] [--limit count]")
        }

        let suggestions = try await client.suggest(prefix: prefix, limit: limit, timetable: timetable)
        return try format.renderSuggestions(
            SuggestedPlacesOutput(query: prefix, timetable: timetable, suggestions: suggestions)
        )
    }

    private func stationsOutput(for arguments: [String]) async throws -> String {
        let options = CommandOptions(arguments)
        try options.rejectUnknownOptions(allowedValueOptions: ["--timetable", "-T", "--format", "-o", "--limit", "-l"])
        let format = try options.outputFormat()
        let limit = options.integerValue(for: "--limit", short: "-l") ?? 8
        let timetable = try options.timetable()
        let prefix = options.positional.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !prefix.isEmpty else {
            throw CommandError.usage("Usage: kastan stations <name> [-T alias] [-o text|markdown|json] [-l count]")
        }

        let stations = try await client.searchStations(prefix: prefix, limit: limit, timetable: timetable)
        return try format.renderStations(
            StationsOutput(query: prefix, timetable: timetable, stations: stations)
        )
    }

    private func connectionsOutput(for arguments: [String]) async throws -> String {
        let options = CommandOptions(arguments)
        try options.rejectUnknownOptions(
            allowedFlags: ["--arrival", "-a", "--departure", "-p", "--direct", "--only-direct", "-x", "--add-to-calendar", "-c", "--verbose", "-v"],
            allowedValueOptions: [
                "--from", "-f", "--to", "-t", "--via", "-V", "--timetable", "-T", "--date", "-d", "--time", "-m",
                "--max-transfers", "-X", "--min-transfer-time", "-M", "--format", "-o", "--limit", "-l",
            ]
        )
        let format = try options.outputFormat()
        let addToCalendar = options.contains("--add-to-calendar", short: "-c")
        if addToCalendar && format == .ics {
            throw CommandError.conflictingOptions("--add-to-calendar", "--format ics")
        }
        let limit = options.integerValue(for: "--limit", short: "-l") ?? 5
        let requestedLimit = max(1, limit)

        let aliasDatabase = try aliasFile.load()

        let endpoints = try connectionEndpoints(
            from: options.value(for: "--from", short: "-f"),
            to: options.value(for: "--to", short: "-t"),
            positional: positionalValues(in: options)
        )

        let fromPlace = resolvePlace(endpoints.from, in: aliasDatabase)
        let toPlace = resolvePlace(endpoints.to, in: aliasDatabase)
        let viaPlaces = options.values(for: "--via", short: "-V").map { resolvePlace($0, in: aliasDatabase) }
        let timetable = try resolveTimetable(
            explicitValue: options.value(for: "--timetable", short: "-T"),
            aliases: ([fromPlace, toPlace] + viaPlaces).compactMap(\.alias)
        )
        try await rejectAmbiguousPlaces(
            [fromPlace, toPlace] + viaPlaces,
            timetable: timetable,
            stationOnly: false
        )

        let request = IDOSConnectionRequest(
            timetable: timetable,
            from: fromPlace.station,
            to: toPlace.station,
            date: options.value(for: "--date", short: "-d"),
            time: options.value(for: "--time", short: "-m"),
            isArrival: try options.isArrivalTimeMode(),
            onlyDirect: options.contains("--direct", short: "-x") || options.contains("--only-direct"),
            via: viaPlaces.map(\.station),
            maxTransfers: try options.nonNegativeIntegerValue(for: "--max-transfers", short: "-X"),
            minimumTransferTime: try options.nonNegativeIntegerValue(for: "--min-transfer-time", short: "-M"),
            resultLimit: format == .ics || addToCalendar ? 1 : requestedLimit
        )
        let connections = try await client.findConnections(request: request)
        if format == .ics || addToCalendar {
            guard let connection = connections.first else {
                throw CommandError.usage("IDOS returned no connections.")
            }

            let calendar = try await client.connectionCalendar(for: connection, timetable: request.timetable)
            if addToCalendar {
                let output = CalendarImportOutput(
                    request: request,
                    connection: connection,
                    path: try calendarImporter.add(calendar: calendar, fileName: "kastan-\(connection.id).ics").path
                )
                return try format.renderCalendarImport(output)
            }

            return calendar
        }

        return try format.renderConnections(
            ConnectionsOutput(
                request: request,
                connections: Array(connections.prefix(requestedLimit)),
                verbose: options.contains("--verbose", short: "-v")
            )
        )
    }

    private func departuresOutput(for arguments: [String]) async throws -> String {
        let options = CommandOptions(arguments)
        try options.rejectUnknownOptions(
            allowedFlags: ["--arrival", "-a", "--departure", "-p", "--verbose", "-v"],
            allowedValueOptions: ["--station", "-s", "--from", "-f", "--timetable", "-T", "--date", "-d", "--time", "-m", "--format", "-o", "--limit", "-l"]
        )
        let format = try options.outputFormat()
        let aliasDatabase = try aliasFile.load()

        guard let station = departureStation(in: options), !station.isEmpty else {
            throw CommandError.usage(departuresUsage)
        }

        let stationPlace = resolvePlace(station, in: aliasDatabase)
        let timetable = try resolveTimetable(
            explicitValue: options.value(for: "--timetable", short: "-T"),
            aliases: [stationPlace.alias].compactMap(\.self)
        )
        try await rejectAmbiguousPlaces([stationPlace], timetable: timetable, stationOnly: true)

        let request = IDOSDeparturesRequest(
            timetable: timetable,
            station: stationPlace.station,
            date: options.value(for: "--date", short: "-d"),
            time: options.value(for: "--time", short: "-m"),
            isArrival: try options.isArrivalTimeMode()
        )
        let limit = options.integerValue(for: "--limit", short: "-l") ?? 10
        let departures = try await client.findDepartures(request: request)
        return try format.renderDepartures(
            DeparturesOutput(
                request: request,
                departures: Array(departures.prefix(max(1, limit))),
                verbose: options.contains("--verbose", short: "-v")
            )
        )
    }

    private func timetablesOutput(for arguments: [String]) throws -> String {
        let options = CommandOptions(arguments)
        try options.rejectUnknownOptions(allowedValueOptions: ["--format", "-o"])
        let format = try options.outputFormat()
        return try format.renderTimetables(TimetablesOutput(timetables: IDOSTimetable.known))
    }

    private func shorthandOutput(for arguments: [String]) async throws -> String? {
        let options = CommandOptions(arguments)

        if isConnectionShorthand(options) {
            return try await connectionsOutput(for: arguments)
        }

        if positionalValues(in: options).count == 1 {
            return try await departuresOutput(for: arguments)
        }

        return nil
    }

    private func aliasesOutput(for arguments: [String]) async throws -> String {
        guard let action = arguments.first else {
            throw CommandError.usage("Usage: kastan aliases list|add|remove|path")
        }

        let actionArguments = Array(arguments.dropFirst())
        let options = CommandOptions(actionArguments)

        switch action {
        case "list":
            try options.rejectUnknownOptions(allowedValueOptions: ["--format", "-o"])
            let format = try options.outputFormat()
            return try format.renderStopAliases(StopAliasesOutput(
                aliases: aliasFile.load().aliases,
                path: aliasFile.fileURL.path
            ))

        case "add":
            try options.rejectUnknownOptions(allowedValueOptions: ["--station", "-s", "--timetable", "-T", "--format", "-o"])
            let format = try options.outputFormat()
            let positional = options.positional
            let station = (options.value(for: "--station", short: "-s") ?? positional.dropFirst().joined(separator: " "))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let name = positional.first, !name.isEmpty,
                  !station.isEmpty,
                  let timetableValue = options.value(for: "--timetable", short: "-T"), !timetableValue.isEmpty
            else {
                throw CommandError.usage("Usage: kastan aliases add name [place|--station place] --timetable alias [--format text|markdown|json]")
            }

            let timetable = try IDOSTimetable.resolve(timetableValue)
            try await rejectAmbiguousPlace(station, timetable: timetable, stationOnly: true)
            var database = try aliasFile.load()
            let action = database.alias(named: name) == nil ? "added" : "updated"
            let alias = StopAlias(name: name, station: station, timetable: timetable)
            try database.upsert(alias)
            try aliasFile.save(database)

            return try format.renderStopAliasMutation(StopAliasMutationOutput(
                action: action,
                alias: alias,
                path: aliasFile.fileURL.path
            ))

        case "remove":
            try options.rejectUnknownOptions(allowedValueOptions: ["--format", "-o"])
            let format = try options.outputFormat()

            guard let name = options.positional.first, !name.isEmpty else {
                throw CommandError.usage("Usage: kastan aliases remove name [--format text|markdown|json]")
            }

            var database = try aliasFile.load()
            let alias = try database.remove(name: name)
            try aliasFile.save(database)

            return try format.renderStopAliasMutation(StopAliasMutationOutput(
                action: "removed",
                alias: alias,
                path: aliasFile.fileURL.path
            ))

        case "path":
            try options.rejectUnknownOptions(allowedValueOptions: ["--format", "-o"])
            let format = try options.outputFormat()
            return try format.renderStopAliasPath(StopAliasPathOutput(path: aliasFile.fileURL.path))

        default:
            throw CommandError.usage("Usage: kastan aliases list|add|remove|path")
        }
    }

    private func resolvePlace(_ value: String, in database: StopAliasDatabase) -> ResolvedPlace {
        guard let alias = database.alias(named: value) else {
            return ResolvedPlace(station: value, alias: nil)
        }

        return ResolvedPlace(station: alias.station, alias: alias)
    }

    private func rejectAmbiguousPlaces(
        _ places: [ResolvedPlace],
        timetable: IDOSTimetable,
        stationOnly: Bool
    ) async throws {
        for place in places where place.alias == nil {
            try await rejectAmbiguousPlace(place.station, timetable: timetable, stationOnly: stationOnly)
        }
    }

    private func rejectAmbiguousPlace(
        _ value: String,
        timetable: IDOSTimetable,
        stationOnly: Bool
    ) async throws {
        let suggestions = stationOnly
            ? try await client.searchStations(prefix: value, limit: 8, timetable: timetable)
            : try await client.suggest(prefix: value, limit: 8, timetable: timetable)
        let candidates = uniqueSuggestions(suggestions)
        let exactMatches = candidates.filter { suggestion($0, matches: value) }
        if exactMatches.count == 1 || candidates.count <= 1 {
            return
        }

        throw CommandError.ambiguousPlace(
            PlaceAmbiguity(
                input: value,
                timetable: timetable,
                kind: stationOnly ? "station" : "place",
                candidates: exactMatches.isEmpty ? candidates : exactMatches
            )
        )
    }

    private func resolveTimetable(explicitValue: String?, aliases: [StopAlias]) throws -> IDOSTimetable {
        let explicitTimetable = try explicitValue.map(IDOSTimetable.resolve)
        let aliasTimetables = aliases.map(\.timetable)

        if let explicitTimetable {
            if let conflictingAlias = aliases.first(where: { $0.timetable.slug != explicitTimetable.slug }) {
                throw CommandError.aliasTimetableMismatch(
                    alias: conflictingAlias.name,
                    aliasTimetable: conflictingAlias.timetable,
                    requestedTimetable: explicitTimetable
                )
            }

            return explicitTimetable
        }

        guard let first = aliasTimetables.first else {
            return try IDOSTimetable.resolve(nil)
        }

        if let conflicting = aliases.first(where: { $0.timetable.slug != first.slug }) {
            throw CommandError.conflictingAliasTimetables(first, conflicting.timetable)
        }

        return first
    }

    private func connectionEndpoints(from: String?, to: String?, positional: [String]) throws -> ConnectionEndpoints {
        let from = from?.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = to?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let from, !from.isEmpty, let to, !to.isEmpty {
            return ConnectionEndpoints(from: from, to: to)
        }

        if from?.isEmpty == false || to?.isEmpty == false {
            throw CommandError.usage(connectionUsage)
        }

        let positional = positionalValues(positional)

        if positional.count == 2 {
            return ConnectionEndpoints(from: positional[0], to: positional[1])
        }

        let expression = positional.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty, let endpoints = parseConnectionExpression(expression) else {
            throw CommandError.usage(connectionUsage)
        }

        return endpoints
    }

    private func departureStation(in options: CommandOptions) -> String? {
        if let station = options.value(for: "--station", short: "-s")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !station.isEmpty
        {
            return station
        }

        if let station = options.value(for: "--from", short: "-f")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !station.isEmpty
        {
            return station
        }

        let positional = positionalValues(in: options)
        return positional.count == 1 ? positional[0] : nil
    }

    private func isConnectionShorthand(_ options: CommandOptions) -> Bool {
        let from = options.value(for: "--from", short: "-f")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = options.value(for: "--to", short: "-t")?.trimmingCharacters(in: .whitespacesAndNewlines)

        if from?.isEmpty == false || to?.isEmpty == false {
            return true
        }

        let positional = positionalValues(in: options)
        if positional.count == 2 {
            return true
        }

        return parseConnectionExpression(positional.joined(separator: " ")) != nil
    }

    private func positionalValues(in options: CommandOptions) -> [String] {
        positionalValues(options.positional(valueOptions: [
            "--from", "-f", "--to", "-t", "--via", "-V", "--station", "-s", "--timetable", "-T",
            "--date", "-d", "--time", "-m", "--max-transfers", "-X", "--min-transfer-time", "-M",
            "--format", "-o", "--limit", "-l",
        ]))
    }

    private func positionalValues(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parseConnectionExpression(_ expression: String) -> ConnectionEndpoints? {
        for delimiter in ["->", "→"] {
            if let endpoints = splitConnectionExpression(expression, delimiter: delimiter, useLastMatch: false) {
                return endpoints
            }
        }

        return splitConnectionExpression(expression, delimiter: "-", useLastMatch: true)
    }

    private func splitConnectionExpression(_ expression: String, delimiter: String, useLastMatch: Bool) -> ConnectionEndpoints? {
        let range = useLastMatch ? expression.range(of: delimiter, options: .backwards) : expression.range(of: delimiter)
        guard let range else {
            return nil
        }

        let from = String(expression[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let to = String(expression[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else {
            return nil
        }

        return ConnectionEndpoints(from: from, to: to)
    }

    private var connectionUsage: String {
        "Usage: kastan connections route|from to|-f place -t place [-V place] [-T alias] [-d d.m.yyyy] [-m h:mm] [-a|-p] [-x] [-X count] [-M minutes] [-c] [-v] [-o text|markdown|json|ics] [-l count]"
    }

    private var departuresUsage: String {
        "Usage: kastan departures station|-f place|-s place [-T alias] [-d d.m.yyyy] [-m h:mm] [-a|-p] [-v] [-o text|markdown|json] [-l count]"
    }

    private var helpText: String {
        """
        🌰 Usage:
          kastan route|from to
          kastan station
          kastan suggest <text> [-T alias] [-o text|markdown|json] [-l count]
          kastan stations <name> [-T alias] [-o text|markdown|json] [-l count]
          kastan connections route|from to|-f place -t place [-V place] [-T alias] [-d d.m.yyyy] [-m h:mm] [-a|-p] [-x] [-X count] [-M minutes] [-c] [-v] [-o text|markdown|json|ics] [-l count]
          kastan departures station|-f place|-s place [-T alias] [-d d.m.yyyy] [-m h:mm] [-a|-p] [-v] [-o text|markdown|json] [-l count]
          kastan aliases list|add|remove|path [-o text|markdown|json]
          kastan timetables [-o text|markdown|json]

        ⚙️ Options:
          -h, --help              Show help
          --version               Show the app version
          -f, --from              Departure place or station
          -t, --to                Arrival place
          -s, --station           Station for departures or arrivals
          -T, --timetable         Timetable alias or IDOS URL slug
          -d, --date              Search date
          -m, --time              Search time
          -a, --arrival           Search by arrival time instead of departure time
          -p, --departure         Search by departure time
          -V, --via               Via place, repeat for multiple places
          -x, --direct            Direct connections only
          -c, --add-to-calendar   Open the first returned connection as an iCalendar import
          -v, --verbose           Show tariff zones, platforms, carriers, and delay details
          -X, --max-transfers     Maximum transfers permitted, including 0
          -M, --min-transfer-time Minimum transfer time in minutes, including 0
          -o, --format            Output format: text, markdown, json, or ics for connections
          -l, --limit             Maximum number of printed results

        Default timetable is vlakyautobusymhdvse.
        Stop aliases are stored in ~/.config/kastan/aliases.json unless KASTAN_ALIAS_DATABASE is set.
        """
    }
}

private enum CommandError: LocalizedError {
    case invalidOutputFormat(String)
    case invalidNonNegativeInteger(name: String, value: String)
    case conflictingOptions(String, String)
    case aliasTimetableMismatch(alias: String, aliasTimetable: IDOSTimetable, requestedTimetable: IDOSTimetable)
    case conflictingAliasTimetables(IDOSTimetable, IDOSTimetable)
    case calendarImportUnavailable
    case unknownOption(String)
    case unsupportedOutputFormat(format: String, command: String)
    case ambiguousPlace(PlaceAmbiguity)
    case usage(String)

    var errorDescription: String? {
        switch self {
        case .invalidOutputFormat(let value):
            return "Invalid output format: \(value). Use text, markdown, json, or ics."
        case .invalidNonNegativeInteger(let name, let value):
            return "Invalid \(name): \(value). Use a non-negative integer."
        case .conflictingOptions(let first, let second):
            return "Conflicting options: \(first) and \(second). Use only one."
        case .aliasTimetableMismatch(let alias, let aliasTimetable, let requestedTimetable):
            return "Stop alias \(alias) belongs to \(aliasTimetable.displayName), but requested timetable is \(requestedTimetable.displayName)."
        case .conflictingAliasTimetables(let first, let second):
            return "Stop aliases use conflicting timetables: \(first.displayName) and \(second.displayName). Use --timetable only when all used aliases belong to it."
        case .calendarImportUnavailable:
            return "Calendar import is not available on this system."
        case .unknownOption(let value):
            return "Unknown option: \(value)."
        case .unsupportedOutputFormat(let format, let command):
            return "\(format) output is not available for \(command)."
        case .ambiguousPlace(let ambiguity):
            return ambiguity.message
        case .usage(let message):
            return message
        }
    }
}

private enum OutputFormat: String {
    case text
    case markdown
    case json
    case ics

    static func resolve(_ value: String?) throws -> OutputFormat {
        guard let value, !value.isEmpty else {
            return .text
        }

        switch value.lowercased() {
        case "text", "plain":
            return .text
        case "markdown", "md":
            return .markdown
        case "json":
            return .json
        case "ics", "ical", "calendar":
            return .ics
        default:
            throw CommandError.invalidOutputFormat(value)
        }
    }

    static func preferredErrorFormat(in arguments: [String]) -> OutputFormat {
        let options = CommandOptions(Array(arguments.dropFirst()))
        return (try? options.outputFormat()) ?? .text
    }

    func renderError(_ message: String) -> String {
        switch self {
        case .text, .ics:
            return "❌ Error: \(message)"
        case .markdown:
            let lines = message.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let first = lines.first else {
                return "> ❌ Error"
            }

            return (["> ❌ Error: \(Markdown.escape(first))"] + lines.dropFirst().map { "> \(Markdown.escape($0))" })
                .joined(separator: "\n")
        case .json:
            return (try? JSON.write(ErrorOutput(error: message))) ?? #"{"error":"\#(message)"}"#
        }
    }

    func renderSuggestions(_ output: SuggestedPlacesOutput) throws -> String {
        switch self {
        case .text:
            guard !output.suggestions.isEmpty else {
                return "🔎 No suggested places found."
            }

            return (["🔎 Suggested places (\(output.timetable.displayName)):"] + output.suggestions.enumerated().map { index, suggestion in
                let detail = suggestionDetails(suggestion).joined(separator: ", ")
                return "\(index + 1). \(suggestion.text)\(detail.isEmpty ? "" : " - \(detail)")"
            }).joined(separator: "\n")
        case .markdown:
            guard !output.suggestions.isEmpty else {
                return "## 🔎 Suggested Places\n\nNo suggested places found."
            }

            let rows = output.suggestions.enumerated().map { index, suggestion in
                "| \(index + 1) | \(Markdown.escape(suggestion.text)) | \(Markdown.escape(suggestionDetails(suggestion).joined(separator: ", "))) |"
            }.joined(separator: "\n")

            return """
            ## 🔎 Suggested Places

            Timetable: **\(Markdown.escape(output.timetable.displayName))**

            | # | Place | Details |
            | ---: | --- | --- |
            \(rows)
            """
        case .json:
            return try JSON.write(output)
        case .ics:
            throw CommandError.unsupportedOutputFormat(format: "iCal", command: "suggest")
        }
    }

    func renderStations(_ output: StationsOutput) throws -> String {
        switch self {
        case .text:
            guard !output.stations.isEmpty else {
                return "🚏 No stations found."
            }

            return (["🚏 Stations (\(output.timetable.displayName)):"] + output.stations.enumerated().map { index, station in
                let detail = suggestionDetails(station).joined(separator: ", ")
                return "\(index + 1). \(station.text)\(detail.isEmpty ? "" : " - \(detail)")"
            }).joined(separator: "\n")
        case .markdown:
            guard !output.stations.isEmpty else {
                return "## 🚏 Stations\n\nNo stations found."
            }

            let rows = output.stations.enumerated().map { index, station in
                "| \(index + 1) | \(Markdown.escape(station.text)) | \(Markdown.escape(suggestionDetails(station).joined(separator: ", "))) |"
            }.joined(separator: "\n")

            return """
            ## 🚏 Stations

            Timetable: **\(Markdown.escape(output.timetable.displayName))**

            | # | Station | Details |
            | ---: | --- | --- |
            \(rows)
            """
        case .json:
            return try JSON.write(output)
        case .ics:
            throw CommandError.unsupportedOutputFormat(format: "iCal", command: "stations")
        }
    }

    func renderConnections(_ output: ConnectionsOutput) throws -> String {
        switch self {
        case .text:
            guard !output.connections.isEmpty else {
                return "🔎 IDOS returned no connections."
            }

            let rows = output.items.enumerated().map { index, item in
                item.summaryLine(number: index + 1, includeDetails: output.verbose)
            }

            return """
            🧭 Connections \(routeDescription(output.request)) (\(output.request.timetable.displayName)):
            \(rows.joined(separator: "\n"))
            """
        case .markdown:
            guard !output.connections.isEmpty else {
                return """
                ## 🧭 Connections

                **From:** \(Markdown.escape(output.request.from))
                **To:** \(Markdown.escape(output.request.to))
                \(markdownViaLine(output.request))
                **Timetable:** \(Markdown.escape(output.request.timetable.displayName))

                No connections found.
                """
            }

            let sections = output.items.enumerated().map { index, item in
                let connection = item.connection
                let legs = connection.legs.map { leg in
                    if output.verbose {
                        return "| \(Markdown.lineName(leg)) | \(Markdown.escape(leg.fromStation)) | \(Markdown.escape(leg.fromTariffZone ?? "")) | \(Markdown.escape(leg.fromPlatform ?? "")) | \(Markdown.bold(leg.departureTime)) | \(Markdown.escape(leg.toStation)) | \(Markdown.escape(leg.toTariffZone ?? "")) | \(Markdown.escape(leg.toPlatform ?? "")) | \(Markdown.bold(leg.arrivalTime)) | \(Markdown.escape(leg.carrier ?? "")) | \(Markdown.escape(leg.delay ?? "")) |"
                    }

                    return "| \(Markdown.lineName(leg)) | \(Markdown.escape(leg.fromStation)) | \(Markdown.bold(leg.departureTime)) | \(Markdown.escape(leg.toStation)) | \(Markdown.bold(leg.arrivalTime)) |"
                }.joined(separator: "\n")
                let tableHeader = output.verbose ? """
                | Line | From | From Tariff Zone | From Platform | Departure | To | To Tariff Zone | To Platform | Arrival | Carrier | Delay |
                | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
                """ : """
                | Line | From | Departure | To | Arrival |
                | --- | --- | --- | --- | --- |
                """

                return """
                ### \(index + 1). \(item.markdownLabel)\(Markdown.bold(connection.departureTime)) \(Markdown.escape(connection.departureStation)) → \(Markdown.bold(connection.arrivalTime)) \(Markdown.escape(connection.arrivalStation))

                Duration: **\(Markdown.escape(connection.duration))**

                \(tableHeader)
                \(legs)
                """
            }.joined(separator: "\n\n")

            return """
            ## 🧭 Connections

            **From:** \(Markdown.escape(output.request.from))
            **To:** \(Markdown.escape(output.request.to))
            \(markdownViaLine(output.request))
            **Timetable:** \(Markdown.escape(output.request.timetable.displayName))

            \(sections)
            """
        case .json:
            return try JSON.write(output)
        case .ics:
            throw CommandError.unsupportedOutputFormat(format: "iCal", command: "connections renderer")
        }
    }

    func renderCalendarImport(_ output: CalendarImportOutput) throws -> String {
        switch self {
        case .text, .ics:
            return "📅 Opened calendar import for \(routeDescription(output.request)): \(output.path)"
        case .markdown:
            return """
            ## 📅 Calendar Import

            **Connection:** \(Markdown.bold(output.connection.departureTime)) \(Markdown.escape(output.connection.departureStation)) → \(Markdown.bold(output.connection.arrivalTime)) \(Markdown.escape(output.connection.arrivalStation))
            **File:** `\(Markdown.escape(output.path))`
            """
        case .json:
            return try JSON.write(output)
        }
    }

    func renderDepartures(_ output: DeparturesOutput) throws -> String {
        let title = output.request.isArrival ? "Arrivals" : "Departures"
        let stationName = output.departures.first?.stationName ?? output.request.station

        switch self {
        case .text:
            guard !output.departures.isEmpty else {
                return "🔎 IDOS returned no \(title.lowercased())."
            }

            let rows = output.departures.enumerated().map { index, departure in
                departure.summaryLine(number: index + 1, includeDetails: output.verbose)
            }

            return """
            🚏 \(title) \(stationName) (\(output.request.timetable.displayName)):
            \(rows.joined(separator: "\n"))
            """
        case .markdown:
            guard !output.departures.isEmpty else {
                return """
                ## 🚏 \(title)

                **Station:** \(Markdown.escape(output.request.station))
                **Timetable:** \(Markdown.escape(output.request.timetable.displayName))

                No \(title.lowercased()) found.
                """
            }

            let rows = output.departures.enumerated().map { index, departure in
                if output.verbose {
                    return "| \(index + 1) | \(Markdown.bold(departure.time)) | \(Markdown.departureLineName(departure)) | \(Markdown.escape(departure.destination)) | \(Markdown.escape(departure.tariffZone ?? "")) | \(Markdown.escape(departure.platform ?? "")) | \(Markdown.escape(departure.via ?? "")) | \(Markdown.escape(departure.carrier ?? "")) | \(Markdown.escape(departure.delay ?? "")) |"
                }

                return "| \(index + 1) | \(Markdown.bold(departure.time)) | \(Markdown.departureLineName(departure)) | \(Markdown.escape(departure.destination)) | \(Markdown.escape(departure.via ?? "")) |"
            }.joined(separator: "\n")
            let tableHeader = output.verbose ? """
            | # | Time | Line | Destination | Tariff Zone | Platform | Via | Carrier | Delay |
            | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
            """ : """
            | # | Time | Line | Destination | Via |
            | ---: | --- | --- | --- | --- |
            """

            return """
            ## 🚏 \(title)

            **Station:** \(Markdown.escape(stationName))
            **Timetable:** \(Markdown.escape(output.request.timetable.displayName))

            \(tableHeader)
            \(rows)
            """
        case .json:
            return try JSON.write(output)
        case .ics:
            throw CommandError.unsupportedOutputFormat(format: "iCal", command: title.lowercased())
        }
    }

    func renderTimetables(_ output: TimetablesOutput) throws -> String {
        switch self {
        case .text:
            let rows = output.timetables.map { timetable in
                "  \(timetable.slug) - \(timetable.displayName)"
            }

            return """
            🗂 Timetables:
            \(rows.joined(separator: "\n"))

            --timetable also accepts a custom IDOS URL slug when IDOS supports it.
            """
        case .markdown:
            let rows = output.timetables.map { timetable in
                "| \(Markdown.escape(timetable.slug)) | \(Markdown.escape(timetable.displayName)) |"
            }.joined(separator: "\n")

            return """
            ## 🗂 Timetables

            | Slug | Name |
            | --- | --- |
            \(rows)

            `--timetable` also accepts a custom IDOS URL slug when IDOS supports it.
            """
        case .json:
            return try JSON.write(output)
        case .ics:
            throw CommandError.unsupportedOutputFormat(format: "iCal", command: "timetables")
        }
    }

    func renderStopAliases(_ output: StopAliasesOutput) throws -> String {
        switch self {
        case .text:
            guard !output.aliases.isEmpty else {
                return "🌰 No stop aliases saved.\nDatabase: \(output.path)"
            }

            let rows = output.aliases.map { alias in
                "  \(alias.name) → \(alias.station) (\(alias.timetable.displayName))"
            }

            return """
            🌰 Stop aliases:
            \(rows.joined(separator: "\n"))

            Database: \(output.path)
            """
        case .markdown:
            guard !output.aliases.isEmpty else {
                return """
                ## 🌰 Stop Aliases

                No stop aliases saved.

                Database: `\(Markdown.escape(output.path))`
                """
            }

            let rows = output.aliases.map { alias in
                "| \(Markdown.escape(alias.name)) | \(Markdown.escape(alias.station)) | \(Markdown.escape(alias.timetable.displayName)) | \(Markdown.escape(alias.timetable.slug)) |"
            }.joined(separator: "\n")

            return """
            ## 🌰 Stop Aliases

            | Alias | Station | Timetable | Slug |
            | --- | --- | --- | --- |
            \(rows)

            Database: `\(Markdown.escape(output.path))`
            """
        case .json:
            return try JSON.write(output)
        case .ics:
            throw CommandError.unsupportedOutputFormat(format: "iCal", command: "aliases")
        }
    }

    func renderStopAliasMutation(_ output: StopAliasMutationOutput) throws -> String {
        switch self {
        case .text:
            return "🌰 Alias \(output.action): \(output.alias.name) → \(output.alias.station) (\(output.alias.timetable.displayName))"
        case .markdown:
            return """
            ## 🌰 Stop Alias \(output.action.capitalized)

            **Alias:** \(Markdown.escape(output.alias.name))
            **Station:** \(Markdown.escape(output.alias.station))
            **Timetable:** \(Markdown.escape(output.alias.timetable.displayName))
            **Database:** `\(Markdown.escape(output.path))`
            """
        case .json:
            return try JSON.write(output)
        case .ics:
            throw CommandError.unsupportedOutputFormat(format: "iCal", command: "aliases")
        }
    }

    func renderStopAliasPath(_ output: StopAliasPathOutput) throws -> String {
        switch self {
        case .text:
            return "🌰 Alias database: \(output.path)"
        case .markdown:
            return """
            ## 🌰 Alias Database

            `\(Markdown.escape(output.path))`
            """
        case .json:
            return try JSON.write(output)
        case .ics:
            throw CommandError.unsupportedOutputFormat(format: "iCal", command: "aliases")
        }
    }

    private func routeDescription(_ request: IDOSConnectionRequest) -> String {
        let via = request.via.isEmpty ? "" : " via \(request.via.joined(separator: ", "))"
        return "\(request.from) → \(request.to)\(via)"
    }

    private func markdownViaLine(_ request: IDOSConnectionRequest) -> String {
        guard !request.via.isEmpty else {
            return ""
        }

        return "**Via:** \(Markdown.escape(request.via.joined(separator: ", ")))"
    }
}

private struct SuggestedPlacesOutput: Codable {
    var query: String
    var timetable: IDOSTimetable
    var suggestions: [IDOSSuggestion]
}

private struct StationsOutput: Codable {
    var query: String
    var timetable: IDOSTimetable
    var stations: [IDOSSuggestion]
}

private struct ConnectionsOutput: Encodable {
    var request: IDOSConnectionRequest
    var connections: [IDOSConnection]
    var verbose = false

    var items: [ConnectionOutput] {
        let shortestDuration = connections.compactMap(\.durationInMinutes).min()
        return connections.map { connection in
            ConnectionOutput(
                connection: connection,
                isDirect: connection.legs.count == 1,
                isShortest: shortestDuration.map { connection.durationInMinutes == $0 } ?? false
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case request
        case connections
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(request, forKey: .request)
        try container.encode(items, forKey: .connections)
    }
}

private struct ConnectionOutput: Encodable {
    var connection: IDOSConnection
    var isDirect: Bool
    var isShortest: Bool

    private var labels: [String] {
        [
            isDirect ? "➡️ Direct" : nil,
            isShortest ? "⚡ Shortest" : nil,
        ].compactMap(\.self)
    }

    var markdownLabel: String {
        labels.isEmpty ? "" : "\(labels.joined(separator: " · ")) — "
    }

    func summaryLine(number: Int, includeDetails: Bool) -> String {
        let summary = connection.summaryLine(number: number, includeDetails: includeDetails)
        guard !labels.isEmpty else {
            return summary
        }

        let numberPrefix = "\(number). "
        return "\(numberPrefix)\(labels.joined(separator: " · ")) — \(summary.dropFirst(numberPrefix.count))"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case departureTime
        case departureStation
        case arrivalTime
        case arrivalStation
        case duration
        case legs
        case shareURL
        case isDirect
        case isShortest
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(connection.id, forKey: .id)
        try container.encode(connection.departureTime, forKey: .departureTime)
        try container.encode(connection.departureStation, forKey: .departureStation)
        try container.encode(connection.arrivalTime, forKey: .arrivalTime)
        try container.encode(connection.arrivalStation, forKey: .arrivalStation)
        try container.encode(connection.duration, forKey: .duration)
        try container.encode(connection.legs, forKey: .legs)
        try container.encodeIfPresent(connection.shareURL, forKey: .shareURL)
        try container.encode(isDirect, forKey: .isDirect)
        try container.encode(isShortest, forKey: .isShortest)
    }
}

private extension IDOSConnection {
    /// Converts the IDOS overall-time label into a value that can be compared within one result list.
    var durationInMinutes: Int? {
        guard let expression = try? NSRegularExpression(pattern: #"(\d+)\s*([[:alpha:]]+)"#) else {
            return nil
        }

        let matches = expression.matches(
            in: duration,
            range: NSRange(duration.startIndex..<duration.endIndex, in: duration)
        )
        var total = 0
        var foundSupportedUnit = false

        for match in matches {
            guard let valueRange = Range(match.range(at: 1), in: duration),
                  let unitRange = Range(match.range(at: 2), in: duration),
                  let value = Int(duration[valueRange])
            else {
                continue
            }

            let unit = duration[unitRange].lowercased()
            if unit == "d" || unit.hasPrefix("day") {
                total += value * 24 * 60
                foundSupportedUnit = true
            } else if unit == "h" || unit.hasPrefix("hour") || unit.hasPrefix("hod") {
                total += value * 60
                foundSupportedUnit = true
            } else if unit == "m" || unit.hasPrefix("min") {
                total += value
                foundSupportedUnit = true
            }
        }

        return foundSupportedUnit ? total : nil
    }
}

private struct DeparturesOutput: Codable {
    var request: IDOSDeparturesRequest
    var departures: [IDOSDeparture]
    var verbose = false

    enum CodingKeys: String, CodingKey {
        case request
        case departures
    }
}

private struct CalendarImportOutput: Codable {
    var request: IDOSConnectionRequest
    var connection: IDOSConnection
    var path: String
}

private struct TimetablesOutput: Codable {
    var timetables: [IDOSTimetable]
}

private struct StopAliasesOutput: Codable {
    var aliases: [StopAlias]
    var path: String
}

private struct StopAliasMutationOutput: Codable {
    var action: String
    var alias: StopAlias
    var path: String
}

private struct StopAliasPathOutput: Codable {
    var path: String
}

private struct ResolvedPlace {
    var station: String
    var alias: StopAlias?
}

private struct PlaceAmbiguity {
    var input: String
    var timetable: IDOSTimetable
    var kind: String
    var candidates: [IDOSSuggestion]

    var message: String {
        let header = "Ambiguous \(kind) name: \(input) (\(timetable.displayName))."
        let rows = candidates.enumerated().map { index, suggestion in
            let detail = suggestionDetails(suggestion).joined(separator: ", ")
            return "\(index + 1). \(suggestion.text)\(detail.isEmpty ? "" : " - \(detail)")"
        }

        return ([header, "Choose one of:"] + rows).joined(separator: "\n")
    }
}

private struct ConnectionEndpoints {
    var from: String
    var to: String
}

private struct ErrorOutput: Codable {
    var error: String
}

private func uniqueSuggestions(_ suggestions: [IDOSSuggestion]) -> [IDOSSuggestion] {
    var seen: Set<String> = []
    return suggestions.filter { suggestion in
        let key = [
            normalizedSuggestionText(suggestion.text),
            suggestion.description ?? "",
            suggestion.region ?? "",
            suggestion.value ?? "",
            suggestion.value2 ?? "",
        ].joined(separator: "|")

        return seen.insert(key).inserted
    }
}

private func suggestion(_ suggestion: IDOSSuggestion, matches value: String) -> Bool {
    let expected = normalizedSuggestionText(value)
    return [suggestion.selectedText, suggestion.text]
        .compactMap(\.self)
        .contains { normalizedSuggestionText($0) == expected }
}

private func suggestionDetails(_ suggestion: IDOSSuggestion) -> [String] {
    var details: [String] = []
    for value in [suggestion.description, suggestion.region].compactMap(\.self) where !value.isEmpty {
        if !details.contains(where: { $0.localizedCaseInsensitiveContains(value) }) {
            details.append(value)
        }
    }
    return details
}

private func normalizedSuggestionText(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
        .lowercased()
}

protocol CalendarImporting {
    func add(calendar: String, fileName: String) throws -> URL
}

struct SystemCalendarImporter: CalendarImporting {
    func add(calendar: String, fileName: String) throws -> URL {
        #if os(macOS)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(fileName)

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try calendar.write(to: url, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CommandError.calendarImportUnavailable
        }

        return url
        #else
        throw CommandError.calendarImportUnavailable
        #endif
    }
}

private enum JSON {
    static func write<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

private enum Markdown {
    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    static func bold(_ value: String) -> String {
        guard !value.isEmpty else {
            return ""
        }

        return "**\(escape(value))**"
    }

    static func lineName(_ leg: IDOSConnectionLeg) -> String {
        let name = htmlEscape(leg.name)
        let prefix = leg.transportMode.map { "\($0.emoji) " } ?? ""
        guard let color = leg.color, !color.isEmpty else {
            return "\(prefix)\(escape(leg.name))"
        }
        return "\(prefix)<span style=\"color: \(htmlEscape(color))\">\(name)</span>"
    }

    static func departureLineName(_ departure: IDOSDeparture) -> String {
        let prefix = departure.transportMode.map { "\($0.emoji) " } ?? ""
        let name = htmlEscape(departure.lineName)
        guard let color = departure.lineColor, !color.isEmpty else {
            return "\(prefix)\(escape(departure.lineName))"
        }
        return "\(prefix)<span style=\"color: \(htmlEscape(color))\">\(name)</span>"
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private struct CommandOptions {
    private static let shortFlags: Set<Character> = ["h", "a", "p", "x", "c", "v"]
    private static let shortValueOptions: Set<Character> = ["f", "t", "s", "T", "V", "d", "m", "X", "M", "o", "l"]

    let arguments: [String]

    init(_ arguments: [String]) {
        self.arguments = Self.normalized(arguments)
    }

    static func normalized(_ arguments: [String]) -> [String] {
        arguments.flatMap(expandedShortOptions)
    }

    var positional: [String] {
        positional(valueOptions: Set(arguments.filter { $0.hasPrefix("-") }))
    }

    private static func expandedShortOptions(_ argument: String) -> [String] {
        guard argument.hasPrefix("-"),
              !argument.hasPrefix("--"),
              !argument.contains("="),
              argument.count > 2,
              !argument.dropFirst().allSatisfy(\.isNumber)
        else {
            return [argument]
        }

        let options = Array(argument.dropFirst())
        guard options.indices.allSatisfy({ index in
            let option = options[index]
            if shortFlags.contains(option) {
                return true
            }

            return shortValueOptions.contains(option) && index == options.count - 1
        }) else {
            return [argument]
        }

        return options.map { "-\($0)" }
    }

    func positional(valueOptions: Set<String>) -> [String] {
        var values: [String] = []
        var skipNext = false

        for argument in arguments {
            if skipNext {
                skipNext = false
                continue
            }

            if argument.hasPrefix("--") || argument.hasPrefix("-") {
                skipNext = valueOptions.contains(argument) && !argument.contains("=")
                continue
            }

            values.append(argument)
        }

        return values
    }

    func value(for longName: String, short shortName: String? = nil) -> String? {
        for index in arguments.indices {
            let argument = arguments[index]
            let names = [longName, shortName].compactMap(\.self)

            for name in names {
                if argument == name, arguments.indices.contains(index + 1) {
                    return arguments[index + 1]
                }

                if argument.hasPrefix("\(name)=") {
                    return String(argument.dropFirst(name.count + 1))
                }
            }
        }

        return nil
    }

    func values(for name: String, short shortName: String? = nil) -> [String] {
        var values: [String] = []
        let names = [name, shortName].compactMap(\.self)

        for index in arguments.indices {
            let argument = arguments[index]

            for name in names {
                if argument == name, arguments.indices.contains(index + 1) {
                    values.append(arguments[index + 1])
                }

                if argument.hasPrefix("\(name)=") {
                    values.append(String(argument.dropFirst(name.count + 1)))
                }
            }
        }

        return values.filter { !$0.isEmpty }
    }

    func integerValue(for name: String, short shortName: String? = nil) -> Int? {
        value(for: name, short: shortName).flatMap(Int.init)
    }

    func nonNegativeIntegerValue(for name: String, short shortName: String? = nil) throws -> Int? {
        guard let match = optionValue(for: name, short: shortName) else {
            return nil
        }

        let (option, value) = match
        guard let integer = Int(value), integer >= 0 else {
            throw CommandError.invalidNonNegativeInteger(name: option, value: value)
        }

        return integer
    }

    func contains(_ name: String, short shortName: String? = nil) -> Bool {
        let names = [name, shortName].compactMap(\.self)
        return arguments.contains { argument in
            names.contains(argument)
        }
    }

    func rejectUnknownOptions(allowedFlags: Set<String> = [], allowedValueOptions: Set<String>) throws {
        var valueExpectedBy: String?

        for argument in arguments {
            if let option = valueExpectedBy {
                if allowedValueOptions.contains(argument) || allowedFlags.contains(argument) {
                    throw CommandError.unknownOption(option)
                }

                valueExpectedBy = nil
                continue
            }

            guard argument.hasPrefix("-") else {
                continue
            }

            if let equalsIndex = argument.firstIndex(of: "=") {
                let option = String(argument[..<equalsIndex])
                if !allowedValueOptions.contains(option) {
                    throw CommandError.unknownOption(option)
                }
                continue
            }

            if allowedValueOptions.contains(argument) {
                valueExpectedBy = argument
                continue
            }

            if !allowedFlags.contains(argument) {
                throw CommandError.unknownOption(argument)
            }
        }
    }

    func isArrivalTimeMode() throws -> Bool {
        let arrival = contains("--arrival", short: "-a")
        let departure = contains("--departure", short: "-p")

        guard !(arrival && departure) else {
            throw CommandError.conflictingOptions("--arrival", "--departure")
        }

        return arrival
    }

    func outputFormat() throws -> OutputFormat {
        try OutputFormat.resolve(value(for: "--format", short: "-o"))
    }

    func timetable() throws -> IDOSTimetable {
        try IDOSTimetable.resolve(value(for: "--timetable", short: "-T"))
    }

    private func optionValue(for longName: String, short shortName: String? = nil) -> (name: String, value: String)? {
        for index in arguments.indices {
            let argument = arguments[index]
            let names = [longName, shortName].compactMap(\.self)

            for name in names {
                if argument == name, arguments.indices.contains(index + 1) {
                    return (name, arguments[index + 1])
                }

                if argument.hasPrefix("\(name)=") {
                    return (name, String(argument.dropFirst(name.count + 1)))
                }
            }
        }

        return nil
    }
}
