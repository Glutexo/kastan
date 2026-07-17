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

/// Executes one Kaštan CLI invocation and renders its human-readable output in the selected language.
struct CommandRunner {
    let version = "0.1.0"
    let client: IDOSClienting
    let aliasFile: StopAliasFile
    let calendarImporter: CalendarImporting
    let preferredLanguageIdentifiers: [String]
    let environment: [String: String]

    init(
        client: IDOSClienting = IDOSClient(),
        aliasFile: StopAliasFile = StopAliasFile(),
        calendarImporter: CalendarImporting = SystemCalendarImporter(),
        preferredLanguageIdentifiers: [String] = Locale.preferredLanguages,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.client = client
        self.aliasFile = aliasFile
        self.calendarImporter = calendarImporter
        self.preferredLanguageIdentifiers = preferredLanguageIdentifiers
        self.environment = environment
    }

    func output<S: Sequence<String>>(for arguments: S) async -> String {
        let originalArguments = CommandOptions.normalized(Array(arguments))
        var localization = Localization(language: AppLanguage.preferred(
            languageIdentifiers: preferredLanguageIdentifiers,
            environment: environment
        ))
        var arguments = originalArguments

        do {
            let invocation = try localizedInvocation(arguments)
            localization = invocation.localization
            arguments = invocation.arguments

            if arguments.contains("--help") || arguments.contains("-h") {
                return localization.text(.help)
            }

            if arguments.contains("--version") {
                return version
            }

            guard let command = arguments.first else {
                return """
                🌰 Kaštan

                \(localization.text(.appDescription))
                \(localization.text(.appHelpHint))
                """
            }

            switch command {
            case "suggest":
                return try await suggestOutput(for: Array(arguments.dropFirst()), localization: localization)
            case "stations":
                return try await stationsOutput(for: Array(arguments.dropFirst()), localization: localization)
            case "connections":
                return try await connectionsOutput(for: Array(arguments.dropFirst()), localization: localization)
            case "departures":
                return try await departuresOutput(for: Array(arguments.dropFirst()), localization: localization)
            case "station-timetables", "station-timetable":
                return try await stationTimetablesOutput(for: Array(arguments.dropFirst()), localization: localization)
            case "service":
                return try await serviceOutput(for: Array(arguments.dropFirst()), localization: localization)
            case "aliases":
                return try await aliasesOutput(for: Array(arguments.dropFirst()), localization: localization)
            case "timetables":
                return try timetablesOutput(for: Array(arguments.dropFirst()), localization: localization)
            default:
                if let output = try await shorthandOutput(for: arguments, localization: localization) {
                    return output
                }

                return "❌ \(localization.text(.unknownCommand, command))\n\n\(localization.text(.help))"
            }
        } catch {
            return OutputFormat.preferredErrorFormat(in: originalArguments).renderError(
                Self.errorMessage(for: error, localization: localization),
                localization: localization
            )
        }
    }

    /// Removes global language options before command parsing and resolves the invocation's output language.
    private func localizedInvocation(_ arguments: [String]) throws -> (arguments: [String], localization: Localization) {
        var remaining: [String] = []
        var requestedLanguage: AppLanguage?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--language" || argument == "--lang" {
                guard arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("-") else {
                    throw CommandError.missingLanguage(argument)
                }

                let value = arguments[index + 1]
                guard let language = AppLanguage(identifier: value) else {
                    throw CommandError.invalidLanguage(value)
                }

                requestedLanguage = language
                index += 2
                continue
            }

            if argument.hasPrefix("--language=") || argument.hasPrefix("--lang=") {
                let value = argument
                    .split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    .last
                    .map(String.init) ?? ""
                guard !value.isEmpty else {
                    throw CommandError.missingLanguage(String(argument.prefix { $0 != "=" }))
                }
                guard let language = AppLanguage(identifier: value) else {
                    throw CommandError.invalidLanguage(value)
                }

                requestedLanguage = language
                index += 1
                continue
            }

