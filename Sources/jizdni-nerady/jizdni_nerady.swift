import Foundation
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
            Jízdní neřády

            Vyhledejte občasné spojení nebo položku našeptávače IDOS.
            Pro nápovědu spusťte jizdni-nerady --help.
            """
        }

        do {
            switch command {
            case "suggest":
                return try await suggestOutput(for: Array(arguments.dropFirst()))
            case "spojeni":
                return try await connectionsOutput(for: Array(arguments.dropFirst()))
            default:
                return "Neznámý příkaz: \(command)\n\n\(helpText)"
            }
        } catch {
            return "Chyba: \(error.localizedDescription)"
        }
    }

    private func suggestOutput(for arguments: [String]) async throws -> String {
        let options = CommandOptions(arguments)
        let limit = options.integerValue(for: "--limit") ?? 8
        let prefix = options.positional.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !prefix.isEmpty else {
            return "Použití: jizdni-nerady suggest <text> [--limit počet]"
        }

        let suggestions = try await client.suggest(prefix: prefix, limit: limit)

        guard !suggestions.isEmpty else {
            return "Našeptávač nic nenašel."
        }

        return (["Nalezené položky:"] + suggestions.enumerated().map { index, suggestion in
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

        guard let from = options.value(for: "--from", short: "-f"), !from.isEmpty else {
            return "Použití: jizdni-nerady spojeni --from místo --to místo [--date d.m.rrrr] [--time h:mm] [--limit počet]"
        }

        guard let to = options.value(for: "--to", short: "-t"), !to.isEmpty else {
            return "Použití: jizdni-nerady spojeni --from místo --to místo [--date d.m.rrrr] [--time h:mm] [--limit počet]"
        }

        let request = IDOSConnectionRequest(
            from: from,
            to: to,
            date: options.value(for: "--date"),
            time: options.value(for: "--time")
        )
        let limit = options.integerValue(for: "--limit") ?? 5
        let connections = try await client.findConnections(request: request)

        guard !connections.isEmpty else {
            return "IDOS nevrátil žádné spojení."
        }

        let limitedConnections = connections.prefix(max(1, limit))
        let rows = limitedConnections.enumerated().map { index, connection in
            connection.summaryLine(number: index + 1)
        }

        return """
        Spojení \(from) -> \(to):
        \(rows.joined(separator: "\n"))
        """
    }

    private var helpText: String {
        """
        Použití:
          jizdni-nerady suggest <text> [--limit počet]
          jizdni-nerady spojeni --from místo --to místo [--date d.m.rrrr] [--time h:mm] [--limit počet]

        Volby:
          -h, --help     Zobrazí nápovědu
          --version      Zobrazí verzi aplikace
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
}
