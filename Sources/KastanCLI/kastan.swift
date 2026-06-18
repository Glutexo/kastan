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

    init(client: IDOSClienting = IDOSClient(), aliasFile: StopAliasFile = StopAliasFile()) {
        self.client = client
        self.aliasFile = aliasFile
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
                return "❌ Unknown command: \(command)\n\n\(helpText)"
            }
        } catch {
            return OutputFormat.preferredErrorFormat(in: arguments).renderError(error.localizedDescription)
        }
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
            allowedFlags: ["--arrival", "--departure", "--direct", "--only-direct"],
            allowedValueOptions: [
                "--from", "-f", "--to", "-t", "--via", "--timetable", "--date", "--time",
                "--max-transfers", "--min-transfer-time", "--format", "--limit",
            ]
        )
        let format = try options.outputFormat()
        let aliasDatabase = try aliasFile.load()

        guard let from = options.value(for: "--from", short: "-f"), !from.isEmpty else {
            throw CommandError.usage("Usage: kastan connections --from place --to place [--via place] [--timetable alias] [--date d.m.yyyy] [--time h:mm] [--arrival|--departure] [--direct] [--max-transfers count] [--min-transfer-time minutes] [--format text|markdown|json] [--limit count]")
        }

        guard let to = options.value(for: "--to", short: "-t"), !to.isEmpty else {
            throw CommandError.usage("Usage: kastan connections --from place --to place [--via place] [--timetable alias] [--date d.m.yyyy] [--time h:mm] [--arrival|--departure] [--direct] [--max-transfers count] [--min-transfer-time minutes] [--format text|markdown|json] [--limit count]")
        }

        let fromPlace = resolvePlace(from, in: aliasDatabase)
        let toPlace = resolvePlace(to, in: aliasDatabase)
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
        return try format.renderConnections(
            ConnectionsOutput(request: request, connections: Array(connections.prefix(max(1, limit))))
        )
    }

    private func departuresOutput(for arguments: [String]) async throws -> String {
        let options = CommandOptions(arguments)
        try options.rejectUnknownOptions(
            allowedFlags: ["--arrival", "--departure"],
            allowedValueOptions: ["--station", "-s", "--timetable", "--date", "--time", "--format", "--limit"]
        )
        let format = try options.outputFormat()
        let aliasDatabase = try aliasFile.load()

        guard let station = options.value(for: "--station", short: "-s"), !station.isEmpty else {
            throw CommandError.usage("Usage: kastan departures --station place [--timetable alias] [--date d.m.yyyy] [--time h:mm] [--arrival|--departure] [--format text|markdown|json] [--limit count]")
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

    private var helpText: String {
        """
        🌰 Usage:
          kastan suggest <text> [--timetable alias] [--format text|markdown|json] [--limit count]
          kastan connections --from place --to place [--via place] [--timetable alias] [--date d.m.yyyy] [--time h:mm] [--arrival|--departure] [--direct] [--max-transfers count] [--min-transfer-time minutes] [--format text|markdown|json] [--limit count]
          kastan departures --station place [--timetable alias] [--date d.m.yyyy] [--time h:mm] [--arrival|--departure] [--format text|markdown|json] [--limit count]
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
          --max-transfers         Maximum transfers permitted, including 0
          --min-transfer-time     Minimum transfer time in minutes, including 0
          --format                Output format: text, markdown, or json

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
    case unknownOption(String)
    case usage(String)

    var errorDescription: String? {
        switch self {
        case .invalidOutputFormat(let value):
            return "Invalid output format: \(value). Use text, markdown, or json."
        case .invalidNonNegativeInteger(let name, let value):
            return "Invalid \(name): \(value). Use a non-negative integer."
        case .conflictingOptions(let first, let second):
            return "Conflicting options: \(first) and \(second). Use only one."
        case .aliasTimetableMismatch(let alias, let aliasTimetable, let requestedTimetable):
            return "Stop alias \(alias) belongs to \(aliasTimetable.displayName), but requested timetable is \(requestedTimetable.displayName)."
        case .conflictingAliasTimetables(let first, let second):
            return "Stop aliases use conflicting timetables: \(first.displayName) and \(second.displayName). Use --timetable only when all used aliases belong to it."
        case .unknownOption(let value):
            return "Unknown option: \(value)."
        case .usage(let message):
            return message
        }
    }
}

private enum OutputFormat: String {
    case text
    case markdown
    case json

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
        case .text:
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
                    "| \(Markdown.lineName(leg)) | \(Markdown.escape(leg.fromStation)) | \(Markdown.bold(leg.departureTime)) | \(Markdown.escape(leg.toStation)) | \(Markdown.bold(leg.arrivalTime)) |"
                }.joined(separator: "\n")

                return """
                ### \(index + 1). \(Markdown.bold(connection.departureTime)) \(Markdown.escape(connection.departureStation)) → \(Markdown.bold(connection.arrivalTime)) \(Markdown.escape(connection.arrivalStation))

                Duration: **\(Markdown.escape(connection.duration))**

                | Line | From | Departure | To | Arrival |
                | --- | --- | --- | --- | --- |
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
        }
    }

    func renderDepartures(_ output: DeparturesOutput) throws -> String {
        let title = output.request.isArrival ? "Arrivals" : "Departures"

        switch self {
        case .text:
            guard !output.departures.isEmpty else {
                return "🔎 IDOS returned no \(title.lowercased())."
            }

            let rows = output.departures.enumerated().map { index, departure in
                departure.summaryLine(number: index + 1)
            }

            return """
            🚏 \(title) \(output.request.station) (\(output.request.timetable.displayName)):
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
                "| \(index + 1) | \(Markdown.bold(departure.time)) | \(Markdown.departureLineName(departure)) | \(Markdown.escape(departure.destination)) | \(Markdown.escape(departure.platform ?? "")) | \(Markdown.escape(departure.via ?? "")) | \(Markdown.escape(departure.delay ?? "")) |"
            }.joined(separator: "\n")

            return """
            ## 🚏 \(title)

            **Station:** \(Markdown.escape(output.request.station))
            **Timetable:** \(Markdown.escape(output.request.timetable.displayName))

            | # | Time | Line | Destination | Platform | Via | Delay |
            | ---: | --- | --- | --- | --- | --- | --- |
            \(rows)
            """
        case .json:
            return try JSON.write(output)
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

private struct ErrorOutput: Codable {
    var error: String
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
        var values: [String] = []
        var skipNext = false

        for argument in arguments {
            if skipNext {
                skipNext = false
                continue
            }

            if argument.hasPrefix("--") || argument.hasPrefix("-") {
                skipNext = !argument.contains("=")
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