            remaining.append(argument)
            index += 1
        }

        let language = requestedLanguage ?? AppLanguage.preferred(
            languageIdentifiers: preferredLanguageIdentifiers,
            environment: environment
        )
        return (remaining, Localization(language: language))
    }

    /// Translates product and library errors while preserving useful platform-provided error details.
    private static func errorMessage(for error: Error, localization: Localization) -> String {
        if let error = error as? CommandError {
            return error.message(localization: localization)
        }

        if let error = error as? IDOSError {
            switch error {
            case .invalidResponse:
                return localization.text(.idosInvalidResponse)
            case .invalidURL:
                return localization.text(.idosInvalidURL)
            case .invalidJSONP:
                return localization.text(.idosInvalidJSONP)
            case .invalidTimetable(let value):
                return localization.text(.idosInvalidTimetable, value)
            case .networkUnavailable(let detail):
                let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                return detail.isEmpty
                    ? localization.text(.networkUnavailable)
                    : localization.text(.networkUnavailableWithDetail, detail)
            case .calendarUnavailable:
                return localization.text(.calendarUnavailable)
            case .pdfUnavailable:
                return localization.text(.pdfUnavailable)
            case .stationTimetableUnavailable:
                return localization.text(.stationTimetableUnavailable)
            case .invalidServiceIdentifier(let value):
                return localization.text(.invalidServiceIdentifier, value)
            case .serviceDetailUnavailable(let detail):
                let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                return detail.isEmpty
                    ? localization.text(.serviceDetailUnavailable)
                    : localization.text(.serviceDetailUnavailableWithDetail, detail)
            }
        }

        if let error = error as? StopAliasError {
            switch error {
            case .aliasNotFound(let name):
                return localization.text(.aliasNotFound, name)
            case .invalidAliasName:
                return localization.text(.invalidAliasName)
            case .invalidStation:
                return localization.text(.invalidAliasStation)
            }
        }

        let localized = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localized.isEmpty else {
            return localization.text(.fallbackError)
        }

        return localized
    }

    private func suggestOutput(for arguments: [String], localization: Localization) async throws -> String {
        let options = CommandOptions(arguments)
        try options.rejectUnknownOptions(allowedValueOptions: ["--timetable", "-T", "--format", "-o", "--limit", "-l"])
        let format = try options.outputFormat()
        let limit = options.integerValue(for: "--limit", short: "-l") ?? 8
        let timetable = try options.timetable()
        let prefix = options.positional.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !prefix.isEmpty else {
            throw CommandError.usage(.usageSuggest)
        }

        let suggestions = try await client.suggest(prefix: prefix, limit: limit, timetable: timetable)
        return try format.renderSuggestions(
            SuggestedPlacesOutput(query: prefix, timetable: timetable, suggestions: suggestions),
            localization: localization
        )
    }

    private func stationsOutput(for arguments: [String], localization: Localization) async throws -> String {
        let options = CommandOptions(arguments)
        try options.rejectUnknownOptions(allowedValueOptions: ["--timetable", "-T", "--format", "-o", "--limit", "-l"])
        let format = try options.outputFormat()
        let limit = options.integerValue(for: "--limit", short: "-l") ?? 8
        let timetable = try options.timetable()
        let prefix = options.positional.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !prefix.isEmpty else {
            throw CommandError.usage(.usageStations)
        }

        let stations = try await client.searchStations(prefix: prefix, limit: limit, timetable: timetable)
        return try format.renderStations(
            StationsOutput(query: prefix, timetable: timetable, stations: stations),
            localization: localization
        )
    }

    private func connectionsOutput(for arguments: [String], localization: Localization) async throws -> String {
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
                throw CommandError.usage(.idosNoConnections)
            }

            let calendar = try await client.connectionCalendar(for: connection, timetable: request.timetable)
            if addToCalendar {
                let output = CalendarImportOutput(
                    request: request,
                    connection: connection,
                    path: try calendarImporter.add(calendar: calendar, fileName: "kastan-\(connection.id).ics").path
                )
                return try format.renderCalendarImport(output, localization: localization)
            }

            return calendar
        }

        return try format.renderConnections(
            ConnectionsOutput(
                request: request,
                connections: Array(connections.prefix(requestedLimit)),
                verbose: options.contains("--verbose", short: "-v")
            ),
            localization: localization
        )
    }

    private func departuresOutput(for arguments: [String], localization: Localization) async throws -> String {
        let options = CommandOptions(arguments)
        try options.rejectUnknownOptions(
            allowedFlags: ["--arrival", "-a", "--departure", "-p", "--verbose", "-v"],
            allowedValueOptions: ["--station", "-s", "--from", "-f", "--timetable", "-T", "--date", "-d", "--time", "-m", "--format", "-o", "--limit", "-l"]
        )
        let format = try options.outputFormat()
        let aliasDatabase = try aliasFile.load()

        guard let station = departureStation(in: options), !station.isEmpty else {
            throw CommandError.usage(.usageDepartures)
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
            ),
            localization: localization
        )
    }

    /// Searches the third IDOS mode using the selected MHD line, route direction, and service date.
    private func stationTimetablesOutput(
        for arguments: [String],
        localization: Localization
    ) async throws -> String {
        let options = CommandOptions(arguments)
        try options.rejectUnknownOptions(
            allowedFlags: ["--whole-week", "-w"],
            allowedValueOptions: [
                "--line", "-L", "--from", "-f", "--to", "-t", "--timetable", "-T",
                "--date", "-d", "--format", "-o",
            ]
        )
        let format = try options.outputFormat()
        let aliasDatabase = try aliasFile.load()
        guard let line = options.value(for: "--line", short: "-L")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !line.isEmpty,
            let from = options.value(for: "--from", short: "-f")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !from.isEmpty,
            let to = options.value(for: "--to", short: "-t")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !to.isEmpty
        else {
            throw CommandError.usage(.usageStationTimetables)
        }

        let fromPlace = resolvePlace(from, in: aliasDatabase)
        let toPlace = resolvePlace(to, in: aliasDatabase)
        let timetable = try resolveTimetable(
            explicitValue: options.value(for: "--timetable", short: "-T"),
            aliases: [fromPlace.alias, toPlace.alias].compactMap(\.self)
        )
        let request = IDOSStationTimetableRequest(
            timetable: timetable,
            line: line,
            from: fromPlace.station,
            to: toPlace.station,
            date: options.value(for: "--date", short: "-d"),
            wholeWeek: options.contains("--whole-week", short: "-w")
        )
        let stationTimetable = try await client.findStationTimetable(
            request: request,
            language: localization.language.idosLanguage
        )
        return try format.renderStationTimetable(
            StationTimetableOutput(request: request, stationTimetable: stationTimetable),
            localization: localization
        )
    }

    private func serviceOutput(for arguments: [String], localization: Localization) async throws -> String {
        let options = CommandOptions(arguments)
        try options.rejectUnknownOptions(allowedValueOptions: ["--timetable", "-T", "--format", "-o"])
        let format = try options.outputFormat()
        let positional = positionalValues(in: options)
        guard positional.count == 1 else {
            throw CommandError.usage(.usageService)
        }

        let timetable: IDOSTimetable
        if let timetableValue = options.value(for: "--timetable", short: "-T") {
            timetable = try IDOSTimetable.resolve(timetableValue)
        } else {
            timetable = .defaultTimetable
        }
        let service = try await client.serviceDetail(
            id: positional[0],
            timetable: timetable,
            language: localization.language.idosLanguage
        )
        return try format.renderServiceDetail(
            ServiceDetailOutput(service: service),
            localization: localization
        )
    }

    private func timetablesOutput(for arguments: [String], localization: Localization) throws -> String {
        let options = CommandOptions(arguments)
        try options.rejectUnknownOptions(allowedValueOptions: ["--format", "-o"])
        let format = try options.outputFormat()
        return try format.renderTimetables(
            TimetablesOutput(timetables: IDOSTimetable.known),
            localization: localization
        )
    }

    private func shorthandOutput(for arguments: [String], localization: Localization) async throws -> String? {
        let options = CommandOptions(arguments)

        if isConnectionShorthand(options) {
            return try await connectionsOutput(for: arguments, localization: localization)
        }

        if positionalValues(in: options).count == 1 {
            return try await departuresOutput(for: arguments, localization: localization)
        }

        return nil
    }

    private func aliasesOutput(for arguments: [String], localization: Localization) async throws -> String {
        guard let action = arguments.first else {
            throw CommandError.usage(.usageAliases)
        }

        let actionArguments = Array(arguments.dropFirst())
        let options = CommandOptions(actionArguments)

        switch action {
        case "list":
            try options.rejectUnknownOptions(allowedValueOptions: ["--format", "-o"])
            let format = try options.outputFormat()
            return try format.renderStopAliases(
                StopAliasesOutput(
                    aliases: aliasFile.load().aliases,
                    path: aliasFile.fileURL.path
                ),
                localization: localization
            )

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
                throw CommandError.usage(.usageAliasesAdd)
            }

            let timetable = try IDOSTimetable.resolve(timetableValue)
            try await rejectAmbiguousPlace(station, timetable: timetable, stationOnly: true)
            var database = try aliasFile.load()
            let action = database.alias(named: name) == nil ? "added" : "updated"
            let alias = StopAlias(name: name, station: station, timetable: timetable)
            try database.upsert(alias)
            try aliasFile.save(database)

            return try format.renderStopAliasMutation(
                StopAliasMutationOutput(
                    action: action,
                    alias: alias,
                    path: aliasFile.fileURL.path
                ),
                localization: localization
            )

        case "remove":
            try options.rejectUnknownOptions(allowedValueOptions: ["--format", "-o"])
            let format = try options.outputFormat()

            guard let name = options.positional.first, !name.isEmpty else {
                throw CommandError.usage(.usageAliasesRemove)
            }

            var database = try aliasFile.load()
            let alias = try database.remove(name: name)
            try aliasFile.save(database)

            return try format.renderStopAliasMutation(
                StopAliasMutationOutput(
                    action: "removed",
                    alias: alias,
                    path: aliasFile.fileURL.path
                ),
                localization: localization
            )

        case "path":
            try options.rejectUnknownOptions(allowedValueOptions: ["--format", "-o"])
            let format = try options.outputFormat()
            return try format.renderStopAliasPath(
                StopAliasPathOutput(path: aliasFile.fileURL.path),
                localization: localization
            )

        default:
            throw CommandError.usage(.usageAliases)
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
                kind: stationOnly ? .station : .place,
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
            throw CommandError.usage(.usageConnections)
        }

        let positional = positionalValues(positional)

        if positional.count == 2 {
            return ConnectionEndpoints(from: positional[0], to: positional[1])
        }

        let expression = positional.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty, let endpoints = parseConnectionExpression(expression) else {
            throw CommandError.usage(.usageConnections)
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

}

