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
        let arguments = Array(arguments)

        if arguments.contains("--help") || arguments.contains("-h") {
            return helpText
        }

        if arguments.contains("--version") {
            return version
        }

        guard let command = arguments.first else {
            return """
            🌰 Kaštan

            Search occasional IDOS connections or suggested places.
            Run kastan --help for usage.
            """
        }

        do {
            switch command {
            case "suggest":
                return try await suggestOutput(for: Array(arguments.dropFirst()))
            case "connections":
                return try await connectionsOutput(for: Array(arguments.dropFirst()))
            case "departures":
                return try await departuresOutput(for: Array(arguments.dropFirst()))
            case "aliases":
                return try aliasesOutput(for: Array(arguments.dropFirst()))
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
        try options.rejectUnknownOptions(allowedValueOptions: ["--timetable", "--format", "--limit"])
        let format = try options.outputFormat()
        let limit = options.integerValue(for: "--limit") ?? 8
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

    private func connectionsOutput(for arguments: [String]) async throws -> String {
        let options = CommandOptions(arguments)
        try options.rejectUnknownOptions(
            allowedFlags: ["--arrival", "--departure", "--direct", "--only-direct", "--add-to-calendar"],
            allowedValueOptions: [
                "--from", "-f", "--to", "-t", "--via", "--timetable", "--date", "--time",
                "--max-transfers", "--min-transfer-time", "--format", "--limit",
            ]
        )
        let format = try options.outputFormat()
        if options.contains("--add-to-calendar") && format == .ics {
            throw CommandError.conflictingOptions("--add-to-calendar", "--format ics")
        }

        let aliasDatabase = try aliasFile.load()

        let endpoints = try connectionEndpoints(
            from: options.value(for: "--from", short: "-f"),
            to: options.value(for: "--to", short: "-t"),
            positional: positionalValues(in: options)
        )

        let fromPlace = resolvePlace(endpoints.from, in: aliasDatabase)
        let toPlace = resolvePlace(endpoints.to, in: aliasDatabase)
        let viaPlaces = options.values(for: "--via").map { resolvePlace($0, in: aliasDatabase) }
        let timetable = try resolveTimetable(
            explicitValue: options.value(for: "--timetable"),
            aliases: ([fromPlace, toPlace] + viaPlaces).compactMap(\.alias)
        )

        let request = IDOSConnectionRequest(
            timetable: timetable,
            from: fromPlace.station,
            to: toPlace.station,
            date: options.value(for: "--date"),
            time: options.value(for: "--time"),
            isArrival: try options.isArrivalTimeMode(),
            onlyDirect: options.contains("--direct") || options.contains("--only-direct"),
            via: viaPlaces.map(\.station),
            maxTransfers: try options.nonNegativeIntegerValue(for: "--max-transfers"),
            minimumTransferTime: try options.nonNegativeIntegerValue(for: "--min-transfer-time")
        )
        let limit = options.integerValue(for: "--limit") ?? 5
        let connections = try await client.findConnections(request: request)
        if format == .ics || options.contains("--add-to-calendar") {
            guard let connection = connections.first else {
                throw CommandError.usage("IDOS returned no connections.")
            }

            let calendar = try await client.connectionCalendar(for: connection, timetable: request.timetable)
            if options.contains("--add-to-calendar") {
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
            ConnectionsOutput(request: request, connections: Array(connections.prefix(max(1, limit))))
        )
    }

    private func departuresOutput(for arguments: [String]) async throws -> String {
        let options = CommandOptions(arguments)
        try options.rejectUnknownOptions(
            allowedFlags: ["--arrival", "--departure"],
            allowedValueOptions: ["--station", "-s", "--from", "-f", "--timetable", "--date", "--time", "--format", "--limit"]
        )
        let format = try options.outputFormat()
        let aliasDatabase = try aliasFile.load()

        guard let station = departureStation(in: options), !station.isEmpty else {
            throw CommandError.usage(departuresUsage)
        }

        let stationPlace = resolvePlace(station, in: aliasDatabase)
        let timetable = try resolveTimetable(
            explicitValue: options.value(for: "--timetable"),
            aliases: [stationPlace.alias].compactMap(\.self)
        )

        let request = IDOSDeparturesRequest(
            timetable: timetable,
            station: stationPlace.station,
            date: options.value(for: "--date"),
            time: options.value(for: "--time"),
            isArrival: try options.isArrivalTimeMode()
        )
        let limit = options.integerValue(for: "--limit") ?? 10
        let departures = try await client.findDepartures(request: request)
        return try format.renderDepartures(
            DeparturesOutput(request: request, departures: Array(departures.prefix(max(1, limit))))
        )
    }

    private func timetablesOutput(for arguments: [String]) throws -> String {
        let options = CommandOptions(arguments)
        try options.rejectUnknownOptions(allowedValueOptions: ["--format"])
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

    private func aliasesOutput(for arguments: [String]) throws -> String {
        guard let action = arguments.first else {
            throw CommandError.usage("Usage: kastan aliases list|add|remove|path")
        }

        let actionArguments = Array(arguments.dropFirst())
        let options = CommandOptions(actionArguments)

        switch action {
        case "list":
            try options.rejectUnknownOptions(allowedValueOptions: ["--format"])
            let format = try options.outputFormat()
            return try format.renderStopAliases(StopAliasesOutput(
                aliases: aliasFile.load().aliases,
                path: aliasFile.fileURL.path
            ))

        case "add":
            try options.rejectUnknownOptions(allowedValueOptions: ["--station", "-s", "--timetable", "--format"])
            let format = try options.outputFormat()

            guard let name = options.positional.first, !name.isEmpty,
                  let station = options.value(for: "--station", short: "-s"), !station.isEmpty,
                  let timetableValue = options.value(for: "--timetable"), !timetableValue.isEmpty
            else {
                throw CommandError.usage("Usage: kastan aliases add name --station place --timetable alias [--format text|markdown|json]")
            }

            let timetable = try IDOSTimetable.resolve(timetableValue)
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
            try options.rejectUnknownOptions(allowedValueOptions: ["--format"])
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
            try options.rejectUnknownOptions(allowedValueOptions: ["--format"])
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
            "--from", "-f", "--to", "-t", "--via", "--station", "-s", "--timetable", "--date", "--time",
            "--max-transfers", "--min-transfer-time", "--format", "--limit",
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
        "Usage: kastan connections route|from to|--from place --to place [--via place] [--timetable alias] [--date d.m.yyyy] [--time h:mm] [--arrival|--departure] [--direct] [--max-transfers count] [--min-transfer-time minutes] [--add-to-calendar] [--format text|markdown|json|ics] [--limit count]"
    }

    private var departuresUsage: String {
        "Usage: kastan departures station|--from place|--station place [--timetable alias] [--date d.m.yyyy] [--time h:mm] [--arrival|--departure] [--format text|markdown|json] [--limit count]"
    }

    private var helpText: String {
        """
        🌰 Usage:
          kastan route|from to
          kastan station
          kastan suggest <text> [--timetable alias] [--format text|markdown|json] [--limit count]
          kastan connections route|from to|--from place --to place [--via place] [--timetable alias] [--date d.m.yyyy] [--time h:mm] [--arrival|--departure] [--direct] [--max-transfers count] [--min-transfer-time minutes] [--add-to-calendar] [--format text|markdown|json|ics] [--limit count]
          kastan departures station|--from place|--station place [--timetable alias] [--date d.m.yyyy] [--time h:mm] [--arrival|--departure] [--format text|markdown|json] [--limit count]
          kastan aliases list|add|remove|path [--format text|markdown|json]
          kastan timetables [--format text|markdown|json]

        ⚙️ Options:
          -h, --help              Show help
          --version               Show the app version
          --arrival               Search by arrival time instead of departure time
          --departure             Search by departure time
          --station               Station for departures or arrivals
          --via                   Via place, repeat for multiple places
          --direct, --only-direct Direct connections only
          --add-to-calendar       Open the first returned connection as an iCalendar import
          --max-transfers         Maximum transfers permitted, including 0
          --min-transfer-time     Minimum transfer time in minutes, including 0
          --format                Output format: text, markdown, json, or ics for connections

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
            return "> ❌ Error: \(Markdown.escape(message))"
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

    func renderConnections(_ output: ConnectionsOutput) throws -> String {
        switch self {
        case .text:
            guard !output.connections.isEmpty else {
                return "🔎 IDOS returned no connections."
            }

            let rows = output.connections.enumerated().map { index, connection in
                connection.summaryLine(number: index + 1)
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

            let sections = output.connections.enumerated().map { index, connection in
                let legs = connection.legs.map { leg in
                    "| \(Markdown.lineName(leg)) | \(Markdown.escape(leg.fromStation)) | \(Markdown.escape(leg.fromTariffZone ?? "")) | \(Markdown.escape(leg.fromPlatform ?? "")) | \(Markdown.bold(leg.departureTime)) | \(Markdown.escape(leg.toStation)) | \(Markdown.escape(leg.toTariffZone ?? "")) | \(Markdown.escape(leg.toPlatform ?? "")) | \(Markdown.bold(leg.arrivalTime)) |"
                }.joined(separator: "\n")

                return """
                ### \(index + 1). \(Markdown.bold(connection.departureTime)) \(Markdown.escape(connection.departureStation)) → \(Markdown.bold(connection.arrivalTime)) \(Markdown.escape(connection.arrivalStation))

                Duration: **\(Markdown.escape(connection.duration))**

                | Line | From | From Tariff Zone | From Platform | Departure | To | To Tariff Zone | To Platform | Arrival |
                | --- | --- | --- | --- | --- | --- | --- | --- | --- |
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
                departure.summaryLine(number: index + 1)
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
                "| \(index + 1) | \(Markdown.bold(departure.time)) | \(Markdown.departureLineName(departure)) | \(Markdown.escape(departure.destination)) | \(Markdown.escape(departure.tariffZone ?? "")) | \(Markdown.escape(departure.platform ?? "")) | \(Markdown.escape(departure.via ?? "")) | \(Markdown.escape(departure.delay ?? "")) |"
            }.joined(separator: "\n")

            return """
            ## 🚏 \(title)

            **Station:** \(Markdown.escape(stationName))
            **Timetable:** \(Markdown.escape(output.request.timetable.displayName))

            | # | Time | Line | Destination | Tariff Zone | Platform | Via | Delay |
            | ---: | --- | --- | --- | --- | --- | --- | --- |
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

    private func suggestionDetails(_ suggestion: IDOSSuggestion) -> [String] {
        var details: [String] = []
        for value in [suggestion.description, suggestion.region].compactMap(\.self) where !value.isEmpty {
            if !details.contains(where: { $0.localizedCaseInsensitiveContains(value) }) {
                details.append(value)
            }
        }
        return details
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

private struct ConnectionsOutput: Codable {
    var request: IDOSConnectionRequest
    var connections: [IDOSConnection]
}

private struct DeparturesOutput: Codable {
    var request: IDOSDeparturesRequest
    var departures: [IDOSDeparture]
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

private struct ConnectionEndpoints {
    var from: String
    var to: String
}

private struct ErrorOutput: Codable {
    var error: String
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
    let arguments: [String]

    init(_ arguments: [String]) {
        self.arguments = arguments
    }

    var positional: [String] {
        positional(valueOptions: Set(arguments.filter { $0.hasPrefix("-") }))
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

    func values(for name: String) -> [String] {
        var values: [String] = []

        for index in arguments.indices {
            let argument = arguments[index]

            if argument == name, arguments.indices.contains(index + 1) {
                values.append(arguments[index + 1])
            }

            if argument.hasPrefix("\(name)=") {
                values.append(String(argument.dropFirst(name.count + 1)))
            }
        }

        return values.filter { !$0.isEmpty }
    }

    func integerValue(for name: String) -> Int? {
        value(for: name).flatMap(Int.init)
    }

    func nonNegativeIntegerValue(for name: String) throws -> Int? {
        guard let value = value(for: name) else {
            return nil
        }

        guard let integer = Int(value), integer >= 0 else {
            throw CommandError.invalidNonNegativeInteger(name: name, value: value)
        }

        return integer
    }

    func contains(_ name: String) -> Bool {
        arguments.contains(name)
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
        let arrival = contains("--arrival")
        let departure = contains("--departure")

        guard !(arrival && departure) else {
            throw CommandError.conflictingOptions("--arrival", "--departure")
        }

        return arrival
    }

    func outputFormat() throws -> OutputFormat {
        try OutputFormat.resolve(value(for: "--format"))
    }

    func timetable() throws -> IDOSTimetable {
        try IDOSTimetable.resolve(value(for: "--timetable"))
    }
}
