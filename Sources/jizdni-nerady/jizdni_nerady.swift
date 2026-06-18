import Foundation
import JizdniNerady
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct JizdniNeradyApp {
    static func main() async {
        let runner = CommandRunner()
        print(await runner.output(for: CommandLine.arguments.dropFirst()))
    }
}

struct CommandRunner {
    let version = "0.1.0"
    let client: IDOSClienting

    init(client: IDOSClienting = IDOSClient()) {
        self.client = client
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
            🚆 jizdni-nerady

            Search occasional IDOS connections or suggested places.
            Run jizdni-nerady --help for usage.
            """
        }

        do {
            switch command {
            case "suggest":
                return try await suggestOutput(for: Array(arguments.dropFirst()))
            case "connections":
                return try await connectionsOutput(for: Array(arguments.dropFirst()))
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
        let format = try options.outputFormat()
        let limit = options.integerValue(for: "--limit") ?? 8
        let timetable = try options.timetable()
        let prefix = options.positional.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !prefix.isEmpty else {
            throw CommandError.usage("Usage: jizdni-nerady suggest <text> [--timetable alias] [--format text|markdown|json] [--limit count]")
        }

        let suggestions = try await client.suggest(prefix: prefix, limit: limit, timetable: timetable)
        return try format.renderSuggestions(
            SuggestedPlacesOutput(query: prefix, timetable: timetable, suggestions: suggestions)
        )
    }

    private func connectionsOutput(for arguments: [String]) async throws -> String {
        let options = CommandOptions(arguments)
        let format = try options.outputFormat()
        let timetable = try options.timetable()

        guard let from = options.value(for: "--from", short: "-f"), !from.isEmpty else {
            throw CommandError.usage("Usage: jizdni-nerady connections --from place --to place [--timetable alias] [--date d.m.yyyy] [--time h:mm] [--arrival|--departure] [--direct] [--max-transfers count] [--format text|markdown|json] [--limit count]")
        }

        guard let to = options.value(for: "--to", short: "-t"), !to.isEmpty else {
            throw CommandError.usage("Usage: jizdni-nerady connections --from place --to place [--timetable alias] [--date d.m.yyyy] [--time h:mm] [--arrival|--departure] [--direct] [--max-transfers count] [--format text|markdown|json] [--limit count]")
        }

        let request = IDOSConnectionRequest(
            timetable: timetable,
            from: from,
            to: to,
            date: options.value(for: "--date"),
            time: options.value(for: "--time"),
            isArrival: try options.isArrivalTimeMode(),
            onlyDirect: options.contains("--direct") || options.contains("--only-direct"),
            maxTransfers: try options.nonNegativeIntegerValue(for: "--max-transfers")
        )
        let limit = options.integerValue(for: "--limit") ?? 5
        let connections = try await client.findConnections(request: request)
        return try format.renderConnections(
            ConnectionsOutput(request: request, connections: Array(connections.prefix(max(1, limit))))
        )
    }

    private func timetablesOutput(for arguments: [String]) throws -> String {
        let options = CommandOptions(arguments)
        let format = try options.outputFormat()
        return try format.renderTimetables(TimetablesOutput(timetables: IDOSTimetable.known))
    }

    private var helpText: String {
        """
        🚆 Usage:
          jizdni-nerady suggest <text> [--timetable alias] [--format text|markdown|json] [--limit count]
          jizdni-nerady connections --from place --to place [--timetable alias] [--date d.m.yyyy] [--time h:mm] [--arrival|--departure] [--direct] [--max-transfers count] [--format text|markdown|json] [--limit count]
          jizdni-nerady timetables [--format text|markdown|json]

        ⚙️ Options:
          -h, --help              Show help
          --version               Show the app version
          --arrival               Search by arrival time instead of departure time
          --departure             Search by departure time
          --direct, --only-direct Direct connections only
          --max-transfers         Maximum transfers permitted, including 0
          --format                Output format: text, markdown, or json

        Default timetable is vlakyautobusymhdvse.
        """
    }
}

private enum CommandError: LocalizedError {
    case invalidOutputFormat(String)
    case invalidNonNegativeInteger(name: String, value: String)
    case conflictingOptions(String, String)
    case usage(String)

    var errorDescription: String? {
        switch self {
        case .invalidOutputFormat(let value):
            return "Invalid output format: \(value). Use text, markdown, or json."
        case .invalidNonNegativeInteger(let name, let value):
            return "Invalid \(name): \(value). Use a non-negative integer."
        case .conflictingOptions(let first, let second):
            return "Conflicting options: \(first) and \(second). Use only one."
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
            🧭 Connections \(output.request.from) → \(output.request.to) (\(output.request.timetable.displayName)):
            \(rows.joined(separator: "\n"))
            """
        case .markdown:
            guard !output.connections.isEmpty else {
                return """
                ## 🧭 Connections

                **From:** \(Markdown.escape(output.request.from))
                **To:** \(Markdown.escape(output.request.to))
                **Timetable:** \(Markdown.escape(output.request.timetable.displayName))

                No connections found.
                """
            }

            let sections = output.connections.enumerated().map { index, connection in
                let legs = connection.legs.map { leg in
                    "| \(Markdown.lineName(leg)) | \(Markdown.escape(leg.fromStation)) | \(Markdown.escape(leg.departureTime)) | \(Markdown.escape(leg.toStation)) | \(Markdown.escape(leg.arrivalTime)) |"
                }.joined(separator: "\n")

                return """
                ### \(index + 1). \(Markdown.escape(connection.departureTime)) \(Markdown.escape(connection.departureStation)) → \(Markdown.escape(connection.arrivalTime)) \(Markdown.escape(connection.arrivalStation))

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
            **Timetable:** \(Markdown.escape(output.request.timetable.displayName))

            \(sections)
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

    private func suggestionDetails(_ suggestion: IDOSSuggestion) -> [String] {
        var details: [String] = []
        for value in [suggestion.description, suggestion.region].compactMap(\.self) where !value.isEmpty {
            if !details.contains(where: { $0.localizedCaseInsensitiveContains(value) }) {
                details.append(value)
            }
        }
        return details
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

private struct TimetablesOutput: Codable {
    var timetables: [IDOSTimetable]
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

    static func lineName(_ leg: IDOSConnectionLeg) -> String {
        let name = htmlEscape(leg.name)
        guard let color = leg.color, !color.isEmpty else {
            return escape(leg.name)
        }
        return "<span style=\"color: \(htmlEscape(color))\">\(name)</span>"
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