private enum CommandError: Error {
    case invalidLanguage(String)
    case missingLanguage(String)
    case invalidOutputFormat(String)
    case invalidNonNegativeInteger(name: String, value: String)
    case conflictingOptions(String, String)
    case aliasTimetableMismatch(alias: String, aliasTimetable: IDOSTimetable, requestedTimetable: IDOSTimetable)
    case conflictingAliasTimetables(IDOSTimetable, IDOSTimetable)
    case calendarImportUnavailable
    case unknownOption(String)
    case unsupportedOutputFormat(format: String, command: String)
    case ambiguousPlace(PlaceAmbiguity)
    case usage(LocalizationKey)

    func message(localization: Localization) -> String {
        switch self {
        case .invalidLanguage(let value):
            return localization.text(.invalidLanguage, value)
        case .missingLanguage(let option):
            return localization.text(.missingLanguage, option)
        case .invalidOutputFormat(let value):
            return localization.text(.invalidOutputFormat, value)
        case .invalidNonNegativeInteger(let name, let value):
            return localization.text(.invalidNonNegativeInteger, name, value)
        case .conflictingOptions(let first, let second):
            return localization.text(.conflictingOptions, first, second)
        case .aliasTimetableMismatch(let alias, let aliasTimetable, let requestedTimetable):
            return localization.text(
                .aliasTimetableMismatch,
                alias,
                localization.timetableName(aliasTimetable),
                localization.timetableName(requestedTimetable)
            )
        case .conflictingAliasTimetables(let first, let second):
            return localization.text(
                .conflictingAliasTimetables,
                localization.timetableName(first),
                localization.timetableName(second)
            )
        case .calendarImportUnavailable:
            return localization.text(.calendarImportUnavailable)
        case .unknownOption(let value):
            return localization.text(.unknownOption, value)
        case .unsupportedOutputFormat(let format, let command):
            return localization.text(.unsupportedOutputFormat, format, command)
        case .ambiguousPlace(let ambiguity):
            return ambiguity.message(localization: localization)
        case .usage(let key):
            return localization.text(key)
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
        let options = CommandOptions(arguments)
        return (try? options.outputFormat()) ?? .text
    }

    func renderError(_ message: String, localization: Localization) -> String {
        let label = localization.text(.errorLabel)
        switch self {
        case .text, .ics:
            return "❌ \(label): \(message)"
        case .markdown:
            let lines = message.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let first = lines.first else {
                return "> ❌ \(label)"
            }

            return (["> ❌ \(label): \(Markdown.escape(first))"] + lines.dropFirst().map { "> \(Markdown.escape($0))" })
                .joined(separator: "\n")
        case .json:
            return (try? JSON.write(ErrorOutput(error: message))) ?? #"{"error":"\#(message)"}"#
        }
    }

    func renderSuggestions(_ output: SuggestedPlacesOutput, localization: Localization) throws -> String {
        let title = localization.text(.suggestedPlaces)
        switch self {
        case .text:
            guard !output.suggestions.isEmpty else {
                return "🔎 \(localization.text(.noSuggestedPlaces))"
            }

            return (["🔎 \(title) (\(localization.timetableName(output.timetable))):"] + output.suggestions.enumerated().map { index, suggestion in
                let detail = suggestionDetails(suggestion).joined(separator: ", ")
                return "\(index + 1). \(suggestion.text)\(detail.isEmpty ? "" : " - \(detail)")"
            }).joined(separator: "\n")
        case .markdown:
            guard !output.suggestions.isEmpty else {
                return "## 🔎 \(title)\n\n\(localization.text(.noSuggestedPlaces))"
            }

            let rows = output.suggestions.enumerated().map { index, suggestion in
                "| \(index + 1) | \(Markdown.escape(suggestion.text)) | \(Markdown.escape(suggestionDetails(suggestion).joined(separator: ", "))) |"
            }.joined(separator: "\n")

            return """
            ## 🔎 \(title)

            \(localization.text(.timetable)): **\(Markdown.escape(localization.timetableName(output.timetable)))**

            | # | \(localization.text(.place)) | \(localization.text(.details)) |
            | ---: | --- | --- |
            \(rows)
            """
        case .json:
            return try JSON.write(output)
        case .ics:
            throw CommandError.unsupportedOutputFormat(format: "iCal", command: "suggest")
        }
    }

    func renderStations(_ output: StationsOutput, localization: Localization) throws -> String {
        let title = localization.text(.stations)
        switch self {
        case .text:
            guard !output.stations.isEmpty else {
                return "🚏 \(localization.text(.noStations))"
            }

            return (["🚏 \(title) (\(localization.timetableName(output.timetable))):"] + output.stations.enumerated().map { index, station in
                let detail = suggestionDetails(station).joined(separator: ", ")
                return "\(index + 1). \(station.text)\(detail.isEmpty ? "" : " - \(detail)")"
            }).joined(separator: "\n")
        case .markdown:
            guard !output.stations.isEmpty else {
                return "## 🚏 \(title)\n\n\(localization.text(.noStations))"
            }

            let rows = output.stations.enumerated().map { index, station in
                "| \(index + 1) | \(Markdown.escape(station.text)) | \(Markdown.escape(suggestionDetails(station).joined(separator: ", "))) |"
            }.joined(separator: "\n")

            return """
            ## 🚏 \(title)

            \(localization.text(.timetable)): **\(Markdown.escape(localization.timetableName(output.timetable)))**

            | # | \(localization.text(.station)) | \(localization.text(.details)) |
            | ---: | --- | --- |
            \(rows)
            """
        case .json:
            return try JSON.write(output)
        case .ics:
            throw CommandError.unsupportedOutputFormat(format: "iCal", command: "stations")
        }
    }

    func renderConnections(_ output: ConnectionsOutput, localization: Localization) throws -> String {
        let title = localization.text(.connections)
        switch self {
        case .text:
            guard !output.connections.isEmpty else {
                return "🔎 \(localization.text(.idosNoConnections))"
            }

            let rows = output.items.enumerated().map { index, item in
                item.summaryLine(number: index + 1, includeDetails: output.verbose, localization: localization)
            }

            return """
            🧭 \(title) \(routeDescription(output.request, localization: localization)) (\(localization.timetableName(output.request.timetable))):
            \(rows.joined(separator: "\n"))
            """
        case .markdown:
            guard !output.connections.isEmpty else {
                return """
                ## 🧭 \(title)

                **\(localization.text(.from)):** \(Markdown.escape(output.request.from))
                **\(localization.text(.to)):** \(Markdown.escape(output.request.to))
                \(markdownViaLine(output.request, localization: localization))
                **\(localization.text(.timetable)):** \(Markdown.escape(localization.timetableName(output.request.timetable)))

                \(localization.text(.noConnections))
                """
            }

            let sections = output.items.enumerated().map { index, item in
                let connection = item.connection
                let legs = connection.legs.map { leg in
                    if output.verbose {
                        let serviceID = leg.id.map { "`\(Markdown.escape($0))`" } ?? ""
                        return "| \(Markdown.lineName(leg)) | \(serviceID) | \(Markdown.escape(leg.fromStation)) | \(Markdown.escape(leg.fromTariffZone ?? "")) | \(Markdown.escape(leg.fromPlatform ?? "")) | \(Markdown.bold(leg.departureTime)) | \(Markdown.escape(leg.toStation)) | \(Markdown.escape(leg.toTariffZone ?? "")) | \(Markdown.escape(leg.toPlatform ?? "")) | \(Markdown.bold(leg.arrivalTime)) | \(Markdown.escape(leg.carrier ?? "")) | \(Markdown.escape(leg.delay ?? "")) |"
                    }

                    return "| \(Markdown.lineName(leg)) | \(Markdown.escape(leg.fromStation)) | \(Markdown.bold(leg.departureTime)) | \(Markdown.escape(leg.toStation)) | \(Markdown.bold(leg.arrivalTime)) |"
                }.joined(separator: "\n")
                let tableHeader = output.verbose ? """
                | \(localization.text(.line)) | \(localization.text(.serviceIdentifier)) | \(localization.text(.from)) | \(localization.text(.fromTariffZone)) | \(localization.text(.fromPlatform)) | \(localization.text(.departure)) | \(localization.text(.to)) | \(localization.text(.toTariffZone)) | \(localization.text(.toPlatform)) | \(localization.text(.arrival)) | \(localization.text(.carrier)) | \(localization.text(.delay)) |
                | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
                """ : """
                | \(localization.text(.line)) | \(localization.text(.from)) | \(localization.text(.departure)) | \(localization.text(.to)) | \(localization.text(.arrival)) |
                | --- | --- | --- | --- | --- |
                """
                let metadata = [
                    "\(localization.text(.duration)): **\(Markdown.escape(connection.duration))**",
                    output.verbose
                        ? "**\(localization.text(.identifier)):** `\(Markdown.escape(connection.id))`"
                        : nil,
                ].compactMap(\.self).joined(separator: "\n")

                return """
                ### \(index + 1). \(item.markdownLabel(localization: localization))\(Markdown.bold(connection.departureTime)) \(Markdown.escape(connection.departureStation)) → \(Markdown.bold(connection.arrivalTime)) \(Markdown.escape(connection.arrivalStation))

                \(metadata)

                \(tableHeader)
                \(legs)
                """
            }.joined(separator: "\n\n")

            return """
            ## 🧭 \(title)

            **\(localization.text(.from)):** \(Markdown.escape(output.request.from))
            **\(localization.text(.to)):** \(Markdown.escape(output.request.to))
            \(markdownViaLine(output.request, localization: localization))
            **\(localization.text(.timetable)):** \(Markdown.escape(localization.timetableName(output.request.timetable)))

            \(sections)
            """
        case .json:
            return try JSON.write(output)
        case .ics:
            throw CommandError.unsupportedOutputFormat(format: "iCal", command: "connections renderer")
        }
    }

    func renderServiceDetail(_ output: ServiceDetailOutput, localization: Localization) throws -> String {
        let service = output.service
        switch self {
        case .text:
            let stops = service.stops.enumerated().map { index, stop in
                var details: [String] = []
                if let arrivalTime = stop.arrivalTime {
                    details.append("\(localization.text(.arrival)) \(Terminal.bold(arrivalTime))")
                }
                if let departureTime = stop.departureTime {
                    details.append("\(localization.text(.departure)) \(Terminal.bold(departureTime))")
                }
                if let tariffZone = stop.tariffZone {
                    details.append(localization.text(.tariffZoneInline, tariffZone))
                }
                if let platform = stop.platform {
                    details.append(localization.text(.platformInline, platform))
                }
                if let track = stop.track {
                    details.append(localization.text(.trackInline, track))
                }
                if let platformTrack = stop.platformTrack {
                    details.append(localization.text(.platformTrackInline, platformTrack))
                }
                if let distance = stop.distance {
                    details.append(distance)
                }

                let notes = stop.notes.map { "\n      \(ServiceStopNote.render($0))" }.joined()
                let suffix = details.isEmpty ? "" : " — \(details.joined(separator: " · "))"
                return "\(index + 1). 📍 \(stop.name)\(suffix)\(notes)"
            }.joined(separator: "\n")
            let date = service.date.map { "\n   \(localization.text(.date)): \($0)" } ?? ""
            let information = service.information.isEmpty ? "" : """


            ℹ️ \(localization.text(.information)):
            \(service.information.map { "   • \($0)" }.joined(separator: "\n"))
            """

            return """
            \(service.displayName) · \(localization.text(.service)) (\(localization.timetableName(service.timetable)))
               \(localization.text(.serviceIdentifier)): \(service.id)\(date)
            🛤️ \(localization.text(.route)):
            \(stops)\(information)
            """
        case .markdown:
            let rows = service.stops.enumerated().map { index, stop in
                let notes = stop.notes
                    .map { Markdown.escape(ServiceStopNote.render($0)) }
                    .joined(separator: "<br>")
                return "| \(index + 1) | \(Markdown.escape(stop.name)) | \(Markdown.bold(stop.arrivalTime ?? "")) | \(Markdown.bold(stop.departureTime ?? "")) | \(Markdown.escape(stop.tariffZone ?? "")) | \(Markdown.escape(stop.platform ?? "")) | \(Markdown.escape(stop.track ?? "")) | \(Markdown.escape(stop.platformTrack ?? "")) | \(Markdown.escape(stop.distance ?? "")) | \(notes) |"
            }.joined(separator: "\n")
            let date = service.date.map { "**\(localization.text(.date)):** \(Markdown.escape($0))\n" } ?? ""
            let information = service.information.isEmpty ? "" : """


            ### ℹ️ \(localization.text(.information))

            \(service.information.map { "- \(Markdown.escape($0))" }.joined(separator: "\n"))
            """

            return """
            ## \(Markdown.serviceName(service)) · \(localization.text(.service))

            **\(localization.text(.serviceIdentifier)):** `\(Markdown.escape(service.id))`
            \(date)**\(localization.text(.timetable)):** \(Markdown.escape(localization.timetableName(service.timetable)))

            ### 🛤️ \(localization.text(.route))

            | # | \(localization.text(.station)) | \(localization.text(.arrival)) | \(localization.text(.departure)) | \(localization.text(.tariffZone)) | \(localization.text(.platform)) | \(localization.text(.track)) | \(localization.text(.platformTrack)) | \(localization.text(.distance)) | \(localization.text(.notes)) |
            | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |
            \(rows)\(information)
            """
        case .json:
            return try JSON.write(output)
        case .ics:
            throw CommandError.unsupportedOutputFormat(format: "iCal", command: "service")
        }
    }

    func renderCalendarImport(_ output: CalendarImportOutput, localization: Localization) throws -> String {
        switch self {
        case .text, .ics:
            let message = localization.text(
                .calendarOpened,
                routeDescription(output.request, localization: localization),
                output.path
            )
            return "📅 \(message)"
        case .markdown:
            return """
            ## 📅 \(localization.text(.calendarImport))

            **\(localization.text(.connection)):** \(Markdown.bold(output.connection.departureTime)) \(Markdown.escape(output.connection.departureStation)) → \(Markdown.bold(output.connection.arrivalTime)) \(Markdown.escape(output.connection.arrivalStation))
            **\(localization.text(.file)):** `\(Markdown.escape(output.path))`
            """
        case .json:
            return try JSON.write(output)
        }
    }

    func renderDepartures(_ output: DeparturesOutput, localization: Localization) throws -> String {
        let title = localization.text(output.request.isArrival ? .arrivals : .departures)
        let stationName = output.departures.first?.stationName ?? output.request.station

        switch self {
        case .text:
            guard !output.departures.isEmpty else {
                return "🔎 \(localization.text(output.request.isArrival ? .idosNoArrivals : .idosNoDepartures))"
            }

            let rows = output.departures.enumerated().map { index, departure in
                departureSummaryLine(
                    departure,
                    number: index + 1,
                    includeDetails: output.verbose,
                    localization: localization
                )
            }

            return """
            🚏 \(title) \(stationName) (\(localization.timetableName(output.request.timetable))):
            \(rows.joined(separator: "\n"))
            """
        case .markdown:
            guard !output.departures.isEmpty else {
                return """
                ## 🚏 \(title)

                **\(localization.text(.station)):** \(Markdown.escape(output.request.station))
                **\(localization.text(.timetable)):** \(Markdown.escape(localization.timetableName(output.request.timetable)))

                \(localization.text(output.request.isArrival ? .noArrivals : .noDepartures))
                """
            }

            let rows = output.departures.enumerated().map { index, departure in
                if output.verbose {
                    return "| \(index + 1) | \(Markdown.bold(departure.time)) | \(Markdown.departureLineName(departure)) | \(Markdown.escape(departure.destination)) | \(Markdown.escape(departure.tariffZone ?? "")) | \(Markdown.escape(departure.platform ?? "")) | \(Markdown.escape(departure.via ?? "")) | \(Markdown.escape(departure.carrier ?? "")) | \(Markdown.escape(departure.delay ?? "")) | `\(Markdown.escape(departure.id))` |"
                }

                return "| \(index + 1) | \(Markdown.bold(departure.time)) | \(Markdown.departureLineName(departure)) | \(Markdown.escape(departure.destination)) | \(Markdown.escape(departure.via ?? "")) |"
            }.joined(separator: "\n")
            let tableHeader = output.verbose ? """
            | # | \(localization.text(.time)) | \(localization.text(.line)) | \(localization.text(.destination)) | \(localization.text(.tariffZone)) | \(localization.text(.platform)) | \(localization.text(.via)) | \(localization.text(.carrier)) | \(localization.text(.delay)) | \(localization.text(.identifier)) |
            | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |
            """ : """
            | # | \(localization.text(.time)) | \(localization.text(.line)) | \(localization.text(.destination)) | \(localization.text(.via)) |
            | ---: | --- | --- | --- | --- |
            """

            return """
            ## 🚏 \(title)

            **\(localization.text(.station)):** \(Markdown.escape(stationName))
            **\(localization.text(.timetable)):** \(Markdown.escape(localization.timetableName(output.request.timetable)))

            \(tableHeader)
            \(rows)
            """
        case .json:
            return try JSON.write(output)
        case .ics:
            throw CommandError.unsupportedOutputFormat(format: "iCal", command: "departures")
        }
    }

    /// Renders the complete route and every hourly departure marker returned by IDOS Station Timetables.
    func renderStationTimetable(
        _ output: StationTimetableOutput,
        localization: Localization
    ) throws -> String {
        let result = output.stationTimetable
        let lineName = [result.transportMode?.emoji, result.lineName]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        switch self {
        case .text:
            let routeRows = result.stops.enumerated().map { index, stop in
                var details: [String] = []
                if let minuteOffset = stop.minuteOffset {
                    details.append(localization.text(.minutesInline, String(minuteOffset)))
                }
                if let tariffZone = stop.tariffZone, !tariffZone.isEmpty {
                    details.append(localization.text(.tariffZoneInline, tariffZone))
                }
                if let platform = stop.platform, !platform.isEmpty {
                    details.append(localization.text(.stationTimetablePlatformInline, platform))
                }
                if stop.isSelected {
                    details.append(localization.text(.selected))
                }
                details.append(contentsOf: stop.notes)
                let suffix = details.isEmpty ? "" : " · \(details.joined(separator: " · "))"
                return "\(index + 1). \(stop.isSelected ? "📍" : "🚏") \(stop.name)\(suffix)"
            }.joined(separator: "\n")
            let schedules = result.schedules.map { schedule in
                let hours = schedule.hours.map { hour in
                    let departures = hour.departures.isEmpty ? "—" : hour.departures.joined(separator: " ")
                    return "   \(Terminal.bold(hour.hour)): \(departures)"
                }.joined(separator: "\n")
                return "🕒 \(schedule.label):\n\(hours)"
            }.joined(separator: "\n\n")
            let lockout = result.isLockout
                ? "\n🚧 \(localization.text(.lockoutTimetable))"
                : ""
            let notes = result.notes.isEmpty ? "" : """


            ℹ️ \(localization.text(.notes)):
            \(result.notes.map { "   • \($0)" }.joined(separator: "\n"))
            """

            return """
            🗓️ \(localization.text(.stationTimetable)) \(lineName) · \(result.fromStop) → \(result.toStop) (\(localization.timetableName(result.timetable))):\(lockout)
            🛤️ \(localization.text(.route)):
            \(routeRows)

            \(schedules)\(notes)
            """
        case .markdown:
            let routeRows = result.stops.enumerated().map { index, stop in
                let notes = stop.notes.map(Markdown.escape).joined(separator: "<br>")
                return "| \(index + 1) | \(Markdown.escape(stop.name)) | \(stop.minuteOffset.map(String.init) ?? "—") | \(Markdown.escape(stop.tariffZone ?? "")) | \(Markdown.escape(stop.platform ?? "")) | \(localization.text(stop.isSelected ? .yes : .no)) | \(notes) |"
            }.joined(separator: "\n")
            let schedules = result.schedules.map { schedule in
                let rows = schedule.hours.map { hour in
                    "| \(Markdown.bold(hour.hour)) | \(Markdown.escape(hour.departures.isEmpty ? "—" : hour.departures.joined(separator: " "))) |"
                }.joined(separator: "\n")
                return """
                ### 🕒 \(Markdown.escape(schedule.label))

                | \(localization.text(.hour)) | \(localization.text(.departures)) |
                | ---: | --- |
                \(rows)
                """
            }.joined(separator: "\n\n")
            let lockout = result.isLockout
                ? "\n\n> 🚧 **\(localization.text(.lockoutTimetable))**"
                : ""
            let notes = result.notes.isEmpty ? "" : """


            ### ℹ️ \(localization.text(.notes))

            \(result.notes.map { "- \(Markdown.escape($0))" }.joined(separator: "\n"))
            """

            return """
            ## 🗓️ \(localization.text(.stationTimetable))

            **\(localization.text(.line)):** \(Markdown.escape(lineName))
            **\(localization.text(.from)):** \(Markdown.escape(result.fromStop))
            **\(localization.text(.to)):** \(Markdown.escape(result.toStop))
            **\(localization.text(.timetable)):** \(Markdown.escape(localization.timetableName(result.timetable)))\(lockout)

            ### 🛤️ \(localization.text(.route))

            | # | \(localization.text(.station)) | \(localization.text(.minutes)) | \(localization.text(.tariffZone)) | \(localization.text(.stationTimetablePlatform)) | \(localization.text(.selected)) | \(localization.text(.notes)) |
            | ---: | --- | ---: | --- | --- | --- | --- |
            \(routeRows)

            \(schedules)\(notes)
            """
        case .json:
            return try JSON.write(output)
        case .ics:
            throw CommandError.unsupportedOutputFormat(format: "iCal", command: "station-timetables")
        }
    }

    func renderTimetables(_ output: TimetablesOutput, localization: Localization) throws -> String {
        let title = localization.text(.timetables)
        switch self {
        case .text:
            let rows = output.timetables.map { timetable in
                "  \(timetable.slug) - \(localization.timetableName(timetable))"
            }

            return """
            🗂 \(title):
            \(rows.joined(separator: "\n"))

            \(localization.text(.customTimetableHint))
            """
        case .markdown:
            let rows = output.timetables.map { timetable in
                "| \(Markdown.escape(timetable.slug)) | \(Markdown.escape(localization.timetableName(timetable))) |"
            }.joined(separator: "\n")

            return """
            ## 🗂 \(title)

            | \(localization.text(.slug)) | \(localization.text(.name)) |
            | --- | --- |
            \(rows)

            \(localization.text(.customTimetableHint).replacingOccurrences(of: "--timetable", with: "`--timetable`"))
            """
        case .json:
            return try JSON.write(output)
        case .ics:
            throw CommandError.unsupportedOutputFormat(format: "iCal", command: "timetables")
        }
    }

    func renderStopAliases(_ output: StopAliasesOutput, localization: Localization) throws -> String {
        let title = localization.text(.stopAliases)
        switch self {
        case .text:
            guard !output.aliases.isEmpty else {
                return "🌰 \(localization.text(.noStopAliases))\n\(localization.text(.database)): \(output.path)"
            }

            let rows = output.aliases.map { alias in
                "  \(alias.name) → \(alias.station) (\(localization.timetableName(alias.timetable)))"
            }

            return """
            🌰 \(title):
            \(rows.joined(separator: "\n"))

            \(localization.text(.database)): \(output.path)
            """
        case .markdown:
            guard !output.aliases.isEmpty else {
                return """
                ## 🌰 \(title)

                \(localization.text(.noStopAliases))

                \(localization.text(.database)): `\(Markdown.escape(output.path))`
                """
            }

            let rows = output.aliases.map { alias in
                "| \(Markdown.escape(alias.name)) | \(Markdown.escape(alias.station)) | \(Markdown.escape(localization.timetableName(alias.timetable))) | \(Markdown.escape(alias.timetable.slug)) |"
            }.joined(separator: "\n")

            return """
            ## 🌰 \(title)

            | \(localization.text(.alias)) | \(localization.text(.station)) | \(localization.text(.timetable)) | \(localization.text(.slug)) |
            | --- | --- | --- | --- |
            \(rows)

            \(localization.text(.database)): `\(Markdown.escape(output.path))`
            """
        case .json:
            return try JSON.write(output)
        case .ics:
            throw CommandError.unsupportedOutputFormat(format: "iCal", command: "aliases")
        }
    }

    func renderStopAliasMutation(_ output: StopAliasMutationOutput, localization: Localization) throws -> String {
        let action = localizedAliasAction(output.action, localization: localization)
        switch self {
        case .text:
            return "🌰 \(localization.text(.aliasMutation, action)): \(output.alias.name) → \(output.alias.station) (\(localization.timetableName(output.alias.timetable)))"
        case .markdown:
            return """
            ## 🌰 \(localization.text(.stopAliasMutation, action.capitalized))

            **\(localization.text(.alias)):** \(Markdown.escape(output.alias.name))
            **\(localization.text(.station)):** \(Markdown.escape(output.alias.station))
            **\(localization.text(.timetable)):** \(Markdown.escape(localization.timetableName(output.alias.timetable)))
            **\(localization.text(.database)):** `\(Markdown.escape(output.path))`
            """
        case .json:
            return try JSON.write(output)
        case .ics:
            throw CommandError.unsupportedOutputFormat(format: "iCal", command: "aliases")
        }
    }

    func renderStopAliasPath(_ output: StopAliasPathOutput, localization: Localization) throws -> String {
        switch self {
        case .text:
            return "🌰 \(localization.text(.aliasDatabaseText)): \(output.path)"
        case .markdown:
            return """
            ## 🌰 \(localization.text(.aliasDatabase))

            `\(Markdown.escape(output.path))`
            """
        case .json:
            return try JSON.write(output)
        case .ics:
            throw CommandError.unsupportedOutputFormat(format: "iCal", command: "aliases")
        }
    }

    private func routeDescription(_ request: IDOSConnectionRequest, localization: Localization) -> String {
        let via = request.via.isEmpty
            ? ""
            : " \(localization.text(.viaInline, request.via.joined(separator: ", ")))"
        return "\(request.from) → \(request.to)\(via)"
    }

    private func markdownViaLine(_ request: IDOSConnectionRequest, localization: Localization) -> String {
        guard !request.via.isEmpty else {
            return ""
        }

        return "**\(localization.text(.via)):** \(Markdown.escape(request.via.joined(separator: ", ")))"
    }

    private func localizedAliasAction(_ action: String, localization: Localization) -> String {
        switch action {
        case "added":
            return localization.text(.added)
        case "updated":
            return localization.text(.updated)
        case "removed":
            return localization.text(.removed)
        default:
            return action
        }
    }

    /// Builds one localized departure row while retaining names and status details supplied by IDOS.
    private func departureSummaryLine(
        _ departure: IDOSDeparture,
        number: Int,
        includeDetails: Bool,
        localization: Localization
    ) -> String {
        var result = "\(number). \(Terminal.bold(departure.time)) \(departure.displayLineName) → \(departure.destination)"

        if includeDetails {
            if let tariffZone = departure.tariffZone, !tariffZone.isEmpty {
                result += " · \(localization.text(.tariffZoneInline, tariffZone))"
            }
            if let platform = departure.platform, !platform.isEmpty {
                result += " · \(localization.text(.platformInline, platform))"
            }
        }

        var details: [String] = []
        if includeDetails {
            details.append("\(localization.text(.identifier)): \(departure.id)")
        }
        if let via = departure.via, !via.isEmpty {
            details.append(localization.text(.viaInline, via))
        }
        if includeDetails {
            details.append(contentsOf: [departure.carrier, departure.delay]
                .compactMap(\.self)
                .filter { !$0.isEmpty })
        }

        if !details.isEmpty {
            result += "\n   \(details.joined(separator: "\n   "))"
        }

        return result
    }
}

/// Adds a quick visual category to common IDOS stop notes without replacing their original text.
private enum ServiceStopNote {
    static func render(_ note: String) -> String {
        "\(emoji(for: note)) \(note)"
    }

