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
                return timetablesOutput
            default:
                return "❌ Unknown command: \(command)\n\n\(helpText)"
            }
        } catch {
            return "❌ Error: \(error.localizedDescription)"
        }
    }

    private func suggestOutput(for arguments: [String]) async throws -> String {
        let options = CommandOptions(arguments)
        let limit = options.integerValue(for: "--limit") ?? 8
        let timetable = try options.timetable()
        let prefix = options.positional.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !prefix.isEmpty else {
            return "Usage: jizdni-nerady suggest <text> [--timetable alias] [--limit count]"
        }

        let suggestions = try await client.suggest(prefix: prefix, limit: limit, timetable: timetable)

        guard !suggestions.isEmpty else {
            return "🔎 No suggested places found."
        }

        return (["🔎 Suggested places (\(timetable.displayName)):"] + suggestions.enumerated().map { index, suggestion in
            var details: [String] = []
            for value in [suggestion.description, suggestion.region].compactMap(\.self) where !value.isEmpty {
                if !details.contains(where: { $0.localizedCaseInsensitiveContains(value) }) {
                    details.append(value)
                }
            }
            let detail = details.joined(separator: ", ")
            return "\(index + 1). \(suggestion.text)\(detail.isEmpty ? "" : " - \(detail)")"
        }).joined(separator: "\n")
    }

    private func connectionsOutput(for arguments: [String]) async throws -> String {
        let options = CommandOptions(arguments)
        let timetable = try options.timetable()

        guard let from = options.value(for: "--from", short: "-f"), !from.isEmpty else {
            return "Usage: jizdni-nerady connections --from place --to place [--timetable alias] [--date d.m.yyyy] [--time h:mm] [--direct] [--limit count]"
        }

        guard let to = options.value(for: "--to", short: "-t"), !to.isEmpty else {
            return "Usage: jizdni-nerady connections --from place --to place [--timetable alias] [--date d.m.yyyy] [--time h:mm] [--direct] [--limit count]"
        }

        let request = IDOSConnectionRequest(
            timetable: timetable,
            from: from,
            to: to,
            date: options.value(for: "--date"),
            time: options.value(for: "--time"),
            onlyDirect: options.contains("--direct") || options.contains("--only-direct")
        )
        let limit = options.integerValue(for: "--limit") ?? 5
        let connections = try await client.findConnections(request: request)

        guard !connections.isEmpty else {
            return "🔎 IDOS returned no connections."
        }

        let limitedConnections = connections.prefix(max(1, limit))
        let rows = limitedConnections.enumerated().map { index, connection in
            connection.summaryLine(number: index + 1)
        }

        return """
        🧭 Connections \(from) → \(to) (\(timetable.displayName)):
        \(rows.joined(separator: "\n"))
        """
    }

    private var timetablesOutput: String {
        let rows = IDOSTimetable.known.map { timetable in
            "  \(timetable.slug) - \(timetable.displayName)"
        }

        return """
        🗂 Timetables:
        \(rows.joined(separator: "\n"))

        --timetable also accepts a custom IDOS URL slug when IDOS supports it.
        """
    }

    private var helpText: String {
        """
        🚆 Usage:
          jizdni-nerady suggest <text> [--timetable alias] [--limit count]
          jizdni-nerady connections --from place --to place [--timetable alias] [--date d.m.yyyy] [--time h:mm] [--direct] [--limit count]
          jizdni-nerady timetables

        ⚙️ Options:
          -h, --help              Show help
          --version               Show the app version
          --direct, --only-direct Direct connections only

        Default timetable is vlakyautobusymhdvse.
        """
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

    func contains(_ name: String) -> Bool {
        arguments.contains(name)
    }

    func timetable() throws -> IDOSTimetable {
        try IDOSTimetable.resolve(value(for: "--timetable"))
    }
}