    private static func emoji(for note: String) -> String {
        let normalized = note
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()

        if normalized.contains("wheelchair accessible") || normalized.contains("bezbarier") {
            return "♿"
        }
        if normalized.contains("rail station") ||
            normalized.contains("railway station") ||
            normalized.contains("zeleznicni stanice") ||
            normalized.contains("zeleznicni dopravu")
        {
            return "🚉"
        }
        if normalized.contains("undeground") || normalized.contains("underground") || normalized.contains("metro") {
            return "🚇"
        }
        if normalized.contains("traffic restriction") ||
            normalized.contains("vyluk") ||
            normalized.contains("omezeni provozu")
        {
            return "🚧"
        }
        if normalized.contains("stops on signal") || normalized.contains("request stop") || normalized.contains("na znameni") {
            return "🔔"
        }

        return "ℹ️"
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

    private func labels(localization: Localization) -> [String] {
        [
            isDirect ? "➡️  \(localization.text(.direct))" : nil,
            isShortest ? "⚡ \(localization.text(.shortest))" : nil,
        ].compactMap(\.self)
    }

    func markdownLabel(localization: Localization) -> String {
        let labels = labels(localization: localization)
        return labels.isEmpty ? "" : "\(labels.joined(separator: " · ")) — "
    }

    func summaryLine(number: Int, includeDetails: Bool, localization: Localization) -> String {
        let labels = labels(localization: localization)
        let summary = localizedSummaryLine(
            number: number,
            includeDetails: includeDetails,
            localization: localization
        )
        guard !labels.isEmpty else {
            return summary
        }

        let numberPrefix = "\(number). "
        return "\(numberPrefix)\(labels.joined(separator: " · ")) — \(summary.dropFirst(numberPrefix.count))"
    }

    /// Recreates the library summary with localized labels while retaining IDOS data and terminal styling.
    private func localizedSummaryLine(
        number: Int,
        includeDetails: Bool,
        localization: Localization
    ) -> String {
        var result = "\(number). \(Terminal.bold(connection.departureTime)) \(connection.departureStation) → \(Terminal.bold(connection.arrivalTime)) \(connection.arrivalStation)"

        if !connection.duration.isEmpty {
            result += " (\(connection.duration))"
        }

        if includeDetails {
            result += "\n   \(localization.text(.identifier)): \(connection.id)"
        }

        if !connection.legs.isEmpty {
            let legSummary = connection.legs.map { leg in
                let line = [
                    leg.displayName,
                    stationDisplay(
                        name: leg.fromStation,
                        tariffZone: includeDetails ? leg.fromTariffZone : nil,
                        platform: includeDetails ? leg.fromPlatform : nil,
                        localization: localization
                    ),
                    Terminal.bold(leg.departureTime),
                    "→",
                    Terminal.bold(leg.arrivalTime),
                    stationDisplay(
                        name: leg.toStation,
                        tariffZone: includeDetails ? leg.toTariffZone : nil,
                        platform: includeDetails ? leg.toPlatform : nil,
                        localization: localization
                    ),
                ]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let details = includeDetails ? [
                    leg.id.map { "\(localization.text(.serviceIdentifier)): \($0)" },
                    leg.carrier,
                    leg.delay,
                ]
                    .compactMap(\.self)
                    .filter { !$0.isEmpty }
                    .map { "      \($0)" }
                    .joined(separator: "\n") : ""

                return details.isEmpty ? line : "\(line)\n\(details)"
            }.map { "   \($0)" }
                .joined(separator: "\n")
            result += "\n\(legSummary)"
        }

        return result
    }

    private func stationDisplay(
        name: String,
        tariffZone: String?,
        platform: String?,
        localization: Localization
    ) -> String {
        var parts = [name]
        if let tariffZone, !tariffZone.isEmpty {
            parts.append(localization.text(.tariffZoneInline, tariffZone))
        }
        if let platform, !platform.isEmpty {
            parts.append(localization.text(.platformInline, platform))
        }
        return parts.joined(separator: " · ")
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

/// Keeps the user's query beside the complete Station Timetable in encoded CLI output.
private struct StationTimetableOutput: Codable {
    var request: IDOSStationTimetableRequest
    var stationTimetable: IDOSStationTimetable
}

private struct ServiceDetailOutput: Codable {
    var service: IDOSServiceDetail
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

private enum AmbiguousPlaceKind {
    case station
    case place
}

private struct PlaceAmbiguity {
    var input: String
    var timetable: IDOSTimetable
    var kind: AmbiguousPlaceKind
    var candidates: [IDOSSuggestion]

    func message(localization: Localization) -> String {
        let header = localization.text(
            kind == .station ? .ambiguousStation : .ambiguousPlace,
            input,
            localization.timetableName(timetable)
        )
        let rows = candidates.enumerated().map { index, suggestion in
            let detail = suggestionDetails(suggestion).joined(separator: ", ")
            return "\(index + 1). \(suggestion.text)\(detail.isEmpty ? "" : " - \(detail)")"
        }

        return ([header, localization.text(.chooseOne)] + rows).joined(separator: "\n")
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

/// Applies terminal emphasis required by Kaštan's text output without changing its textual content.
private enum Terminal {
    private static let boldCode = "\u{001B}[1m"
    private static let resetCode = "\u{001B}[0m"

    static func bold(_ text: String) -> String {
        guard !text.isEmpty else {
            return ""
        }

        return "\(boldCode)\(text)\(resetCode)"
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

    static func serviceName(_ service: IDOSServiceDetail) -> String {
        let prefix = service.transportMode.map { "\($0.emoji) " } ?? ""
        let name = htmlEscape(service.name)
        guard let color = service.color, !color.isEmpty else {
            return "\(prefix)\(escape(service.name))"
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
    private static let shortFlags: Set<Character> = ["h", "a", "p", "x", "c", "v", "w"]
    private static let shortValueOptions: Set<Character> = ["f", "t", "s", "T", "V", "L", "d", "m", "X", "M", "o", "l"]

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
