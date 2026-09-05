import Foundation
@testable import Kastan
import Testing
@testable import KastanCLI

@Test func defaultOutputNamesApplication() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: [])

    #expect(output.contains("🌰 Kaštan"))
    #expect(output.contains("Search IDOS connections, departures, station timetables, stations, service routes"))
}

@Test func helpOutputShowsUsage() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["--help"])

    #expect(output.contains("🌰 Usage:"))
    #expect(output.contains("connections"))
    #expect(output.contains("departures"))
    #expect(output.contains("station-timetables"))
    #expect(output.contains("timetables"))
    #expect(output.contains("aliases"))
    #expect(output.contains("stations"))
    #expect(output.contains("--timetable"))
    #expect(output.contains("--station"))
    #expect(output.contains("--arrival"))
    #expect(output.contains("--departure"))
    #expect(output.contains("--whole-week"))
    #expect(output.contains("--line"))
    #expect(output.contains("--municipality"))
    #expect(output.contains("--via"))
    #expect(output.contains("--direct"))
    #expect(output.contains("--transport-mode"))
    #expect(output.contains("--add-to-calendar"))
    #expect(output.contains("--verbose"))
    #expect(output.contains("--max-transfers"))
    #expect(output.contains("--min-transfer-time"))
    #expect(output.contains("--max-transfer-time"))
    #expect(output.contains("--max-walking-time"))
    #expect(output.contains("--max-city-walking-time"))
    #expect(output.contains("--walk-to-nearby-stops"))
    #expect(output.contains("--same-name-walking-transfers-only"))
    #expect(output.contains("--wheelchair-accessible-connections-only"))
    #expect(output.contains("--low-floor-connections-only"))
    #expect(output.contains("--prefer-trains-over-buses"))
    #expect(output.contains("--train-connections-for-wheelchair-passengers"))
    #expect(output.contains("--train-connections-for-passengers-with-children"))
    #expect(output.contains("--connections-for-passengers-with-bicycles"))
    #expect(output.contains("--prefer-busy-routes"))
    #expect(output.contains("--bed-or-couchette-preference"))
    #expect(output.contains("--format"))
    #expect(output.contains("-T, --timetable"))
    #expect(output.contains("-o, --format"))
    #expect(output.contains("-v, --verbose"))
    #expect(output.contains("Show result and service IDs"))
    #expect(output.contains("kastan service <service-id> [-T alias] [-o text|markdown|html|json]"))
    #expect(output.contains("Output format: text, markdown, html, json"))
    #expect(output.contains("Direct connections only"))
    #expect(!output.contains("--jr"))
    #expect(output.contains("--version"))
    #expect(output.contains("--source"))
    #expect(output.contains("available: idos; default: idos"))
    #expect(output.contains("Timetable identifier supplied by the selected data source"))
    #expect(output.contains("Default timetable for IDOS is All timetables (vlakyautobusymhdvse)."))
    #expect(!output.contains("IDOS URL slug"))
}

@Test func cliMapsEveryLibraryConnectionOptionToDistinctEnglishNames() {
    let names = TransitConnectionOption.allCases.flatMap(\.connectionCommandNames)

    #expect(TransitConnectionOption.allCases.allSatisfy { !$0.connectionCommandNames.isEmpty })
    #expect(Set(names).count == names.count)
    #expect(
        TransitConnectionOption.allCases.filter(\.connectionCommandTakesValue)
            == Array(TransitConnectionOption.allCases.dropFirst())
    )
    #expect(
        Set(TransitConnectionTransportMode.allCases.map(\.connectionCommandValue)).count
            == TransitConnectionTransportMode.allCases.count
    )
}

@Test func sourceOptionRoutesCollidingTimetablesAcrossGlobalArgumentPositions() async throws {
    let alternateID: TransitDataSourceID = "alternate"
    let registry = try TransitDataSourceRegistry(
        dataSources: [
            CLIRoutingDataSource(id: .idos, timetableName: "IDOS shared timetable"),
            CLIRoutingDataSource(id: alternateID, timetableName: "Alternate shared timetable"),
        ],
        defaultDataSourceID: .idos
    )
    let runner = CommandRunner(
        dataSourceRegistry: registry,
        preferredLanguageIdentifiers: ["en"],
        environment: [:]
    )

    let requiredSource = await runner.output(for: ["timetables"])
    let requiredSourceJSON = await runner.output(
        for: ["timetables", "--format", "json", "--language", "cs"]
    )
    let idosOutput = await runner.output(
        for: ["--source", "idos", "timetables", "--format", "json"]
    )
    let sourceBeforeCommand = await runner.output(
        for: ["--source", "alternate", "timetables", "--format", "json"]
    )
    let sourceAfterCommand = await runner.output(
        for: ["timetables", "--source", "alternate", "--format", "json"]
    )
    let sourceWithEquals = await runner.output(
        for: ["timetables", "--format", "json", "--source=alternate"]
    )
    let alternateHelp = await runner.output(for: ["--source", "alternate", "--help"])
    let alternateCzechHelp = await runner.output(
        for: ["--source=alternate", "--help", "--language", "cs"]
    )
    let alternateUnknownCommand = await runner.output(
        for: ["--source=alternate", "unknown", "extra", "arguments"]
    )
    let genericHelp = await runner.output(for: ["--help"])
    let genericCzechHelp = await runner.output(for: ["--help", "--language", "cs"])
    let versionWithoutSource = await runner.output(for: ["--version"])

    #expect(
        requiredSource
            == "❌ Error: More than one data source is available. Select one with --source. Available sources: alternate, idos."
    )
    #expect(
        try jsonDictionary(requiredSourceJSON)["error"] as? String
            == "Je dostupný více než jeden zdroj dat. Vyberte jeden volbou --source. Dostupné zdroje: alternate, idos."
    )
    #expect(try timetableName(in: idosOutput) == "IDOS shared timetable")
    #expect(try timetableName(in: sourceBeforeCommand) == "Alternate shared timetable")
    #expect(try timetableName(in: sourceAfterCommand) == "Alternate shared timetable")
    #expect(try timetableName(in: sourceWithEquals) == "Alternate shared timetable")
    #expect(alternateHelp.contains(
        "Default timetable for Alternate shared timetable is Alternate shared timetable (shared)."
    ))
    #expect(alternateHelp.contains("Required data source ID (available: alternate, idos)"))
    #expect(alternateCzechHelp.contains(
        "Výchozí jízdní řád zdroje Alternate shared timetable je Alternate shared timetable (shared)."
    ))
    #expect(alternateUnknownCommand.contains(
        "Default timetable for Alternate shared timetable is Alternate shared timetable (shared)."
    ))
    #expect(genericHelp.contains("Required data source ID (available: alternate, idos)"))
    #expect(!genericHelp.contains("default: idos"))
    #expect(!genericHelp.contains("Default timetable for"))
    #expect(genericCzechHelp.contains("Povinné ID zdroje dat (dostupné: alternate, idos)"))
    #expect(!genericCzechHelp.contains("výchozí: idos"))
    #expect(!genericCzechHelp.contains("Výchozí jízdní řád zdroje"))
    #expect(versionWithoutSource == "0.7.1")
}

@Test func sourceOptionReportsLocalizedUnknownAndMissingValues() async throws {
    let registry = try TransitDataSourceRegistry(
        dataSources: [
            CLIRoutingDataSource(id: .idos, timetableName: "IDOS shared timetable"),
            CLIRoutingDataSource(id: "alternate", timetableName: "Alternate shared timetable"),
        ],
        defaultDataSourceID: .idos
    )
    let runner = CommandRunner(
        dataSourceRegistry: registry,
        preferredLanguageIdentifiers: ["en"],
        environment: [:]
    )

    let unknown = await runner.output(for: ["--source=missing", "timetables"])
    let missing = await runner.output(for: ["timetables", "--source", "--language", "cs"])

    #expect(unknown == "❌ Error: Unknown data source: missing. Available sources: alternate, idos.")
    #expect(missing == "❌ Chyba: Chybí hodnota pro --source. Dostupné zdroje: alternate, idos.")
}

@Test func explicitTestSourceDoesNotChangeTheSoleRegularSourceDefault() async throws {
    let registry = try TransitDataSourceRegistry(
        dataSources: [
            CLIRoutingDataSource(id: .idos, timetableName: "IDOS shared timetable"),
        ],
        defaultDataSourceID: .idos,
        explicitDataSources: [
            CLIRoutingDataSource(id: "mock", timetableName: "Mock shared timetable"),
        ]
    )
    let runner = CommandRunner(
        dataSourceRegistry: registry,
        preferredLanguageIdentifiers: ["en"],
        environment: [:]
    )

    let implicitOutput = await runner.output(for: ["timetables", "--format", "json"])
    let mockOutput = await runner.output(
        for: ["timetables", "--format", "json", "--source", "mock"]
    )
    let help = await runner.output(for: ["--help"])
    let unknown = await runner.output(for: ["--source", "missing", "timetables"])

    #expect(try timetableName(in: implicitOutput) == "IDOS shared timetable")
    #expect(try timetableName(in: mockOutput) == "Mock shared timetable")
    #expect(help.contains("available: idos; default: idos"))
    #expect(!help.contains("mock"))
    #expect(unknown == "❌ Error: Unknown data source: missing. Available sources: idos.")
}

@Test func builtInMockSourceProvidesDeterministicCLIResultsOnlyWhenExplicitlySelected() async throws {
    let runner = CommandRunner(
        dataSourceRegistry: .builtIn,
        preferredLanguageIdentifiers: ["en"],
        environment: [:]
    )

    let output = await runner.output(
        for: ["connections", "Mockov", "Testov", "--source=mock", "--format", "json"]
    )
    let ordinaryHelp = await runner.output(for: ["--help"])
    let help = await runner.output(for: ["--source", "mock", "--help"])
    let json = try jsonDictionary(output)
    let connection = try #require((json["connections"] as? [[String: Any]])?.first)

    #expect(connection["id"] as? String == "mock:connection:1")
    #expect(connection["departureTime"] as? String == "08:00")
    #expect(connection["arrivalTime"] as? String == "08:42")
    #expect(ordinaryHelp.contains("available: idos; default: idos"))
    #expect(!ordinaryHelp.contains("mock"))
    #expect(help.contains("Default timetable for Kaštan Mock is Mock Network (mock)."))
}

@Test func connectionOptionsAreRejectedBeforeAnUnsupportedProviderRequest() async throws {
    let limitedID: TransitDataSourceID = "limited"
    let registry = try TransitDataSourceRegistry(
        dataSources: [
            CLIRoutingDataSource(id: .idos, timetableName: "IDOS shared timetable"),
            CLIRoutingDataSource(
                id: limitedID,
                timetableName: "Limited shared timetable",
                capabilities: [.timetables, .connections]
            ),
        ],
        defaultDataSourceID: .idos
    )
    let runner = CommandRunner(
        dataSourceRegistry: registry,
        preferredLanguageIdentifiers: ["en"],
        environment: [:]
    )
    let base = ["--source", "limited", "connections", "Praha", "Brno"]

    let withoutProviderSpecificOptions = await runner.output(for: base)
    let direct = await runner.output(for: base + ["-x"])
    let via = await runner.output(for: base + ["-V", "Pardubice"])
    let transportMode = await runner.output(
        for: base + ["--transport-mode", "only:regional-train"]
    )
    let maximumTransfers = await runner.output(for: base + ["-X", "1"])
    let minimumTransferTime = await runner.output(
        for: base + ["--min-transfer-time=5", "--language", "cs"]
    )

    #expect(!withoutProviderSpecificOptions.hasPrefix("❌"))
    #expect(direct == "❌ Error: Option -x is not supported by data source Limited shared timetable (limited).")
    #expect(via == "❌ Error: Option -V is not supported by data source Limited shared timetable (limited).")
    #expect(
        transportMode
            == "❌ Error: Option --transport-mode is not supported by data source Limited shared timetable (limited)."
    )
    #expect(maximumTransfers == "❌ Error: Option -X is not supported by data source Limited shared timetable (limited).")
    #expect(minimumTransferTime == "❌ Chyba: Zdroj dat Limited shared timetable (limited) nepodporuje volbu --min-transfer-time.")
}

@Test func systemLanguageSelectsFirstSupportedLocalization() async {
    let output = await CommandRunner(
        client: MockIDOSClient(),
        preferredLanguageIdentifiers: ["it-CZ", "cs-CZ"],
        environment: [:]
    ).output(for: ["--help"])
    let fallback = await CommandRunner(
        client: MockIDOSClient(),
        preferredLanguageIdentifiers: ["de-DE"],
        environment: ["LANG": "C.UTF-8"]
    ).output(for: ["--help"])

    #expect(output.contains("🌰 Použití:"))
    #expect(output.contains("⚙️ Možnosti:"))
    #expect(output.contains("--language, --lang"))
    #expect(fallback.contains("🌰 Usage:"))
}

@Test func posixLocaleSelectsCzechLocalization() async {
    let output = await CommandRunner(
        client: MockIDOSClient(),
        preferredLanguageIdentifiers: ["de-DE"],
        environment: ["LC_ALL": "cs_CZ.UTF-8"]
    ).output(for: [])

    #expect(output.contains("Vyhledávání spojení"))
    #expect(output.contains("Nápovědu zobrazíte"))
}

@Test func explicitLanguageOverridesSystemLanguage() async {
    let runner = CommandRunner(
        client: MockIDOSClient(),
        preferredLanguageIdentifiers: ["cs-CZ"],
        environment: [:]
    )
    let english = await runner.output(for: ["--lang=en", "--help"])
    let czech = await runner.output(for: ["--language", "cs", "--help"])

    #expect(english.contains("🌰 Usage:"))
    #expect(english.contains("Output language: en or cs"))
    #expect(czech.contains("🌰 Použití:"))
    #expect(czech.contains("Jazyk výstupu: en nebo cs"))
}

@Test func czechLanguageLocalizesConnectionText() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky",
            "--verbose", "--limit", "1", "--language", "cs",
        ]
    )

    #expect(output.contains("🧭 Spojení Praha → Brno (Vlaky)"))
    #expect(output.contains("➡️  Přímý · ⚡ Nejrychlejší"))
    #expect(output.contains("ID: 396829589"))
    #expect(output.contains("ID spoje: vlaky:0-74552-18.06.2026 12:04:00"))
    #expect(output.contains("tarifní zóna P · nástupiště 4"))
    #expect(output.contains("Aktuálně bez zpoždění"))
    #expect(!output.contains("Currently no delay"))
}

@Test func connectionTextExpandsCombinedRailwayPlatformAndTrack() async {
    let connection = IDOSConnection(
        id: "connection-platform-track",
        departureTime: "18:01",
        departureStation: "Frýdek-Místek",
        arrivalTime: "18:29",
        arrivalStation: "Ostrava-Stodolní",
        duration: "28 min",
        legs: [
            IDOSConnectionLeg(
                name: "S6",
                transportMode: .train,
                departureTime: "18:01",
                fromStation: "Frýdek-Místek",
                fromPlatform: "2/3",
                arrivalTime: "18:29",
                toStation: "Ostrava-Stodolní"
            ),
        ]
    )
    let output = await englishCommandRunner(
        client: MockIDOSClient(connectionResults: [connection])
    ).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky",
            "--verbose", "--limit", "1", "--language", "cs",
        ]
    )

    #expect(output.contains("Frýdek-Místek · nástupiště 2 kolej 3"))
    #expect(!output.contains("nástupiště 2/3"))
}

@Test func knownIDOSDelayStatesFollowTheSelectedOutputLanguage() {
    let czech = Localization(language: .czech)
    let english = Localization(language: .english)

    #expect(czech.delayStatus(" Currently no delay ") == "Aktuálně bez zpoždění")
    #expect(czech.delayStatus("Departure tends to be on time") == "Odjezd bývá včas")
    #expect(czech.delayStatus("Arrival tends to be on time") == "Příjezd bývá včas")
    #expect(czech.delayStatus("Departure tends to be delayed") == "Odjezd bývá zpožděn")
    #expect(czech.delayStatus("Arrival tends to be delayed") == "Příjezd bývá zpožděn")
    #expect(english.delayStatus("Aktuálně bez zpoždění") == "Currently no delay")
    #expect(english.delayStatus("Odjezd bývá včas") == "Departure tends to be on time")
    #expect(english.delayStatus("Příjezd bývá včas") == "Arrival tends to be on time")
    #expect(english.delayStatus("Odjezd bývá zpožděn") == "Departure tends to be delayed")
    #expect(english.delayStatus("Příjezd bývá zpožděn") == "Arrival tends to be delayed")
    #expect(english.delayStatus("Departure tends to be on time") == "Departure tends to be on time")
    #expect(english.delayStatus("Arrival tends to be on time") == "Arrival tends to be on time")
    #expect(english.delayStatus("Departure tends to be delayed") == "Departure tends to be delayed")
    #expect(english.delayStatus("Arrival tends to be delayed") == "Arrival tends to be delayed")
    #expect(czech.delayStatus("Delay 12 min") == "Delay 12 min")
    #expect(czech.delayStatus("  ") == nil)
    #expect(czech.platformTrack("2/3") == "nástupiště 2 kolej 3")
    #expect(english.platformTrack("2/3") == "platform 2 track 3")
    #expect(czech.platformAndTrack(platform: "2", track: "3") == "nástupiště 2 kolej 3")
    #expect(czech.connectionPlatform("2/3", transportMode: .bus) == "nástupiště 2/3")
    #expect(czech.platformTrack("2/3/4") == "nástupiště/kolej 2/3/4")
}

@Test func czechLanguageLocalizesMarkdownAndErrors() async {
    let runner = englishCommandRunner(client: MockIDOSClient())
    let markdown = await runner.output(
        for: [
            "departures", "--station", "Ostrava,Hrabůvka,Benzina", "--timetable", "odis",
            "--format", "markdown", "--verbose", "--limit", "1", "--lang", "cs",
        ]
    )
    let error = await runner.output(for: ["stations", "Praha", "--unknown", "--language", "cs"])

    #expect(markdown.contains("## 🚏 Odjezdy"))
    #expect(markdown.contains("| # | Čas | Linka | Cíl | Tarifní zóna | Nástupiště | Přes | Dopravce | Zpoždění | ID |"))
    #expect(markdown.contains("`odis:1-4286-18.06.2026 16:03:00`"))
    #expect(error.contains("❌ Chyba: Neznámá volba: --unknown."))
}

@Test func localizedOutputKeepsJSONSchemaAndValuesStable() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["timetables", "--format", "json", "--language", "cs"]
    )
    let json = try jsonDictionary(output)
    let timetables = try #require(json["timetables"] as? [[String: Any]])

    #expect(timetables.contains {
        $0["slug"] as? String == "vlaky" && $0["displayName"] as? String == "Trains"
    })
}

@Test func unsupportedAndMissingLanguagesReturnLocalizedErrors() async {
    let runner = CommandRunner(
        client: MockIDOSClient(),
        preferredLanguageIdentifiers: ["cs-CZ"],
        environment: [:]
    )
    let unsupported = await runner.output(for: ["--language", "de", "--format", "json"])
    let missing = await runner.output(for: ["--lang"])
    let unsupportedJSON = try? jsonDictionary(unsupported)

    #expect(unsupportedJSON?["error"] as? String == "Nepodporovaný jazyk: de. Použijte en nebo cs.")
    #expect(missing == "❌ Chyba: Chybí hodnota pro --lang. Použijte en nebo cs.")
}

@Test func everyLocalizationKeyExistsInBothLanguages() {
    for language in AppLanguage.allCases {
        let localization = Localization(language: language)
        for key in LocalizationKey.allCases {
            #expect(localization.text(key) != key.rawValue, "Missing \(key.rawValue) for \(language.rawValue)")
        }
    }
}

@Test func versionOutputShowsCurrentVersion() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["--version"])

    #expect(output == "0.7.1")
}

@Test func suggestCommandPrintsSuggestions() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["suggest", "Praha", "--timetable", "pid"])

    #expect(output.contains("🔎 Suggested places (Prague + PID)"))
    #expect(output.contains("Praha hl.n."))
    #expect(output.contains("station"))
}

@Test func suggestCommandPrintsJSON() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["suggest", "Praha", "--timetable", "pid", "--format", "json"]
    )
    let json = try jsonDictionary(output)

    #expect((json["query"] as? String) == "Praha")
    #expect((json["timetable"] as? [String: Any])?["displayName"] as? String == "Prague + PID")
    #expect((json["suggestions"] as? [[String: Any]])?.first?["text"] as? String == "Praha hl.n.")
}

@Test func humanReadableCommandsProduceStandaloneHTML() async {
    let runner = englishCommandRunner(
        client: MockIDOSClient(),
        aliasFile: temporaryAliasFile()
    )
    let invocations = [
        ["suggest", "Praha", "--format", "html"],
        ["stations", "Praha", "--format", "html"],
        ["connections", "Praha", "Brno", "--timetable", "vlaky", "--format", "html", "--limit", "1"],
        ["departures", "Ostrava,Hrabůvka,Benzina", "--timetable", "odis", "--format", "html", "--limit", "1"],
        [
            "station-timetables", "--line", "Bus 154", "--from", "Strašnická",
            "--to", "Sídliště Libuš", "--timetable", "pid", "--date", "17.7.2026",
            "--whole-week", "--format", "html",
        ],
        ["service", "vlaky:0-74552-18.06.2026 12:04:00", "--format", "html"],
        ["timetables", "--format", "html"],
        ["aliases", "list", "--format", "html"],
    ]

    for invocation in invocations {
        let output = await runner.output(for: invocation)
        #expect(output.hasPrefix("<!doctype html>"), "Expected HTML for \(invocation)")
        #expect(output.contains("<html lang=\"en\">"), "Expected English HTML for \(invocation)")
        #expect(output.contains("<meta charset=\"utf-8\">"), "Expected UTF-8 HTML for \(invocation)")
        #expect(!output.contains("\u{001B}"), "HTML must not contain terminal control codes for \(invocation)")
    }
}

@Test func htmlOutputEscapesContentReceivedFromIDOS() async {
    let suggestion = IDOSSuggestion(
        selectedText: "<script>alert(1)</script>",
        text: "<script>alert(1)</script>",
        description: "A & B",
        iconId: 1
    )
    let runner = englishCommandRunner(client: MockIDOSClient(
        suggestionResultsByPrefix: ["unsafe": [suggestion]]
    ))

    let output = await runner.output(for: ["suggest", "unsafe", "--format", "html"])

    #expect(output.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
    #expect(output.contains("A &amp; B"))
    #expect(!output.contains("<script>alert(1)</script>"))
}

@Test func htmlConnectionOutputRejectsUnsafeIDOSMarkupAndColors() async {
    let connection = IDOSConnection(
        id: "unsafe-connection",
        departureTime: "12:00",
        departureStation: "Praha <script>alert(1)</script>",
        arrivalTime: "14:30",
        arrivalStation: "Brno & okolí",
        duration: "2 h 30 min",
        legs: [
            IDOSConnectionLeg(
                name: "R <script>alert(2)</script>",
                color: "red; background: url(unsafe)",
                transportMode: .train,
                departureTime: "12:00",
                fromStation: "Praha <hl.n.>",
                arrivalTime: "14:30",
                toStation: "Brno & okolí"
            ),
        ]
    )
    let runner = englishCommandRunner(client: MockIDOSClient(connectionResults: [connection]))

    let output = await runner.output(
        for: ["connections", "Praha", "Brno", "--timetable", "vlaky", "--format", "html"]
    )

    #expect(output.contains("Praha &lt;script&gt;alert(1)&lt;/script&gt;"))
    #expect(output.contains("Brno &amp; okolí"))
    #expect(output.contains("R &lt;script&gt;alert(2)&lt;/script&gt;"))
    #expect(!output.contains("<script>"))
    #expect(!output.contains("background: url(unsafe)"))
}

@Test func suggestCommandAcceptsShortOptions() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["suggest", "Praha", "-T", "pid", "-o", "json", "-l", "1"]
    )
    let json = try jsonDictionary(output)

    #expect((json["query"] as? String) == "Praha")
    #expect((json["timetable"] as? [String: Any])?["displayName"] as? String == "Prague + PID")
}

@Test func suggestCommandRejectsUnknownOptions() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["suggest", "Praha", "--unknown"])

    #expect(output.contains("❌ Error: Unknown option: --unknown."))
}

@Test func stationsCommandPrintsStations() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["stations", "Praha", "--timetable", "pid"])

    #expect(output.contains("🚏 Stations (Prague + PID):"))
    #expect(output.contains("Praha hl.n."))
    #expect(output.contains("station"))
}

@Test func stationsCommandPrintsJSON() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["stations", "Praha", "-T", "pid", "-o", "json", "-l", "1"]
    )
    let json = try jsonDictionary(output)

    #expect((json["query"] as? String) == "Praha")
    #expect((json["timetable"] as? [String: Any])?["displayName"] as? String == "Prague + PID")
    #expect((json["stations"] as? [[String: Any]])?.first?["text"] as? String == "Praha hl.n.")
    #expect(json["suggestions"] == nil)
}

@Test func stationsCommandRejectsUnknownOptions() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["stations", "Praha", "--unknown"])

    #expect(output.contains("❌ Error: Unknown option: --unknown."))
}

@Test func connectionCommandPrintsConnections() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("1. ➡️  Direct · ⚡ Shortest — 🕒"))
    #expect(output.contains("\u{001B}[1m12:04\u{001B}[0m Praha hl.n. → \u{001B}[1m15:44\u{001B}[0m Brno hl.n."))
    #expect(output.contains("🚆"))
    #expect(output.contains("R9"))
    #expect(!output.contains("ID: 396829589"))
    #expect(!output.contains("Service ID:"))
    #expect(!output.contains("tariff zone P · platform 4"))
    #expect(!output.contains("Currently no delay"))
}

@Test func connectionCommandHighlightsDirectAndShortestResultsIndependently() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(connectionResults: [
            connectionResult(id: "1", duration: "3 h 40 min", legNames: ["R 1"]),
            connectionResult(id: "2", duration: "3 h 15 min", legNames: ["R 2", "R 3"]),
            connectionResult(id: "3", duration: "3 h 50 min", legNames: ["R 4", "R 5"]),
        ])
    ).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--limit", "3"]
    )
    let lines = output.split(separator: "\n")
    let first = lines.first { $0.hasPrefix("1. ") }
    let second = lines.first { $0.hasPrefix("2. ") }
    let third = lines.first { $0.hasPrefix("3. ") }

    #expect(first?.contains("➡️  Direct") == true)
    #expect(first?.contains("⚡ Shortest") == false)
    #expect(second?.contains("➡️  Direct") == false)
    #expect(second?.contains("⚡ Shortest") == true)
    #expect(third?.contains("➡️  Direct") == false)
    #expect(third?.contains("⚡ Shortest") == false)
    #expect(third?.contains("🕒") == true)
}

@Test func connectionCommandHighlightsAllResultsTiedForShortestDuration() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(connectionResults: [
            connectionResult(id: "1", duration: "2 h 5 min", legNames: ["R 1"]),
            connectionResult(id: "2", duration: "125 min", legNames: ["R 2", "R 3"]),
        ])
    ).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--limit", "2"]
    )
    let resultHeadings = output.split(separator: "\n").filter { $0.hasPrefix("1. ") || $0.hasPrefix("2. ") }

    #expect(resultHeadings.count == 2)
    #expect(resultHeadings.allSatisfy { $0.contains("⚡ Shortest") })
}

@Test func connectionCommandPassesLimitToIDOSRequest() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(
            expectedConnectionResultLimit: 12,
            validatesConnectionResultLimit: true
        )
    ).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--limit", "12"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
}

@Test func connectionCommandMarksUnknownTransportAsGenericRoute() async {
    let runner = englishCommandRunner(
        client: MockIDOSClient(connectionResults: [
            connectionResult(id: "1", duration: "4 h", legNames: ["Mystery service"], transportMode: nil),
        ])
    )
    let text = await runner.output(
        for: ["connections", "Praha", "Brno", "--timetable", "vlaky", "--limit", "1"]
    )
    let markdown = await runner.output(
        for: ["connections", "Praha", "Brno", "--timetable", "vlaky", "--format", "markdown", "--limit", "1"]
    )

    #expect(text.contains("   🛣️ Mystery service"))
    #expect(markdown.contains("| 🛣️ Mystery service |"))
}

@Test func connectionCommandPrintsVerboseConnections() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--limit", "1", "--verbose"]
    )

    #expect(output.contains("tariff zone P · platform 4"))
    #expect(output.contains("   🆔 ID: 396829589"))
    #expect(output.contains("      🆔 Service ID: vlaky:0-74552-18.06.2026 12:04:00"))
    #expect(output.contains("      🏢 České dráhy, a.s."))
    #expect(output.contains("      ⏱️ Currently no delay"))
}

@Test func connectionCommandRequestsViaPlaces() async {
    let output = await englishCommandRunner(client: MockIDOSClient(expectedVia: ["Pardubice", "Olomouc"])).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky",
            "--via", "Pardubice", "--via=Olomouc", "--limit", "1",
        ]
    )

    #expect(output.contains("🧭 Connections Praha → Brno via Pardubice, Olomouc (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandAcceptsShortOptions() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(
            expectedIsArrival: true,
            expectedOnlyDirect: true,
            expectedVia: ["Pardubice"],
            expectedMaxTransfers: 0,
            expectedMinimumTransferTime: 10
        )
    ).output(
        for: [
            "connections", "-f", "Praha", "-t", "Brno", "-T", "vlaky", "-d", "18.6.2026",
            "-m", "15:00", "-a", "-x", "-V", "Pardubice", "-X", "0", "-M", "10", "-v", "-l", "1",
        ]
    )

    #expect(output.contains("🧭 Connections Praha → Brno via Pardubice (Trains)"))
    #expect(output.contains("tariff zone P · platform 4"))
}

@Test func connectionCommandAcceptsCombinedShortFlags() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(expectedOnlyDirect: true)
    ).output(
        for: ["connections", "-vx", "-f", "Praha", "-t", "Brno", "-T", "vlaky", "-l", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("tariff zone P · platform 4"))
}

@Test func rootCommandAcceptsCombinedShortFlagsBeforeRoute() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(expectedOnlyDirect: true)
    ).output(
        for: ["-vx", "Praha", "Brno", "-T", "vlaky", "-l", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("tariff zone P · platform 4"))
}

@Test func rootCommandAcceptsCombinedShortFlagsWithValueOptionAtEnd() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(expectedOnlyDirect: true)
    ).output(
        for: ["-vxT", "vlaky", "Praha", "Brno", "-l", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("tariff zone P · platform 4"))
}

@Test func connectionCommandAcceptsHyphenRouteExpression() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "Praha-Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func rootCommandAcceptsHyphenRouteExpression() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["Praha-Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandAcceptsTwoPositionalPlaces() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "Praha", "Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func rootCommandAcceptsTwoPositionalPlaces() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["Praha", "Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandAcceptsAsciiArrowRouteExpression() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "Praha->Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(!output.contains("->"))
    #expect(output.contains("R9"))
}

@Test func rootCommandAcceptsAsciiArrowRouteExpression() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["Praha->Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandAcceptsUnicodeArrowRouteExpression() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "Praha→Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func rootCommandAcceptsUnicodeArrowRouteExpression() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["Praha→Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandPrintsMarkdown() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--format", "markdown", "--limit", "1"]
    )

    #expect(output.contains("## 🧭 Connections"))
    #expect(output.contains("### 1. ➡️  Direct · ⚡ Shortest — 🕒 **12:04** Praha hl.n. → **15:44** Brno hl.n."))
    #expect(output.contains("⏱️ Duration: **3 hod 40 min**"))
    #expect(output.contains("| Line | From | Departure | To | Arrival |"))
    #expect(output.contains("| 🚆 <span style=\"color: #008000\">R9 (R 981 Vysočina)</span> | Praha hl.n. | **12:04** | Brno hl.n. | **15:44** |"))
    #expect(output.contains(#"🚆 <span style="color: #008000">R9 (R 981 Vysočina)</span>"#))
    #expect(!output.contains("**ID:**"))
    #expect(!output.contains("From Tariff Zone"))
    #expect(!output.contains("Currently no delay"))
}

@Test func connectionCommandPrintsVerboseMarkdown() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky",
            "--format", "markdown", "--limit", "1", "--verbose",
        ]
    )

    #expect(output.contains("| Line | Service ID | From | From Tariff Zone | From Platform | Departure | To | To Tariff Zone | To Platform | Arrival | Carrier | Delay |"))
    #expect(output.contains("| 🚆 <span style=\"color: #008000\">R9 (R 981 Vysočina)</span> | `vlaky:0-74552-18.06.2026 12:04:00` | Praha hl.n. | P | 4 | **12:04** | Brno hl.n. | 100 |  | **15:44** | České dráhy, a.s. | Currently no delay |"))
    #expect(output.contains("🆔 **ID:** `396829589`"))
}

@Test func connectionCommandPrintsLocalizedSemanticHTML() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky",
            "--format", "html", "--limit", "1", "--verbose", "--language", "cs",
        ]
    )

    #expect(output.contains("<html lang=\"cs\">"))
    #expect(output.contains("<h1>🧭 Spojení</h1>"))
    #expect(output.contains("➡️  Přímý · ⚡ Nejrychlejší"))
    #expect(output.contains("<span style=\"color: #008000\">R9 (R 981 Vysočina)</span>"))
    #expect(output.contains("<th scope=\"col\">ID spoje</th>"))
    #expect(output.contains("<code>vlaky:0-74552-18.06.2026 12:04:00</code>"))
    #expect(output.contains("Aktuálně bez zpoždění"))
}

@Test func requestedHTMLErrorsStayMachineRecognizableAndEscaped() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "connections", "Praha", "Brno", "--max-transfers=<value>",
            "--format", "html",
        ]
    )

    #expect(output.hasPrefix("<!doctype html>"))
    #expect(output.contains("<h1>❌ Error</h1>"))
    #expect(output.contains("Invalid --max-transfers: &lt;value&gt;"))
    #expect(!output.contains("--max-transfers: <value>"))
}

@Test func connectionCommandPrintsMarkdownWithVia() async {
    let output = await englishCommandRunner(client: MockIDOSClient(expectedVia: ["Pardubice"])).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--via", "Pardubice",
            "--timetable", "vlaky", "--format", "markdown", "--limit", "1",
        ]
    )

    #expect(output.contains("**Via:** Pardubice"))
}

@Test func connectionCommandPrintsJSONWithTransferLimits() async throws {
    let output = await englishCommandRunner(
        client: MockIDOSClient(expectedIsArrival: true, expectedMaxTransfers: 0, expectedMinimumTransferTime: 10)
    ).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky",
            "--arrival", "--max-transfers", "0", "--min-transfer-time", "10", "--format", "json", "--limit", "1",
        ]
    )
    let json = try jsonDictionary(output)
    let request = json["request"] as? [String: Any]

    #expect(request?["isArrival"] as? Bool == true)
    #expect(request?["maxTransfers"] as? Int == 0)
    #expect(request?["minimumTransferTime"] as? Int == 10)
    let connection = (json["connections"] as? [[String: Any]])?.first
    #expect(connection?["id"] as? String == "396829589")
    let leg = (connection?["legs"] as? [[String: Any]])?.first
    #expect(leg?["id"] as? String == "vlaky:0-74552-18.06.2026 12:04:00")
    #expect(connection?["isDirect"] as? Bool == true)
    #expect(connection?["isShortest"] as? Bool == true)
}

@Test func connectionCommandPassesAndPrintsEveryAdditionalJourneyOption() async throws {
    let output = await englishCommandRunner(
        client: MockIDOSClient(
            expectedTransportModeFilters: [
                .init(operation: .only, mode: .regionalTrain),
                .init(operation: .exclude, mode: .cityTrolleybus),
            ],
            expectedMinimumTransferTime: -1,
            expectedMaximumTransferTime: 360,
            expectedMaximumWalkingTime: 45,
            expectedMaximumCityWalkingTime: 20,
            expectedWalkToNearbyStops: true,
            expectedSameNameWalkingTransfersOnly: false,
            expectedWheelchairAccessibleConnectionsOnly: true,
            expectedLowFloorConnectionsOnly: false,
            expectedPreferTrainsOverBuses: true,
            expectedTrainConnectionsForWheelchairPassengers: false,
            expectedTrainConnectionsForPassengersWithChildren: true,
            expectedConnectionsForPassengersWithBicycles: false,
            expectedPreferBusyRoutes: true,
            expectedBedOrCouchettePreference: .use
        )
    ).output(
        for: [
            "connections", "Praha", "Brno", "--timetable", "vlaky",
            "--min-transfer-time", "-1",
            "--transport-mode", "only:regional-train",
            "--transport-mode", "exclude:city-trolleybus",
            "--max-transfer-time", "360",
            "--max-walking-time", "45",
            "--max-city-walking-time", "20",
            "--walk-to-nearby-stops", "true",
            "--same-name-walking-transfers-only", "false",
            "--wheelchair-accessible-connections-only", "true",
            "--low-floor-connections-only", "false",
            "--prefer-trains-over-buses", "true",
            "--train-connections-for-wheelchair-passengers", "false",
            "--train-connections-for-passengers-with-children", "true",
            "--connections-for-passengers-with-bicycles", "false",
            "--prefer-busy-routes", "true",
            "--bed-or-couchette-preference", "use",
            "--format", "json", "--limit", "1",
        ]
    )
    let request = try #require(jsonDictionary(output)["request"] as? [String: Any])

    #expect(request["minimumTransferTime"] as? Int == -1)
    let transportModeFilters = try #require(request["transportModeFilters"] as? [[String: String]])
    #expect(transportModeFilters == [
        ["operation": "only", "mode": "regionalTrain"],
        ["operation": "exclude", "mode": "cityTrolleybus"],
    ])
    #expect(request["maximumTransferTime"] as? Int == 360)
    #expect(request["maximumWalkingTime"] as? Int == 45)
    #expect(request["maximumCityWalkingTime"] as? Int == 20)
    #expect(request["walkToNearbyStops"] as? Bool == true)
    #expect(request["sameNameWalkingTransfersOnly"] as? Bool == false)
    #expect(request["wheelchairAccessibleConnectionsOnly"] as? Bool == true)
    #expect(request["lowFloorConnectionsOnly"] as? Bool == false)
    #expect(request["preferTrainsOverBuses"] as? Bool == true)
    #expect(request["trainConnectionsForWheelchairPassengers"] as? Bool == false)
    #expect(request["trainConnectionsForPassengersWithChildren"] as? Bool == true)
    #expect(request["connectionsForPassengersWithBicycles"] as? Bool == false)
    #expect(request["preferBusyRoutes"] as? Bool == true)
    #expect(request["bedOrCouchettePreference"] as? String == "use")
}

@Test func connectionCommandPrintsIDOSCalendar() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--format", "ics"]
    )

    #expect(output.contains("BEGIN:VCALENDAR"))
    #expect(output.contains("SUMMARY:Connection Praha hl.n. >> Brno hl.n."))
    #expect(output.contains("END:VCALENDAR"))
}

@Test func connectionCommandPrintsIDOSCalendarInSelectedLanguage() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(expectedCalendarLanguage: .czech)
    ).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky",
            "--format", "ics", "--language", "cs",
        ]
    )

    #expect(output.contains("SUMMARY:Spojení Praha hl.n. >> Brno hl.n."))
}

@Test func connectionCommandAddsIDOSCalendar() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(),
        calendarImporter: MockCalendarImporter(path: "/tmp/kastan-test.ics")
    ).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--add-to-calendar"]
    )

    #expect(output.contains("📅 Opened calendar import for Praha → Brno"))
    #expect(output.contains("/tmp/kastan-test.ics"))
}

@Test func connectionCommandAddsIDOSCalendarAsJSON() async throws {
    let output = await englishCommandRunner(
        client: MockIDOSClient(),
        calendarImporter: MockCalendarImporter(path: "/tmp/kastan-test.ics")
    ).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky",
            "--add-to-calendar", "--format", "json",
        ]
    )
    let json = try jsonDictionary(output)

    #expect(json["path"] as? String == "/tmp/kastan-test.ics")
    #expect((json["connection"] as? [String: Any])?["id"] as? String == "396829589")
}

@Test func connectionCommandRejectsCalendarImportWithICSOutput() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky",
            "--add-to-calendar", "--format", "ics",
        ]
    )

    #expect(output.contains("Conflicting options: --add-to-calendar and --format ics"))
}

@Test func connectionCommandPrintsJSONWithVia() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient(expectedVia: ["Pardubice"])).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--via", "Pardubice",
            "--timetable", "vlaky", "--format", "json", "--limit", "1",
        ]
    )
    let json = try jsonDictionary(output)
    let request = json["request"] as? [String: Any]

    #expect(request?["via"] as? [String] == ["Pardubice"])
}

@Test func connectionCommandRequestsDirectConnections() async {
    let output = await englishCommandRunner(client: MockIDOSClient(expectedOnlyDirect: true)).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--direct", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandRequestsArrivalTime() async {
    let output = await englishCommandRunner(client: MockIDOSClient(expectedIsArrival: true)).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--time", "15:00", "--arrival", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandRequestsDepartureTime() async {
    let output = await englishCommandRunner(client: MockIDOSClient(expectedIsArrival: false)).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--time", "15:00", "--departure", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandRejectsConflictingTimeModes() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--time", "15:00", "--arrival", "--departure"]
    )

    #expect(output.contains("❌ Error: Conflicting options: --arrival and --departure. Use only one."))
}

@Test func connectionCommandRejectsUnknownOptions() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--unknown"]
    )

    #expect(output.contains("❌ Error: Unknown option: --unknown."))
}

@Test func connectionCommandRejectsUnknownOptionsAsJSON() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--format", "json", "--unknown"]
    )
    let json = try jsonDictionary(output)

    #expect(json["error"] as? String == "Unknown option: --unknown.")
}

@Test func connectionCommandPrintsNetworkErrors() async {
    let output = await englishCommandRunner(client: MockIDOSClient(failConnectionsWithNetworkError: true)).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky"]
    )

    #expect(output.contains("❌ Error: Network request failed. Check your internet connection."))
}

@Test func connectionCommandReportsAmbiguousPlaceNames() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(suggestionResultsByPrefix: ["sí pe": ambiguousPIDStationSuggestions()])
    ).output(
        for: ["connections", "Santoška", "sí pe", "--timetable", "pid"]
    )

    #expect(output.contains("❌ Error: Ambiguous place name: sí pe (Prague + PID)."))
    #expect(output.contains("1. Sídliště Petrovice - stop (Praha)"))
    #expect(output.contains("2. Sídliště Petřiny - stop (Praha)"))
}

@Test func connectionCommandLimitsMaximumTransfers() async {
    let output = await englishCommandRunner(client: MockIDOSClient(expectedMaxTransfers: 0)).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--max-transfers", "0", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandSetsMinimumTransferTime() async {
    let output = await englishCommandRunner(client: MockIDOSClient(expectedMinimumTransferTime: 10)).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--min-transfer-time", "10", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandRejectsNegativeMaximumTransfers() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--max-transfers", "-1"]
    )

    #expect(output.contains("❌ Error: Invalid --max-transfers: -1. Use a non-negative integer."))
}

@Test func connectionCommandRejectsNegativeShortMaximumTransfers() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "-f", "Praha", "-t", "Brno", "-T", "vlaky", "-X", "-1"]
    )

    #expect(output.contains("❌ Error: Invalid -X: -1. Use a non-negative integer."))
}

@Test func connectionCommandAcceptsStandardMinimumTransferTime() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(expectedMinimumTransferTime: -1)
    ).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--min-transfer-time", "-1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
}

@Test func connectionCommandRejectsMinimumTransferTimeBelowStandard() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "Praha", "Brno", "--timetable", "vlaky", "--min-transfer-time", "-2"]
    )

    #expect(output.contains("❌ Error: Invalid --min-transfer-time: -2. Use an integer of at least -1."))
}

@Test func connectionCommandRejectsInvalidBooleanJourneyOption() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "Praha", "Brno", "--prefer-busy-routes", "yes"]
    )

    #expect(output == "❌ Error: Invalid --prefer-busy-routes: yes. Use one of: true, false.")
}

@Test func connectionCommandRejectsInvalidTransportModeFilter() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "Praha", "Brno", "--transport-mode", "prefer:train"]
    )

    #expect(output.contains("❌ Error: Invalid --transport-mode: prefer:train."))
    #expect(output.contains("only:highest-quality-train"))
    #expect(output.contains("exclude:city-trolleybus"))
}

@Test func connectionCommandRejectsInvalidBedOrCouchettePreference() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "Praha", "Brno", "--bed-or-couchette-preference", "sometimes"]
    )

    #expect(
        output
            == "❌ Error: Invalid --bed-or-couchette-preference: sometimes. Use one of: no-limitation, use, do-not-use."
    )
}

@Test func connectionCommandRejectsBedOrCouchetteForIncompatibleTimetable() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(expectedConnectionTimetable: "autobusy")
    ).output(
        for: [
            "connections", "Praha", "Brno", "--timetable", "autobusy",
            "--bed-or-couchette-preference", "use",
        ]
    )

    #expect(
        output
            == "❌ Error: Option --bed-or-couchette-preference is not supported for timetable Buses (autobusy)."
    )
}

@Test func departuresCommandPrintsDepartures() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["departures", "--station", "Ostrava,Hrabůvka,Benzina", "--timetable", "odis", "--time", "16:00", "--limit", "1"]
    )

    #expect(output.contains("🚏 Departures Ostrava,Hrabůvka,Benzina (ODIS)"))
    #expect(output.contains("\u{001B}[1m16:03\u{001B}[0m"))
    #expect(output.contains("🚌"))
    #expect(output.contains("Bus 980"))
    #expect(output.contains("Rožnov p.Radh.,,aut.st."))
    #expect(output.contains("via Frýdek-Místek,Místek,Anenská"))
    #expect(!output.contains("ID: odis:1-4286-18.06.2026 16:03:00"))
    #expect(!output.contains("tariff zone 70 · platform 1"))
    #expect(!output.contains("Currently no delay"))
}

@Test func departuresCommandPrintsVerboseDepartures() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "departures", "--station", "Ostrava,Hrabůvka,Benzina", "--timetable", "odis",
            "--time", "16:00", "--limit", "1", "--verbose",
        ]
    )

    #expect(output.contains("tariff zone 70 · platform 1"))
    #expect(output.contains("ID: odis:1-4286-18.06.2026 16:03:00"))
    #expect(output.contains("Transdev Slezsko a.s."))
    #expect(output.contains("Currently no delay"))
}

@Test func stationTimetablesCommandPrintsCompleteMHDStationTimetable() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "station-timetables", "--line", "Bus 154", "--from", "Strašnická",
            "--to", "Sídliště Libuš", "--timetable", "pid", "--date", "17.7.2026", "--whole-week",
        ]
    )

    #expect(output.contains("🗓️ Station Timetable 🚌 Bus 154 · Strašnická → Sídliště Libuš (Prague + PID)"))
    #expect(output.contains("🚧 Lockout timetable"))
    #expect(output.contains("🛤️ Route:"))
    #expect(output.contains("1. 📍 Strašnická · +0 min · tariff zone 0 · platform 1 · Selected · request stop"))
    #expect(output.contains("2. 🚏 Na Hroudě · +1 min · tariff zone B · platform 2 · wheelchair accessible stop"))
    #expect(output.contains("🕒 17.7.2026 Friday:"))
    #expect(output.contains("\u{001B}[1m5\u{001B}[0m: 13 35A 55"))
    #expect(output.contains("❓ Explanations:"))
    #expect(output.contains("A: runs only to stop Háje"))
    #expect(output.contains("ℹ️ Notes:"))
    #expect(output.contains("valid from 1.7.2026"))
    let explanations = try #require(output.range(of: "❓ Explanations:"))
    let notes = try #require(output.range(of: "ℹ️ Notes:"))
    #expect(explanations.lowerBound < notes.lowerBound)
}

@Test func stationTimetablesCommandSelectsODISMunicipality() async throws {
    let odis = try IDOSTimetable.resolve("odis")
    let municipality = try #require(
        try IDOSStationTimetableMunicipality.resolve("frydek-mistek", timetable: odis)
    )
    let output = await englishCommandRunner(client: MockIDOSClient(
        expectedStationTimetable: "odis",
        expectedStationTimetableMunicipality: municipality
    )).output(
        for: [
            "station-timetables", "-L", "Bus 154", "-f", "Strašnická",
            "-t", "Sídliště Libuš", "-T", "odis", "-u", "Frýdek-Místek",
            "-d", "17.7.2026", "-w",
        ]
    )

    #expect(output.contains("(ODIS · Frýdek-Místek)"))
}

@Test func stationTimetablesCommandSelectsIREDOMunicipality() async throws {
    let iredo = try IDOSTimetable.resolve("iredo")
    let municipality = try #require(
        try IDOSStationTimetableMunicipality.resolve("Chrudim", timetable: iredo)
    )
    let output = await englishCommandRunner(client: MockIDOSClient(
        expectedStationTimetable: "iredo",
        expectedStationTimetableMunicipality: municipality,
        expectedStationTimetableLine: "Bus 1",
        expectedStationTimetableFrom: "Dopravní terminál",
        expectedStationTimetableTo: "Na Větrníku"
    )).output(
        for: [
            "station-timetables", "-L", "Bus 1", "-f", "Dopravní terminál",
            "-t", "Na Větrníku", "-T", "iredo", "-u", "Chrudim",
            "-d", "17.7.2026", "-w",
        ]
    )

    #expect(output.contains("(IREDO · Chrudim)"))
}

@Test func stationTimetablesCommandSelectsIDOLMunicipality() async throws {
    let idol = try IDOSTimetable.resolve("idol")
    let municipality = try #require(
        try IDOSStationTimetableMunicipality.resolve("Liberec", timetable: idol)
    )
    let output = await englishCommandRunner(client: MockIDOSClient(
        expectedStationTimetable: "idol",
        expectedStationTimetableMunicipality: municipality,
        expectedStationTimetableLine: "Tram 2",
        expectedStationTimetableFrom: "Fügnerova",
        expectedStationTimetableTo: "Dolní Hanychov"
    )).output(
        for: [
            "station-timetables", "-L", "Tram 2", "-f", "Fügnerova",
            "-t", "Dolní Hanychov", "-T", "idol", "-u", "Liberec",
            "-d", "17.7.2026", "-w",
        ]
    )

    #expect(output.contains("(IDOL · Liberec)"))
}

@Test func stationTimetablesCommandRejectsMunicipalityOutsideSelectedTimetable() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "station-timetables", "-L", "Bus 154", "-f", "Strašnická",
            "-t", "Sídliště Libuš", "-T", "pid", "-u", "Ostrava",
        ]
    )

    #expect(output.contains("Timetable Prague + PID does not offer a municipality choice."))
}

@Test func stationTimetablesCommandAcceptsShortOptionsAndPrintsMarkdown() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "station-timetables", "-wL", "Bus 154", "-f", "Strašnická", "-t", "Sídliště Libuš",
            "-T", "pid", "-d", "17.7.2026", "-o", "markdown",
        ]
    )

    #expect(output.contains("## 🗓️ Station Timetable"))
    #expect(output.contains("**Line:** 🚌 Bus 154"))
    #expect(output.contains("| # | Station | Minutes | Tariff Zone | Platform | Selected | Notes |"))
    #expect(output.contains("| 1 | Strašnická | 0 | 0 | 1 | Yes | request stop |"))
    #expect(output.contains("### 🕒 17.7.2026 Friday"))
    #expect(output.contains("| **5** | 13 35A 55 |"))
    #expect(output.contains("### ❓ Explanations"))
    #expect(output.contains("### ℹ️ Notes"))
}

@Test func stationTimetablesCommandPrintsStableJSON() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "station-timetable", "-L", "Bus 154", "-f", "Strašnická", "-t", "Sídliště Libuš",
            "-T", "pid", "-d", "17.7.2026", "-w", "-o", "json",
        ]
    )
    let json = try jsonDictionary(output)
    let request = try #require(json["request"] as? [String: Any])
    let result = try #require(json["stationTimetable"] as? [String: Any])
    let stops = try #require(result["stops"] as? [[String: Any]])

    #expect(request["line"] as? String == "Bus 154")
    #expect(request["wholeWeek"] as? Bool == true)
    #expect(result["lineName"] as? String == "Bus 154")
    #expect(stops.first?["isSelected"] as? Bool == true)
    #expect(stops.first?["platform"] as? String == "1")
    #expect((result["schedules"] as? [[String: Any]])?.count == 1)
    #expect(result["explanations"] as? [String] == ["A: runs only to stop Háje"])
    #expect(result["notes"] as? [String] == ["valid from 1.7.2026"])
}

@Test func stationTimetablesCommandLocalizesCzechOutputAndIDOSRequest() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(expectedStationTimetableLanguage: .czech)
    ).output(
        for: [
            "station-timetables", "-L", "Bus 154", "-f", "Strašnická", "-t", "Sídliště Libuš",
            "-T", "pid", "-d", "17.7.2026", "-w", "--language", "cs",
        ]
    )

    #expect(output.contains("🗓️ Zastávkový jízdní řád"))
    #expect(output.contains("🚧 Výlukový jízdní řád"))
    #expect(output.contains("🛤️ Trasa:"))
    #expect(output.contains("tarifní zóna 0 · stanoviště 1 · Vybraná"))
    #expect(output.contains("❓ Vysvětlivky:"))
    #expect(output.contains("ℹ️ Poznámky:"))
}

@Test func stationTimetablesCommandRequiresLineAndDirectionAndRejectsUnknownOptions() async {
    let runner = englishCommandRunner(client: MockIDOSClient())
    let missing = await runner.output(for: ["station-timetables", "--line", "Bus 154"])
    let unknown = await runner.output(
        for: [
            "station-timetables", "-L", "Bus 154", "-f", "Strašnická", "-t", "Sídliště Libuš",
            "--unknown",
        ]
    )

    #expect(missing.contains("Usage: kastan station-timetables"))
    #expect(unknown.contains("❌ Error: Unknown option: --unknown."))
}

@Test func serviceCommandPrintsCompleteRoute() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["service", "vlaky:0-74552-18.06.2026 12:04:00"]
    )

    #expect(output.contains("🚆 \u{001B}[38;2;0;128;0mRJ 1051 RegioJet\u{001B}[0m · Service (Trains)"))
    #expect(output.contains("   🆔 Service ID: vlaky:0-74552-18.06.2026 12:04:00"))
    #expect(output.contains("   📅 Date: 18.6.2026"))
    #expect(output.contains("🛤️ Route:"))
    #expect(output.contains("1. 📍 Praha-Zahradní Město — Departure \u{001B}[1m11:45\u{001B}[0m · track 3 · 0 km"))
    #expect(output.contains("🚧 Traffic restrictions"))
    #expect(output.contains("2. 📍 Praha hl.n. — Arrival \u{001B}[1m11:53\u{001B}[0m · Departure \u{001B}[1m12:04\u{001B}[0m"))
    #expect(output.contains("🚇 transfer to the undeground"))
    #expect(output.contains("♿ wheelchair accessible station"))
    #expect(output.contains("🚉 rail station"))
    #expect(output.contains("platform 3 track 1 · 262 km"))
    #expect(!output.contains("platform/track 3/1"))
    #expect(output.contains("ℹ️ Information:"))
    #expect(output.contains("   🚧 Planned traffic restriction"))
    #expect(output.contains("   🏢 České dráhy, a.s."))
    #expect(!output.contains("   • "))
}

@Test func serviceCommandPrintsMarkdown() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "service", "vlaky:0-74552-18.06.2026 12:04:00", "--format", "markdown",
        ]
    )

    #expect(output.contains("## 🚆 <span style=\"color: #008000\">RJ 1051 RegioJet</span> · Service"))
    #expect(output.contains("🆔 **Service ID:** `vlaky:0-74552-18.06.2026 12:04:00`"))
    #expect(output.contains("📅 **Date:** 18.6.2026"))
    #expect(output.contains("🗂️ **Timetable:** Trains"))
    #expect(output.contains("| # | Station | Arrival | Departure | Tariff Zone | Platform | Track | Platform/Track | Distance | Notes |"))
    #expect(output.contains("| 2 | Praha hl.n. | **11:53** | **12:04** | P |  |  |  | 7 km | 🚇 transfer to the undeground |"))
    #expect(output.contains("| 3 | Brno hl.n. | **15:44** |  |  |  |  | 3/1 | 262 km | ♿ wheelchair accessible station<br>🚉 rail station |"))
    #expect(output.contains("- 🚧 Planned traffic restriction"))
    #expect(output.contains("- 🏢 České dráhy, a.s."))
}

@Test func serviceCommandPrintsJSON() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["service", "vlaky:0-74552-18.06.2026 12:04:00", "-o", "json"]
    )
    let json = try jsonDictionary(output)
    let service = json["service"] as? [String: Any]
    let stops = service?["stops"] as? [[String: Any]]

    #expect((service?["timetable"] as? [String: Any])?["slug"] as? String == "vlaky")
    #expect(service?["id"] as? String == "vlaky:0-74552-18.06.2026 12:04:00")
    #expect(stops?.count == 3)
    #expect(stops?[2]["notes"] as? [String] == ["wheelchair accessible station", "rail station"])
}

@Test func serviceCommandLocalizesCzechOutput() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(expectedServiceLanguage: .czech)
    ).output(
        for: ["service", "vlaky:0-74552-18.06.2026 12:04:00", "--language", "cs"]
    )

    #expect(output.contains("· Spoj (Vlaky)"))
    #expect(output.contains("🆔 ID spoje: vlaky:0-74552-18.06.2026 12:04:00"))
    #expect(output.contains("📅 Datum: 18.6.2026"))
    #expect(output.contains("🛤️ Trasa:"))
    #expect(output.contains("Příjezd \u{001B}[1m11:53\u{001B}[0m · Odjezd \u{001B}[1m12:04\u{001B}[0m"))
    #expect(output.contains("🚧 Omezení provozu"))
    #expect(output.contains("🚇 přestup na Metro"))
    #expect(output.contains("♿ bezbariérově přístupná stanice"))
    #expect(output.contains("🚉 zastávka s možností přestupu na železniční dopravu"))
    #expect(output.contains("🚧 Plánované omezení provozu"))
    #expect(output.contains("🏢 České dráhy, a.s."))
}

@Test func serviceCommandPassesAnExplicitTimetableContext() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(expectedServiceTimetable: "odis")
    ).output(
        for: [
            "service", "vlaky:0-74552-18.06.2026 12:04:00", "--timetable", "odis",
        ]
    )

    #expect(output.contains("RJ 1051 RegioJet"))
}

@Test func serviceCommandRequiresIdentifier() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["service", "--timetable", "vlaky"])

    #expect(output.contains("Usage: kastan service <service-id>"))
}

@Test func serviceCommandRejectsInvalidIdentifierBeforeNetworkRequest() async {
    let client = IDOSClient(baseURL: URL(string: "http://127.0.0.1:9")!)
    let output = await englishCommandRunner(client: client).output(
        for: ["service", "not-an-id", "--timetable", "vlaky"]
    )

    #expect(output.contains("Invalid service ID: not-an-id."))
    #expect(!output.contains("Network request failed"))
}

@Test func departuresCommandAcceptsShortOptions() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["departures", "-s", "Ostrava,Hrabůvka,Benzina", "-T", "odis", "-m", "16:00", "-v", "-l", "1"]
    )

    #expect(output.contains("🚏 Departures Ostrava,Hrabůvka,Benzina (ODIS)"))
    #expect(output.contains("tariff zone 70 · platform 1"))
}

@Test func departuresCommandPrintsResolvedStationName() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(
            expectedStation: "Frýdek,sportovní",
            resolvedStationName: "Frýdek,Sportovní hala Polárka"
        )
    ).output(
        for: ["departures", "--from", "Frýdek,sportovní", "--timetable", "odis", "--time", "16:00", "--limit", "1"]
    )

    #expect(output.contains("🚏 Departures Frýdek,Sportovní hala Polárka (ODIS)"))
    #expect(!output.contains("🚏 Departures Frýdek,sportovní (ODIS)"))
}

@Test func departuresCommandAcceptsFromOption() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["departures", "--from", "Ostrava,Hrabůvka,Benzina", "--timetable", "odis", "--time", "16:00", "--limit", "1"]
    )

    #expect(output.contains("🚏 Departures Ostrava,Hrabůvka,Benzina (ODIS)"))
    #expect(output.contains("\u{001B}[1m16:03\u{001B}[0m"))
}

@Test func rootCommandWithOnePlacePrintsDepartures() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["Ostrava,Hrabůvka,Benzina", "--timetable", "odis", "--time", "16:00", "--limit", "1"]
    )

    #expect(output.contains("🚏 Departures Ostrava,Hrabůvka,Benzina (ODIS)"))
    #expect(output.contains("\u{001B}[1m16:03\u{001B}[0m"))
}

@Test func departuresCommandPrintsJSON() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient(expectedDepartureIsArrival: true)).output(
        for: [
            "departures", "--station", "Ostrava,Hrabůvka,Benzina", "--timetable", "odis",
            "--time", "16:00", "--arrival", "--format", "json", "--limit", "1",
        ]
    )
    let json = try jsonDictionary(output)
    let request = json["request"] as? [String: Any]

    #expect(request?["station"] as? String == "Ostrava,Hrabůvka,Benzina")
    #expect(request?["isArrival"] as? Bool == true)
    #expect((json["departures"] as? [[String: Any]])?.first?["lineName"] as? String == "Bus 980")
}

@Test func departuresCommandPrintsMarkdown() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "departures", "--station", "Ostrava,Hrabůvka,Benzina", "--timetable", "odis",
            "--format", "markdown", "--limit", "1",
        ]
    )

    #expect(output.contains("## 🚏 Departures"))
    #expect(output.contains("| # | Time | Line | Destination | Via |"))
    #expect(output.contains("| 1 | **16:03** | 🚌 <span style=\"color: #0000FF\">Bus 980</span> | Rožnov p.Radh.,,aut.st. | Frýdek-Místek,Místek,Anenská |"))
    #expect(output.contains(#"🚌 <span style="color: #0000FF">Bus 980</span>"#))
    #expect(!output.contains("| ID |"))
    #expect(!output.contains("Tariff Zone"))
    #expect(!output.contains("Currently no delay"))
}

@Test func departuresCommandPrintsVerboseMarkdown() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "departures", "--station", "Ostrava,Hrabůvka,Benzina", "--timetable", "odis",
            "--format", "markdown", "--limit", "1", "--verbose",
        ]
    )

    #expect(output.contains("| # | Time | Line | Destination | Tariff Zone | Platform | Via | Carrier | Delay | ID |"))
    #expect(output.contains("| 1 | **16:03** | 🚌 <span style=\"color: #0000FF\">Bus 980</span> | Rožnov p.Radh.,,aut.st. | 70 | 1 | Frýdek-Místek,Místek,Anenská | Transdev Slezsko a.s. | Currently no delay | `odis:1-4286-18.06.2026 16:03:00` |"))
}

@Test func departuresCommandRejectsUnknownOptions() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["departures", "--station", "Ostrava,Hrabůvka,Benzina", "--unknown"]
    )

    #expect(output.contains("❌ Error: Unknown option: --unknown."))
}

@Test func departuresCommandReportsAmbiguousStationNames() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(stationResultsByPrefix: ["sí pe": ambiguousPIDStationSuggestions()])
    ).output(
        for: ["departures", "sí pe", "--timetable", "pid"]
    )

    #expect(output.contains("❌ Error: Ambiguous station name: sí pe (Prague + PID)."))
    #expect(output.contains("1. Sídliště Petrovice - stop (Praha)"))
    #expect(output.contains("2. Sídliště Petřiny - stop (Praha)"))
}

@Test func timetablesCommandPrintsCommonAliases() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["timetables"])

    #expect(output.contains("🗂 Timetables:"))
    #expect(output.contains("vlakyautobusymhdvse"))
    #expect(output.contains("All timetables"))
    #expect(output.contains("pid"))
    #expect(output.contains("frydekmistek"))
    #expect(output.contains("odis"))
    #expect(output.contains("idsok"))
    #expect(output.contains("IDSOK"))
    #expect(output.contains("iredo"))
    #expect(output.contains("IREDO"))
    #expect(output.contains("duk"))
    #expect(output.contains("DÚK"))
    #expect(output.contains("idpk"))
    #expect(output.contains("idzk"))
    #expect(output.contains("ideska"))
    #expect(output.contains("karlovyvary"))
    #expect(output.contains("zlin"))
}

@Test func timetablesCommandPrintsJSON() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["timetables", "-o=json"])
    let json = try jsonDictionary(output)
    let timetables = json["timetables"] as? [[String: Any]]
    let cityTimetables = timetables?.filter {
        ($0["displayName"] as? String)?.hasPrefix("Urban Public Transport ") == true
    }
    let addedCityCatalogs = [
        "ceskykrumlov": "Český Krumlov",
        "milevsko": "Milevsko",
        "vimperk": "Vimperk",
        "novemestonamorave": "Nové Město na Moravě",
        "dvurkralove": "Dvůr Králové n. L.",
        "kostelecnadorlici": "Kostelec nad Orlicí",
        "rychnov": "Rychnov nad Kněžnou",
        "jablonec": "Jablonec nad Nisou",
        "ustinadorlici": "Ústí nad Orlicí",
        "kralupy": "Kralupy nad Vltavou",
        "mnisekpodbrdy": "Mníšek pod Brdy",
        "ricany": "Říčany",
        "roudnice": "Roudnice nad Labem",
        "varnsdorf": "Varnsdorf",
    ]

    #expect(timetables?.contains { $0["slug"] as? String == "vlakyautobusymhdvse" } == true)
    #expect(timetables?.contains { $0["displayName"] as? String == "All timetables" } == true)
    #expect(cityTimetables?.count == 106)
    #expect(cityTimetables?.contains { $0["slug"] as? String == "praha" } == false)
    for (slug, city) in addedCityCatalogs {
        #expect(cityTimetables?.contains {
            $0["slug"] as? String == slug
                && $0["displayName"] as? String == "Urban Public Transport \(city)"
        } == true)
    }
}

@Test func timetablesCommandRejectsUnknownOptions() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["timetables", "--unknown"])

    #expect(output.contains("❌ Error: Unknown option: --unknown."))
}

@Test func aliasesCommandAddsListsAndRemovesStopAliases() async throws {
    let aliasFile = temporaryAliasFile()
    let runner = englishCommandRunner(client: MockIDOSClient(), aliasFile: aliasFile)

    let addOutput = await runner.output(for: [
        "aliases", "add", "home", "-s", "Frýdek,Na Veselé", "-T", "odis",
    ])
    #expect(addOutput.contains("🌰 Alias added: home → Frýdek,Na Veselé (ODIS)"))

    let listOutput = await runner.output(for: ["aliases", "list"])
    #expect(listOutput.contains("🌰 Stop aliases:"))
    #expect(listOutput.contains("home → Frýdek,Na Veselé (ODIS)"))

    let jsonOutput = await runner.output(for: ["aliases", "list", "-o", "json"])
    let json = try jsonDictionary(jsonOutput)
    let aliases = try #require(json["aliases"] as? [[String: Any]])
    #expect(aliases.first?["name"] as? String == "home")
    #expect(aliases.first?["station"] as? String == "Frýdek,Na Veselé")
    #expect((aliases.first?["timetable"] as? [String: Any])?["slug"] as? String == "odis")

    let removeOutput = await runner.output(for: ["aliases", "remove", "home"])
    #expect(removeOutput.contains("🌰 Alias removed: home → Frýdek,Na Veselé (ODIS)"))

    let emptyOutput = await runner.output(for: ["aliases", "list"])
    #expect(emptyOutput.contains("🌰 No stop aliases saved."))
}

@Test func aliasesCommandAddsStopAliasWithPositionalStation() async throws {
    let aliasFile = temporaryAliasFile()
    let runner = englishCommandRunner(client: MockIDOSClient(), aliasFile: aliasFile)

    let addOutput = await runner.output(for: [
        "aliases", "add", "s", "Sídliště Petrovice", "--timetable", "pid",
    ])

    #expect(addOutput.contains("🌰 Alias added: s → Sídliště Petrovice (Prague + PID)"))

    let listOutput = await runner.output(for: ["aliases", "list"])
    #expect(listOutput.contains("s → Sídliště Petrovice (Prague + PID)"))
}

@Test func aliasesCommandRejectsAmbiguousStationNames() async {
    let aliasFile = temporaryAliasFile()
    let runner = englishCommandRunner(
        client: MockIDOSClient(stationResultsByPrefix: ["sí pe": ambiguousPIDStationSuggestions()]),
        aliasFile: aliasFile
    )

    let output = await runner.output(for: [
        "aliases", "add", "s", "sí pe", "--timetable", "pid",
    ])

    #expect(output.contains("❌ Error: Ambiguous station name: sí pe (Prague + PID)."))
    #expect(output.contains("1. Sídliště Petrovice - stop (Praha)"))
    #expect(output.contains("2. Sídliště Petřiny - stop (Praha)"))
}

@Test func aliasesCommandPrintsDatabasePath() async {
    let aliasFile = temporaryAliasFile()
    let output = await englishCommandRunner(client: MockIDOSClient(), aliasFile: aliasFile).output(for: ["aliases", "path"])

    #expect(output.contains("🌰 Alias database:"))
    #expect(output.contains(aliasFile.fileURL.path))
}

@Test func connectionCommandUsesStopAliasesAndInferredTimetable() async throws {
    let aliasFile = temporaryAliasFile()
    var database = StopAliasDatabase()
    try database.upsert(StopAlias(name: "home", station: "Frýdek,Na Veselé", timetable: try IDOSTimetable.resolve("odis")))
    try database.upsert(StopAlias(name: "work", station: "Ostrava,Hrabůvka,Benzina", timetable: try IDOSTimetable.resolve("odis")))
    try aliasFile.save(database)

    let output = await englishCommandRunner(
        client: MockIDOSClient(
            expectedConnectionTimetable: "odis",
            expectedFrom: "Frýdek,Na Veselé",
            expectedTo: "Ostrava,Hrabůvka,Benzina"
        ),
        aliasFile: aliasFile
    ).output(for: ["connections", "--from", "home", "--to", "work", "--limit", "1"])

    #expect(output.contains("🧭 Connections Frýdek,Na Veselé → Ostrava,Hrabůvka,Benzina (ODIS)"))
}

@Test func connectionCommandUsesStopAliasesInRouteExpression() async throws {
    let aliasFile = temporaryAliasFile()
    var database = StopAliasDatabase()
    try database.upsert(StopAlias(name: "home", station: "Frýdek,Na Veselé", timetable: try IDOSTimetable.resolve("odis")))
    try database.upsert(StopAlias(name: "work", station: "Ostrava,Hrabůvka,Benzina", timetable: try IDOSTimetable.resolve("odis")))
    try aliasFile.save(database)

    let output = await englishCommandRunner(
        client: MockIDOSClient(
            expectedConnectionTimetable: "odis",
            expectedFrom: "Frýdek,Na Veselé",
            expectedTo: "Ostrava,Hrabůvka,Benzina"
        ),
        aliasFile: aliasFile
    ).output(for: ["connections", "home→work", "--limit", "1"])

    #expect(output.contains("🧭 Connections Frýdek,Na Veselé → Ostrava,Hrabůvka,Benzina (ODIS)"))
}

@Test func connectionCommandUsesStopAliasesAsTwoPositionalPlaces() async throws {
    let aliasFile = temporaryAliasFile()
    var database = StopAliasDatabase()
    try database.upsert(StopAlias(name: "home", station: "Frýdek,Na Veselé", timetable: try IDOSTimetable.resolve("odis")))
    try database.upsert(StopAlias(name: "work", station: "Ostrava,Hrabůvka,Benzina", timetable: try IDOSTimetable.resolve("odis")))
    try aliasFile.save(database)

    let output = await englishCommandRunner(
        client: MockIDOSClient(
            expectedConnectionTimetable: "odis",
            expectedFrom: "Frýdek,Na Veselé",
            expectedTo: "Ostrava,Hrabůvka,Benzina"
        ),
        aliasFile: aliasFile
    ).output(for: ["connections", "home", "work", "--limit", "1"])

    #expect(output.contains("🧭 Connections Frýdek,Na Veselé → Ostrava,Hrabůvka,Benzina (ODIS)"))
}

@Test func rootCommandUsesStopAliasesAsTwoPositionalPlaces() async throws {
    let aliasFile = temporaryAliasFile()
    var database = StopAliasDatabase()
    try database.upsert(StopAlias(name: "home", station: "Frýdek,Na Veselé", timetable: try IDOSTimetable.resolve("odis")))
    try database.upsert(StopAlias(name: "work", station: "Ostrava,Hrabůvka,Benzina", timetable: try IDOSTimetable.resolve("odis")))
    try aliasFile.save(database)

    let output = await englishCommandRunner(
        client: MockIDOSClient(
            expectedConnectionTimetable: "odis",
            expectedFrom: "Frýdek,Na Veselé",
            expectedTo: "Ostrava,Hrabůvka,Benzina"
        ),
        aliasFile: aliasFile
    ).output(for: ["home", "work", "--limit", "1"])

    #expect(output.contains("🧭 Connections Frýdek,Na Veselé → Ostrava,Hrabůvka,Benzina (ODIS)"))
}

@Test func departuresCommandUsesStopAliasAndInferredTimetable() async throws {
    let aliasFile = temporaryAliasFile()
    var database = StopAliasDatabase()
    try database.upsert(StopAlias(
        name: "benzina",
        station: "Ostrava,Hrabůvka,Benzina",
        timetable: try IDOSTimetable.resolve("odis")
    ))
    try aliasFile.save(database)

    let output = await englishCommandRunner(client: MockIDOSClient(), aliasFile: aliasFile).output(
        for: ["departures", "--station", "benzina", "--limit", "1"]
    )

    #expect(output.contains("🚏 Departures Ostrava,Hrabůvka,Benzina (ODIS)"))
}

@Test func rootCommandUsesStopAliasAsDepartureStation() async throws {
    let aliasFile = temporaryAliasFile()
    var database = StopAliasDatabase()
    try database.upsert(StopAlias(
        name: "work",
        station: "Ostrava,Hrabůvka,Benzina",
        timetable: try IDOSTimetable.resolve("odis")
    ))
    try aliasFile.save(database)

    let output = await englishCommandRunner(client: MockIDOSClient(), aliasFile: aliasFile).output(
        for: ["work", "--limit", "1"]
    )

    #expect(output.contains("🚏 Departures Ostrava,Hrabůvka,Benzina (ODIS)"))
}

@Test func connectionCommandRejectsConflictingStopAliasTimetables() async throws {
    let aliasFile = temporaryAliasFile()
    var database = StopAliasDatabase()
    try database.upsert(StopAlias(name: "home", station: "Frýdek,Na Veselé", timetable: try IDOSTimetable.resolve("odis")))
    try database.upsert(StopAlias(name: "main", station: "Praha hl.n.", timetable: try IDOSTimetable.resolve("vlaky")))
    try aliasFile.save(database)

    let output = await englishCommandRunner(client: MockIDOSClient(), aliasFile: aliasFile).output(
        for: ["connections", "--from", "home", "--to", "main"]
    )

    #expect(output.contains("❌ Error: Stop aliases use conflicting timetables: ODIS and Trains."))
}

@Test func timetableResolverAcceptsKnownAliasesAndCustomSlugs() throws {
    #expect(try IDOSTimetable.resolve("all timetables").slug == "vlakyautobusymhdvse")
    #expect(try IDOSTimetable.resolve("Prague + PID").slug == "pid")
    #expect(try IDOSTimetable.resolve("IDSOK").slug == "idsok")
    #expect(try IDOSTimetable.resolve("IREDO").slug == "iredo")
    #expect(try IDOSTimetable.resolve("DÚK").slug == "duk")
    #expect(try IDOSTimetable.resolve("IDPK").slug == "idpk")
    #expect(try IDOSTimetable.resolve("IDZK").slug == "idzk")
    #expect(try IDOSTimetable.resolve("IDESKA").slug == "ideska")
    #expect(try IDOSTimetable.resolve("Frýdek-Místek").slug == "frydekmistek")
    #expect(try IDOSTimetable.resolve("Urban Public Transport Karlovy Vary").slug == "karlovyvary")
    #expect(try IDOSTimetable.resolve("Český Krumlov").slug == "ceskykrumlov")
    #expect(try IDOSTimetable.resolve("Dvůr Králové n. L.").slug == "dvurkralove")
    #expect(try IDOSTimetable.resolve("Jablonec nad Nisou").slug == "jablonec")
    #expect(try IDOSTimetable.resolve("Kralupy nad Vltavou").slug == "kralupy")
    #expect(try IDOSTimetable.resolve("Roudnice nad Labem").slug == "roudnice")
    #expect(try IDOSTimetable.resolve("Rychnov nad Kněžnou").slug == "rychnov")
    #expect(try IDOSTimetable.resolve("Zlín a Otrokovice").slug == "zlin")
    #expect(try IDOSTimetable.resolve("karlovyvary").slug == "karlovyvary")
}

@Test func timetableResolverRejectsUnknownNonSlugNames() throws {
    do {
        _ = try IDOSTimetable.resolve("MHD Karlovy Vary")
        Issue.record("Expected invalid timetable error.")
    } catch IDOSError.invalidTimetable(let value) {
        #expect(value == "MHD Karlovy Vary")
    } catch {
        Issue.record("Unexpected error: \(error).")
    }
}

@Test func directConnectionRequestUsesIDOSOnlyDirectParameter() {
    let directRequest = IDOSConnectionRequest(from: "Praha", to: "Brno", onlyDirect: true)
    let normalRequest = IDOSConnectionRequest(from: "Praha", to: "Brno")

    #expect(directRequest.formItems.contains(URLQueryItem(name: "OnlyDirect", value: "true")))
    #expect(!normalRequest.formItems.contains { $0.name == "OnlyDirect" })
}

@Test func connectionRequestUsesIDOSArrivalTimeParameter() {
    let arrivalRequest = IDOSConnectionRequest(from: "Praha", to: "Brno", isArrival: true)
    let departureRequest = IDOSConnectionRequest(from: "Praha", to: "Brno")

    #expect(arrivalRequest.formItems.contains(URLQueryItem(name: "IsArr", value: "True")))
    #expect(departureRequest.formItems.contains(URLQueryItem(name: "IsArr", value: "False")))
}

@Test func connectionRequestDistinguishesSelectedStationFromFreeText() throws {
    let suggestion = IDOSSuggestion(
        selectedText: "Frýdek-Místek",
        text: "Frýdek-Místek",
        description: "station, district Frýdek-Místek, trains",
        value: "100003",
        value2: "10357"
    )
    let selection = try #require(IDOSPlaceSelection(suggestion: suggestion))
    let destination = IDOSPlaceSelection(text: "Ostrava", listID: "1", itemID: "10278")
    let selectedRequest = IDOSConnectionRequest(
        from: "Frýdek-Místek",
        to: "Ostrava",
        fromSelection: selection,
        toSelection: destination
    )
    let freeTextRequest = IDOSConnectionRequest(from: "Frýdek-Místek", to: "Ostrava")

    #expect(selection.text == "Frýdek-Místek")
    #expect(selectedRequest.formItems.contains(URLQueryItem(
        name: "FromHidden",
        value: "Frýdek-Místek%100003%10357"
    )))
    #expect(selectedRequest.formItems.contains(URLQueryItem(
        name: "ToHidden",
        value: "Ostrava%1%10278"
    )))
    #expect(freeTextRequest.formItems.contains(URLQueryItem(name: "FromHidden", value: "%0")))
    #expect(freeTextRequest.formItems.contains(URLQueryItem(name: "ToHidden", value: "%0")))
}

@Test func connectionRequestCarriesCurrentWGS84Location() {
    let location = IDOSPlaceSelection.currentLocation(
        text: "My location",
        latitude: 49.1973914,
        longitude: 16.6191237
    )
    let request = IDOSConnectionRequest(
        from: location.text,
        to: "Brno",
        fromSelection: location
    )

    #expect(request.formItems.contains(URLQueryItem(
        name: "FromHidden",
        value: "loc: 49.197391; 16.619124%myPosition=true"
    )))
}

@Test func connectionRequestUsesIDOSMaximumTransfersParameter() {
    let limitedRequest = IDOSConnectionRequest(from: "Praha", to: "Brno", maxTransfers: 0)
    let normalRequest = IDOSConnectionRequest(from: "Praha", to: "Brno")

    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.AdvancedFormIsOpen", value: "True")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MaxChange", value: "0")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MinTime", value: "-1")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MaxTime", value: "240")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "trTypeId[154]", value: "154")))
    #expect(!normalRequest.formItems.contains { $0.name == "AdvancedForm.AdvancedFormIsOpen" })
    #expect(!normalRequest.formItems.contains { $0.name == "AdvancedForm.MaxChange" })
}

@Test func connectionRequestUsesIDOSMinimumTransferTimeParameter() {
    let limitedRequest = IDOSConnectionRequest(from: "Praha", to: "Brno", minimumTransferTime: 10)
    let normalRequest = IDOSConnectionRequest(from: "Praha", to: "Brno")

    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.AdvancedFormIsOpen", value: "True")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MaxChange", value: "4")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MinTime", value: "10")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MaxTime", value: "240")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MaxArcLength", value: "60")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MaxArcLengthCity", value: "10")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "trTypeId[301]", value: "301")))
    #expect(!normalRequest.formItems.contains { $0.name == "AdvancedForm.AdvancedFormIsOpen" })
    #expect(!normalRequest.formItems.contains { $0.name == "AdvancedForm.MinTime" })
}

@Test func connectionRequestResolvesRepeatableTransportModeFiltersToIDOSCheckboxes() {
    func transportTypeIDs(in request: IDOSConnectionRequest) -> [Int] {
        request.formItems.compactMap { item in
            guard item.name.hasPrefix("trTypeId[") else { return nil }
            return item.value.flatMap(Int.init)
        }
    }

    let onlyRequest = IDOSConnectionRequest(
        from: "Praha",
        to: "Brno",
        transportModeFilters: [
            .init(operation: .only, mode: .highestQualityTrain),
            .init(operation: .only, mode: .cityBus),
        ]
    )
    let excludedRequest = IDOSConnectionRequest(
        from: "Praha",
        to: "Brno",
        transportModeFilters: [
            .init(operation: .exclude, mode: .regionalTrain),
        ]
    )
    let combinedRequest = IDOSConnectionRequest(
        from: "Praha",
        to: "Brno",
        transportModeFilters: [
            .init(operation: .only, mode: .highestQualityTrain),
            .init(operation: .only, mode: .cityBus),
            .init(operation: .exclude, mode: .highestQualityTrain),
        ]
    )

    #expect(transportTypeIDs(in: onlyRequest) == [150, 301])
    #expect(transportTypeIDs(in: excludedRequest) == [
        150, 151, 152, 154, 155, 156,
        200, 201, 202,
        300, 301, 303, 306,
    ])
    #expect(transportTypeIDs(in: combinedRequest) == [301])
    #expect(onlyRequest.formItems.contains(
        URLQueryItem(name: "AdvancedForm.AdvancedFormIsOpen", value: "True")
    ))
}

@Test func connectionRequestUsesIDOSWalkingAndTransferParameters() {
    let customizedRequest = IDOSConnectionRequest(
        from: "Praha",
        to: "Brno",
        maximumTransferTime: 360,
        maximumWalkingTime: 45,
        maximumCityWalkingTime: 20,
        walkToNearbyStops: false,
        sameNameWalkingTransfersOnly: true
    )

    #expect(customizedRequest.formItems.contains(
        URLQueryItem(name: "AdvancedForm.AdvancedFormIsOpen", value: "True")
    ))
    #expect(customizedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MaxTime", value: "360")))
    #expect(customizedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MaxArcLength", value: "45")))
    #expect(customizedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MaxArcLengthCity", value: "20")))
    #expect(customizedRequest.formItems.contains(
        URLQueryItem(name: "AdvancedForm.MaxArcLengthFrom", value: "false")
    ))
    #expect(customizedRequest.formItems.contains(
        URLQueryItem(name: "AdvancedForm.LimitWalkArcs", value: "true")
    ))
}

@Test func connectionRequestUsesIDOSAdditionalParameters() {
    let customizedRequest = IDOSConnectionRequest(
        from: "Praha",
        to: "Brno",
        wheelchairAccessibleConnectionsOnly: true,
        lowFloorConnectionsOnly: false,
        preferTrainsOverBuses: true,
        trainConnectionsForWheelchairPassengers: false,
        trainConnectionsForPassengersWithChildren: true,
        connectionsForPassengersWithBicycles: false,
        preferBusyRoutes: true
    )
    let normalRequest = IDOSConnectionRequest(from: "Praha", to: "Brno")

    #expect(customizedRequest.formItems.contains(
        URLQueryItem(name: "AdvancedForm.AdvancedFormIsOpen", value: "True")
    ))
    #expect(customizedRequest.formItems.contains(
        URLQueryItem(name: "AdvancedForm.LowDeckConn", value: "true")
    ))
    #expect(customizedRequest.formItems.contains(
        URLQueryItem(name: "AdvancedForm.LowDeckConnTr", value: "false")
    ))
    #expect(customizedRequest.formItems.contains(
        URLQueryItem(name: "AdvancedForm.PrefereTrains", value: "true")
    ))
    #expect(customizedRequest.formItems.contains(
        URLQueryItem(name: "AdvancedForm.WheelChair", value: "false")
    ))
    #expect(customizedRequest.formItems.contains(
        URLQueryItem(name: "AdvancedForm.Children", value: "true")
    ))
    #expect(customizedRequest.formItems.contains(
        URLQueryItem(name: "AdvancedForm.Bicycle", value: "false")
    ))
    #expect(customizedRequest.formItems.contains(
        URLQueryItem(name: "AdvancedForm.AutoStrategy", value: "true")
    ))
    #expect(!normalRequest.formItems.contains { item in
        [
            "AdvancedForm.LowDeckConn",
            "AdvancedForm.LowDeckConnTr",
            "AdvancedForm.PrefereTrains",
            "AdvancedForm.WheelChair",
            "AdvancedForm.Children",
            "AdvancedForm.Bicycle",
            "AdvancedForm.AutoStrategy",
        ].contains(item.name)
    })
}

@Test func connectionRequestUsesIDOSBedOrCouchettePreference() {
    let formValues: [TransitBedOrCouchettePreference: String] = [
        .noLimitation: "0",
        .use: "1",
        .doNotUse: "2",
    ]

    for preference in TransitBedOrCouchettePreference.allCases {
        let request = IDOSConnectionRequest(
            from: "Praha",
            to: "Brno",
            bedOrCouchettePreference: preference
        )

        #expect(request.formItems.contains(URLQueryItem(
            name: "AdvancedForm.UseBeds",
            value: formValues[preference]
        )))
        #expect(request.formItems.contains(URLQueryItem(
            name: "AdvancedForm.AdvancedFormIsOpen",
            value: "True"
        )))
    }

    let normalRequest = IDOSConnectionRequest(from: "Praha", to: "Brno")
    #expect(!normalRequest.formItems.contains { $0.name == "AdvancedForm.UseBeds" })
}

@Test func connectionRequestUsesIDOSViaParameters() throws {
    let selectedVia = try #require(IDOSPlaceSelection(suggestion: IDOSSuggestion(
        selectedText: "Pardubice hl.n.",
        text: "Pardubice hl.n.",
        description: "station, district Pardubice, trains",
        value: "100003",
        value2: "5456463"
    )))
    let viaRequest = IDOSConnectionRequest(
        from: "Praha",
        to: "Brno",
        via: ["Pardubice hl.n.", "Olomouc"],
        viaSelections: [selectedVia, nil]
    )
    let normalRequest = IDOSConnectionRequest(from: "Praha", to: "Brno")

    #expect(viaRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.AdvancedFormIsOpen", value: "True")))
    #expect(viaRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.Via[0]", value: "Pardubice hl.n.")))
    #expect(viaRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.Via[1]", value: "Olomouc")))
    #expect(viaRequest.formItems.contains(URLQueryItem(
        name: "AdvancedForm.ViaHidden[0]",
        value: "Pardubice hl.n.%100003%5456463"
    )))
    #expect(viaRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.ViaHidden[1]", value: "")))
    #expect(viaRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MaxChange", value: "4")))
    #expect(viaRequest.formItems.contains(URLQueryItem(name: "trTypeId[301]", value: "301")))
    #expect(!normalRequest.formItems.contains { $0.name.hasPrefix("AdvancedForm.Via[") })
    #expect(!normalRequest.formItems.contains { $0.name.hasPrefix("AdvancedForm.ViaHidden[") })
}

@Test func connectionRequestCarriesResultLimit() {
    let request = IDOSConnectionRequest(from: "Praha", to: "Brno", resultLimit: 12)

    #expect(request.resultLimit == 12)
    #expect(!request.formItems.contains { $0.name == "resultLimit" })
}

@Test func departuresRequestUsesIDOSParameters() {
    let selection = IDOSPlaceSelection(
        text: "Ostrava,Hrabůvka,Benzina",
        listID: "200003",
        itemID: "85812"
    )
    let request = IDOSDeparturesRequest(
        station: "Ostrava,Hrabůvka,Benzina",
        stationSelection: selection,
        date: "18.6.2026",
        time: "16:00",
        isArrival: true
    )

    #expect(request.formItems.contains(URLQueryItem(name: "From", value: "Ostrava,Hrabůvka,Benzina")))
    #expect(request.formItems.contains(URLQueryItem(
        name: "FromHidden",
        value: "Ostrava,Hrabůvka,Benzina%200003%85812"
    )))
    #expect(request.formItems.contains(URLQueryItem(name: "Date", value: "18.6.2026")))
    #expect(request.formItems.contains(URLQueryItem(name: "Time", value: "16:00")))
    #expect(request.formItems.contains(URLQueryItem(name: "IsArr", value: "True")))
    #expect(request.formItems.contains(URLQueryItem(name: "submit", value: "true")))
}

@Test func stationTimetableRequestUsesIDOSParameters() {
    let request = IDOSStationTimetableRequest(
        timetable: IDOSTimetable(slug: "pid", displayName: "Prague + PID"),
        line: " Bus 154 ",
        from: " Strašnická ",
        to: " Sídliště Libuš ",
        date: "17.7.2026",
        wholeWeek: true
    )
    let values = Dictionary(uniqueKeysWithValues: request.queryItems.map { ($0.name, $0.value) })

    #expect(request.isComplete)
    #expect(values["date"] == "17.7.2026")
    #expect(values["l"] == "Bus 154")
    #expect(values["f"] == "Strašnická")
    #expect(values["t"] == "Sídliště Libuš")
    #expect(values["wholeweek"] == "true")
    #expect(values["submit"] == "true")
}

@Test func odisStationTimetableMunicipalitiesMatchIDOSParameters() throws {
    let odis = try IDOSTimetable.resolve("odis")
    let municipalities = IDOSStationTimetableMunicipality.available(for: odis)
    let frydekMistek = try #require(
        try IDOSStationTimetableMunicipality.resolve("frydek-mistek", timetable: odis)
    )
    let request = IDOSStationTimetableRequest(
        timetable: odis,
        municipality: frydekMistek,
        line: "Bus 301",
        from: "Řepiště,,U kříže",
        to: "Místek,Riviéra"
    )
    let requestValues = Dictionary(uniqueKeysWithValues: request.queryItems.map { ($0.name, $0.value) })
    let suggestionValues = Dictionary(uniqueKeysWithValues: IDOSClient
        .stationTimetableSuggestionQueryItems(
            prefix: "301",
            limit: 8,
            municipality: frydekMistek,
            onlyStation: false
        )
        .map { ($0.name, $0.value) })

    #expect(municipalities.map(\.name) == [
        "Bruntál", "Český Těšín", "Frýdek-Místek", "Havířov", "Karviná", "Krnov",
        "Nový Jičín", "Opava", "Orlová", "Ostrava", "Studénka", "Třinec",
    ])
    #expect(frydekMistek.timetableIndex == 3)
    #expect(frydekMistek.timetableName == "FM")
    #expect(try IDOSStationTimetableMunicipality.resolve("FM", timetable: odis) == frydekMistek)
    #expect(IDOSStationTimetableMunicipality.default(for: odis)?.name == "Ostrava")
    #expect(IDOSStationTimetableMunicipality.available(
        for: IDOSTimetable(slug: "pid", displayName: "Prague + PID")
    ).isEmpty)
    #expect(requestValues["ttn"] == "FM")
    #expect(suggestionValues["bindTtIndex"] == "3")

    let defaultRequest = IDOSStationTimetableRequest(
        timetable: odis,
        line: "Tram 1",
        from: "Dubina",
        to: "Hlučínská"
    )
    let defaultValues = Dictionary(uniqueKeysWithValues: defaultRequest.queryItems.map { ($0.name, $0.value) })
    #expect(defaultValues["ttn"] == "ODIS")
}

@Test func iredoStationTimetableMunicipalitiesMatchIDOSParameters() throws {
    let iredo = try IDOSTimetable.resolve("iredo")
    let municipalities = IDOSStationTimetableMunicipality.available(for: iredo)
    let chrudim = try #require(
        try IDOSStationTimetableMunicipality.resolve("Chrudim", timetable: iredo)
    )
    let request = IDOSStationTimetableRequest(
        timetable: iredo,
        municipality: chrudim,
        line: "Bus 1",
        from: "Dopravní terminál",
        to: "Na Větrníku"
    )
    let requestValues = Dictionary(uniqueKeysWithValues: request.queryItems.map { ($0.name, $0.value) })
    let suggestionValues = Dictionary(uniqueKeysWithValues: IDOSClient
        .stationTimetableSuggestionQueryItems(
            prefix: "1",
            limit: 8,
            municipality: chrudim,
            onlyStation: false
        )
        .map { ($0.name, $0.value) })

    #expect(municipalities.map(\.name) == [
        "Dvůr Králové nad Labem", "Chrudim", "Náchod", "Přelouč",
        "Rychnov nad Kněžnou", "Týniště nad Orlicí", "Vrchlabí",
    ])
    #expect(chrudim.timetableIndex == 3)
    #expect(chrudim.timetableName == "Chrudim")
    #expect(
        try IDOSStationTimetableMunicipality.resolve("DvurKral", timetable: iredo)?.name
            == "Dvůr Králové nad Labem"
    )
    #expect(IDOSStationTimetableMunicipality.default(for: iredo)?.name == "Dvůr Králové nad Labem")
    #expect(requestValues["ttn"] == "Chrudim")
    #expect(suggestionValues["bindTtIndex"] == "3")

    let defaultRequest = IDOSStationTimetableRequest(
        timetable: iredo,
        line: "Bus 481",
        from: "Dvůr Králové n.L.,,nemocnice",
        to: "Dvůr Králové n.L.,,žel.st."
    )
    let defaultValues = Dictionary(
        uniqueKeysWithValues: defaultRequest.queryItems.map { ($0.name, $0.value) }
    )
    #expect(defaultValues["ttn"] == "DvurKral")
}

@Test func idolStationTimetableMunicipalitiesMatchIDOSParameters() throws {
    let idol = try IDOSTimetable.resolve("idol")
    let municipalities = IDOSStationTimetableMunicipality.available(for: idol)
    let liberec = try #require(
        try IDOSStationTimetableMunicipality.resolve("Liberec", timetable: idol)
    )
    let request = IDOSStationTimetableRequest(
        timetable: idol,
        municipality: liberec,
        line: "Tram 2",
        from: "Fügnerova",
        to: "Dolní Hanychov"
    )
    let requestValues = Dictionary(uniqueKeysWithValues: request.queryItems.map { ($0.name, $0.value) })
    let suggestionValues = Dictionary(uniqueKeysWithValues: IDOSClient
        .stationTimetableSuggestionQueryItems(
            prefix: "2",
            limit: 8,
            municipality: liberec,
            onlyStation: false
        )
        .map { ($0.name, $0.value) })

    #expect(municipalities.map(\.name) == [
        "Česká Lípa", "Jablonec nad Nisou", "Liberec", "Turnov",
    ])
    #expect(liberec.timetableIndex == 4)
    #expect(liberec.timetableName == "Liberec")
    #expect(
        try IDOSStationTimetableMunicipality.resolve("CeskaLipa", timetable: idol)?.name
            == "Česká Lípa"
    )
    #expect(IDOSStationTimetableMunicipality.default(for: idol)?.name == "Česká Lípa")
    #expect(requestValues["ttn"] == "Liberec")
    #expect(suggestionValues["bindTtIndex"] == "4")

    let defaultRequest = IDOSStationTimetableRequest(
        timetable: idol,
        line: "Bus 202",
        from: "Sídliště Lada",
        to: "Hlavní nádraží"
    )
    let defaultValues = Dictionary(
        uniqueKeysWithValues: defaultRequest.queryItems.map { ($0.name, $0.value) }
    )
    #expect(defaultValues["ttn"] == "CeskaLipa")
}

@Test func additionalIntegratedSystemMunicipalitiesMatchIDOSParameters() throws {
    let cases: [(
        slug: String,
        defaultIdentifier: String,
        municipalities: [IDOSStationTimetableMunicipality]
    )] = [
        (
            "idsok",
            "Hranice",
            [
                .init(name: "Hranice", timetableIndex: 2, timetableName: "Hranice"),
                .init(name: "Olomouc", timetableIndex: 3, timetableName: "Olomouc"),
                .init(name: "Prostějov", timetableIndex: 5, timetableName: "Prostej"),
                .init(name: "Přerov", timetableIndex: 4, timetableName: "Prerov"),
                .init(name: "Šumperk", timetableIndex: 6, timetableName: "Sumperk"),
                .init(name: "Zábřeh", timetableIndex: 7, timetableName: "Zabreh"),
            ]
        ),
        (
            "duk",
            "UL",
            [
                .init(name: "Bílina", timetableIndex: 8, timetableName: "Bilina"),
                .init(name: "Děčín", timetableIndex: 5, timetableName: "DC"),
                .init(name: "Chomutov", timetableIndex: 3, timetableName: "Chomutov"),
                .init(
                    name: "Klášterec nad Ohří",
                    timetableIndex: 9,
                    timetableName: "KlasterecNadOhri"
                ),
                .init(name: "Most-Litvínov", timetableIndex: 6, timetableName: "Most"),
                .init(
                    name: "Roudnice nad Labem",
                    timetableIndex: 7,
                    timetableName: "RoudniceNadLabem"
                ),
                .init(name: "Teplice", timetableIndex: 4, timetableName: "Teplice"),
                .init(name: "Ústí nad Labem", timetableIndex: 2, timetableName: "UL"),
                .init(name: "Varnsdorf", timetableIndex: 10, timetableName: "Varnsdorf"),
            ]
        ),
        (
            "idpk",
            "Plzen",
            [
                .init(name: "Domažlice", timetableIndex: 3, timetableName: "DO"),
                .init(name: "Klatovy", timetableIndex: 4, timetableName: "KT"),
                .init(name: "Plzeň", timetableIndex: 2, timetableName: "Plzen"),
                .init(name: "Rokycany", timetableIndex: 5, timetableName: "Rokycany"),
                .init(name: "Stříbro", timetableIndex: 6, timetableName: "Stribro"),
                .init(name: "Tachov", timetableIndex: 7, timetableName: "Tachov"),
            ]
        ),
        (
            "idzk",
            "UherskeHradiste",
            [
                .init(
                    name: "Uherské Hradiště",
                    timetableIndex: 2,
                    timetableName: "UherskeHradiste"
                ),
                .init(name: "Vsetín", timetableIndex: 3, timetableName: "Vsetin"),
            ]
        ),
        (
            "ideska",
            "CesBud",
            [
                .init(name: "České Budějovice", timetableIndex: 2, timetableName: "CesBud"),
                .init(name: "Český Krumlov", timetableIndex: 3, timetableName: "CeskyKrumlov"),
                .init(name: "Jindřichův Hradec", timetableIndex: 4, timetableName: "JinHrad"),
                .init(name: "Milevsko", timetableIndex: 5, timetableName: "Milevsko"),
                .init(name: "Písek", timetableIndex: 6, timetableName: "Pisek"),
                .init(name: "Strakonice", timetableIndex: 7, timetableName: "Strakon"),
                .init(name: "Tábor", timetableIndex: 8, timetableName: "Tabor"),
                .init(name: "Vimperk", timetableIndex: 9, timetableName: "Vimperk"),
            ]
        ),
    ]

    for item in cases {
        let timetable = try IDOSTimetable.resolve(item.slug)
        let municipalities = IDOSStationTimetableMunicipality.available(for: timetable)
        let expectedDefault = try #require(
            item.municipalities.first { $0.timetableName == item.defaultIdentifier }
        )
        let selected = try #require(item.municipalities.last)
        let request = IDOSStationTimetableRequest(
            timetable: timetable,
            municipality: selected,
            line: "Bus 1",
            from: "Start",
            to: "Destination"
        )
        let requestValues = Dictionary(
            uniqueKeysWithValues: request.queryItems.map { ($0.name, $0.value) }
        )
        let suggestionValues = Dictionary(uniqueKeysWithValues: IDOSClient
            .stationTimetableSuggestionQueryItems(
                prefix: "1",
                limit: 8,
                municipality: selected,
                onlyStation: false
            )
            .map { ($0.name, $0.value) })

        #expect(municipalities == item.municipalities)
        #expect(IDOSStationTimetableMunicipality.default(for: timetable) == expectedDefault)
        #expect(
            try IDOSStationTimetableMunicipality.resolve(
                selected.timetableName,
                timetable: timetable
            ) == selected
        )
        #expect(requestValues["ttn"] == selected.timetableName)
        #expect(suggestionValues["bindTtIndex"] == String(selected.timetableIndex))
    }
}

@Test func stationTimetableLineSuggestionKeepsDirectionTerminals() throws {
    let data = Data(
        #"[{"text":"Bus 154","description":"Strašnická-Sídliště Libuš","from":"Strašnická","to":"Sídliště Libuš"}]"#.utf8
    )
    let suggestions = try JSONDecoder().decode([IDOSSuggestion].self, from: data)

    #expect(suggestions.first?.text == "Bus 154")
    #expect(suggestions.first?.from == "Strašnická")
    #expect(suggestions.first?.to == "Sídliště Libuš")
}

@Test func presentationTextUsesUnicodeArrowsInHumanReadableIDOSValues() {
    let suggestion = IDOSSuggestion(
        selectedText: "Praha->Brno",
        text: "Praha -> Brno",
        description: "Praha hl.n. -> Brno hl.n.",
        region: "Praha -> Jihomoravský kraj",
        value: "opaque->identifier",
        from: "Praha->",
        to: "->Brno"
    )
    let normalized = IDOSPresentationText.normalize(suggestion)

    #expect(IDOSPresentationText.normalize("Praha -> Brno") == "Praha → Brno")
    #expect(normalized.selectedText == "Praha→Brno")
    #expect(normalized.text == "Praha → Brno")
    #expect(normalized.description == "Praha hl.n. → Brno hl.n.")
    #expect(normalized.region == "Praha → Jihomoravský kraj")
    #expect(normalized.from == "Praha→")
    #expect(normalized.to == "→Brno")
    #expect(normalized.value == "opaque->identifier")
}

@Test func jsonpParserDecodesCallbackPayload() throws {
    let data = Data(#"cb([{"text":"Praha"}]);"#.utf8)
    let payload = try IDOSJSONP.decodePayload(from: data)
    let suggestions = try JSONDecoder().decode([IDOSSuggestion].self, from: payload)

    #expect(suggestions == [IDOSSuggestion(
        selectedText: nil,
        text: "Praha",
        description: nil,
        region: nil,
        value: nil,
        value2: nil,
        iconId: nil,
        coorX: nil,
        coorY: nil
    )])
}

@Test func stationTimetableParserSeparatesRouteSchedulesExplanationsAndNotes() throws {
    let html = """
    <div class="connection-head relative zjr-panel">
      <h2 class="reset departures__title">
        <img src="/images/vyluka64.png" class="exception" title="Lockout timetable" />
        <span>Line Bus 154</span>
      </h2>
    </div>
    <div class="zjr-stations">
      <table class="zjr-table">
        <tbody>
          <tr>
            <td class="zjr-table__time right valign-top bold">0</td>
            <td class="zjr-table__station_name">
              <span class="bold">Strašnick&#225;</span>
              <span title="platform">(1)</span>
              <span title="request stop">(x)</span>
            </td>
            <td class="tarif">0</td>
          </tr>
          <tr>
            <td class="zjr-table__time right valign-top bold">1</td>
            <td class="zjr-table__station_name">
              <a class="fromStation" href="javascript:;" title="search from the station">Na Hroudě</a>
              <span title="stanoviště">(2)</span>
              <span title="wheelchair accessible stop">#</span>
            </td>
            <td class="tarif">B</td>
          </tr>
        </tbody>
      </table>
    </div>
    <div class="zjr-table-container zjrBorderBottom ">
      <table class="zjr-table times">
        <thead>
          <tr><th class="zjr-table__date right"></th><th>17.7.2026 Friday</th></tr>
        </thead>
        <tbody>
          <tr><td class="zjr-table__date right bold valign-top">5</td><td>13 35A <span>55</span></td></tr>
          <tr><td class="zjr-table__date right bold valign-top">6</td><td></td></tr>
        </tbody>
      </table>
    </div>
    <ul class="remarks-list">
      <li class="remarks-list__item"><img title="Line description" /> valid from 1.7.2026</li>
      <li class="remarks-list__item"><img title="Information note" /> 1: stanoviště</li>
      <li class="remarks-list__item"><img title="Information note" /> A: runs only to stop Háje</li>
      <li class="remarks-list__item"><img title="Information note" /> B: unused marker information</li>
      <li class="remarks-list__item"><img title="Information note" /> : Board through the front door</li>
    </ul>
    """
    let request = IDOSStationTimetableRequest(
        timetable: IDOSTimetable(slug: "pid", displayName: "Prague + PID"),
        line: "Bus 154",
        from: "Strašnická",
        to: "Sídliště Libuš"
    )
    let timetable = try #require(IDOSStationTimetableParser.parse(
        html: html,
        request: request,
        shareURL: "https://idos.cz/en/pid/zjr/?l=154"
    ))

    #expect(timetable.lineName == "Bus 154")
    #expect(timetable.transportMode == .bus)
    #expect(timetable.fromStop == "Strašnická")
    #expect(timetable.toStop == "Sídliště Libuš")
    #expect(timetable.isLockout)
    #expect(timetable.shareURL == "https://idos.cz/en/pid/zjr/?l=154")
    #expect(timetable.stops.map(\.name) == ["Strašnická", "Na Hroudě"])
    #expect(timetable.stops.map(\.minuteOffset) == [0, 1])
    #expect(timetable.stops.map(\.tariffZone) == ["0", "B"])
    #expect(timetable.stops.map(\.platform) == ["1", "2"])
    #expect(timetable.selectedStop?.name == "Strašnická")
    #expect(timetable.stops[0].notes == ["request stop"])
    #expect(timetable.stops[1].notes == ["wheelchair accessible stop"])
    #expect(timetable.schedules == [
        IDOSStationTimetableSchedule(
            label: "17.7.2026 Friday",
            hours: [
                IDOSStationTimetableHour(hour: "5", departures: ["13", "35A", "55"]),
                IDOSStationTimetableHour(hour: "6", departures: []),
            ]
        )
    ])
    #expect(timetable.explanations == ["A: runs only to stop Háje"])
    #expect(timetable.notes == [
        "valid from 1.7.2026",
        "B: unused marker information",
        "Board through the front door",
    ])
}

@Test func stationTimetableDecodesLegacyJSONWithoutExplanations() throws {
    let legacyJSON = """
    {
      "timetable": {"slug": "pid", "displayName": "Prague + PID"},
      "lineName": "Bus 154",
      "fromStop": "Strašnická",
      "toStop": "Sídliště Libuš",
      "stops": [],
      "schedules": [],
      "notes": ["valid from 1.7.2026"],
      "isLockout": false
    }
    """

    let timetable = try JSONDecoder().decode(
        IDOSStationTimetable.self,
        from: Data(legacyJSON.utf8)
    )

    #expect(timetable.explanations.isEmpty)
    #expect(timetable.notes == ["valid from 1.7.2026"])
}

@Test func connectionParserReadsBasicResultHtml() {
    let html = """
    <div id="connectionBox-396829589" class="box connection" data-share-url="https://idos.cz/detail">
      <p class="reset total">Overall time <strong>3 h 40 min</strong></p>
      <h3 title="fast train" style="color: #FF0000;"><span>R9 (R 981 Vysocina)</span></h3>
      <p class="specs">
        <span title="train also consists of 1st class coaches">1.2.</span>
        <span title="carriage with a wireless internet connection">Wi</span>
        <span title="carriage of registered luggage (until full capacity)">K</span>
        <span title="carriage suitable for transport of passengers using wheelchairs">NPP</span>
      </p>
      <p class="reset time  " title="">12:04</p><p class="station"><strong class="name ">Praha hl.n.</strong> <span><span title="tariff zone" class="color-lightgrey">P</span> <span title="platform" class="color-green">4</span></span></p>
      <p class="reset time  " title="">15:44</p><p class="station"><strong class="name ">Brno hl.n.</strong> <span><span title="tariff zone" class="color-lightgrey">100</span></span></p>
    </div>
    <script>
    var connResult = new Conn.ConnResult(params, null, {"connData":[{"connId":396829589,"trains":[{"ttIndex":0,"train":74552,"dateFromValue":"2026-06-18T00:00:00","timeFrom":"12:04"}]}]});
    </script>
    """

    let connections = IDOSConnectionParser.parse(
        html: html,
        timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains")
    )

    #expect(connections.count == 1)
    #expect(connections.first?.id == "396829589")
    #expect(connections.first?.duration == "3 h 40 min")
    #expect(connections.first?.legs.first?.name == "R9 (R 981 Vysocina)")
    #expect(connections.first?.legs.first?.id == "vlaky:0-74552-18.06.2026 12:04:00")
    #expect(connections.first?.legs.first?.color == "#FF0000")
    #expect(connections.first?.legs.first?.transportMode == .train)
    #expect(connections.first?.legs.first?.fromTariffZone == "P")
    #expect(connections.first?.legs.first?.fromPlatform == "4")
    #expect(connections.first?.legs.first?.toTariffZone == "100")
    #expect(connections.first?.legs.first?.serviceInformation.map(\.category) == [
        .firstClassSeating,
        .wiFi,
        .bicycle,
        .wheelchair,
    ])
    #expect(connections.first?.legs.first?.serviceInformation.map(\.symbol) == [
        "1️⃣",
        "🛜",
        "🚲",
        "♿",
    ])
    #expect(connections.first?.summaryLine(number: 1).contains("🚆") == true)
    #expect(connections.first?.summaryLine(number: 1).contains("tariff zone P · platform 4") == true)
    #expect(connections.first?.summaryLine(number: 1).contains("\u{001B}[38;2;255;0;0mR9") == true)
}

@Test func connectionParserBuildsCalendarModelFromResultHtml() throws {
    let html = """
    <div id="connectionBox-396829589" class="box connection" data-share-url="https://idos.cz/en/vlaky/spojeni/prehled/?p=abc">
      <p class="reset total">Overall time <strong>3 h 40 min</strong></p>
      <h3 title="fast train"><span>R9 (R 981 Vysocina)</span></h3>
      <p class="reset time" title="">12:04</p><p class="station"><strong class="name ">Praha hl.n.</strong></p>
      <p class="reset time" title="">15:44</p><p class="station"><strong class="name ">Brno hl.n.</strong></p>
    </div>
    <script>
    var connResult = new Conn.ConnResult(params, null, {"handle":123,"connData":[{"connId":396829589,"trains":[]}],"searchItem":{"sCombName":"Trains"}});
    </script>
    """

    let connection = try #require(IDOSConnectionParser.parse(html: html).first)
    let model = try #require(connection.calendarModel)
    let data = try #require(model.data(using: .utf8))
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let jsConnData = try #require(json["jsConnData"] as? [String: Any])
    let connData = try #require(jsConnData["connData"] as? [[String: Any]])

    #expect(jsConnData["handle"] as? Int == 123)
    #expect(jsConnData["permanentUrl"] as? String == "https://idos.cz/en/vlaky/spojeni/prehled/?p=abc")
    #expect(connData.first?["connId"] as? Int == 396829589)
    #expect(connData.first?["priceOffer"] is NSNull)

    let pdfModel = try #require(connection.pdfModel)
    let pdfData = try #require(pdfModel.data(using: .utf8))
    let pdfJSON = try #require(JSONSerialization.jsonObject(with: pdfData) as? [String: Any])
    let pdfConnectionData = try #require(pdfJSON["jsConnData"] as? [String: Any])

    #expect(pdfJSON["context"] as? Int == 2)
    #expect(pdfConnectionData["permanentUrl"] == nil)
}

@Test func connectionParserReadsCzechResultTextAndCombinedPlatform() throws {
    let html = """
    <div id="connectionBox-1" class="box connection">
      <p class="reset total">Celkový čas <strong>1 hod 46 min</strong></p>
      <h3 title="osobní vlak" style="color: #0000FF;"><span>S6 (Os 3133)</span></h3>
      <p class="specs">
        <span title="ve vlaku řazen vůz s bezdrátovým připojením k internetu">Wi</span>
      </p>
      <p class="reset time" title="">17:37</p><p class="station"><strong class="name">Valašské Meziříčí</strong> <span title="tarifní pásmo">240</span></p>
      <p class="reset time" title="">19:23</p><p class="station"><strong class="name">Ostrava hl.n.</strong> <span title="nástupiště/kolej">5/4</span></p>
    </div>
    """

    let connection = try #require(IDOSConnectionParser.parse(html: html).first)

    #expect(connection.duration == "1 hod 46 min")
    #expect(connection.legs.first?.fromTariffZone == "240")
    #expect(connection.legs.first?.toPlatform == "5/4")
    #expect(connection.summaryLine(number: 1).contains("platform 5 track 4"))
    #expect(connection.legs.first?.serviceInformation.map(\.category) == [.wiFi])
    #expect(
        connection.legs.first?.serviceInformation.map(\.text) == [
            "ve vlaku řazen vůz s bezdrátovým připojením k internetu",
        ]
    )
}

@Test func nestedFormEncodingMatchesIDOSSharingFields() throws {
    let model: [String: Any] = [
        "context": 2,
        "jsConnData": [
            "active": true,
            "connData": [["connId": 123, "priceOffer": NSNull()]],
            "searchItem": ["name": "Praha hl.n."],
        ],
    ]

    let data = try #require(IDOSFormEncoding.nestedData(rootName: "pdfModel", value: model))
    let value = try #require(String(data: data, encoding: .utf8))

    #expect(value == [
        "pdfModel%5Bcontext%5D=2",
        "pdfModel%5BjsConnData%5D%5Bactive%5D=true",
        "pdfModel%5BjsConnData%5D%5BconnData%5D%5B0%5D%5BconnId%5D=123",
        "pdfModel%5BjsConnData%5D%5BconnData%5D%5B0%5D%5BpriceOffer%5D=",
        "pdfModel%5BjsConnData%5D%5BsearchItem%5D%5Bname%5D=Praha%20hl.n.",
    ].joined(separator: "&"))
}

@Test func connectionEmailDraftReadsIDOSMessageAndAttachmentNames() throws {
    let data = Data(
        #"{"filename":"connection.pdf","filename2":"connection.ics","message":"Prepared by IDOS","description":"Connection detail","error":null}"#.utf8
    )

    let draft = try IDOSClient.connectionEmailDraft(from: data)

    #expect(draft == IDOSConnectionEmailDraft(
        message: "Prepared by IDOS",
        description: "Connection detail",
        attachmentFileNames: ["connection.pdf", "connection.ics"]
    ))
}

@Test func connectionEmailDraftRejectsAnIDOSPreparationError() {
    let data = Data(
        #"{"filename":null,"filename2":null,"message":null,"description":null,"error":"Connection is unavailable."}"#.utf8
    )

    do {
        _ = try IDOSClient.connectionEmailDraft(from: data)
        Issue.record("Expected an unavailable email draft error.")
    } catch IDOSError.emailUnavailable {
        // The server's preparation error deliberately maps to the stable public capability error.
    } catch {
        Issue.record("Unexpected error: \(error).")
    }
}

@Test func connectionEmailDeliveryValidatesIDOSResultErrors() throws {
    try IDOSClient.validateConnectionEmailDelivery(
        from: Data(#"{"errors":[],"showErrorModal":false}"#.utf8)
    )

    do {
        try IDOSClient.validateConnectionEmailDelivery(
            from: Data(#"{"errors":["Invalid recipient.","Try again."],"showErrorModal":false}"#.utf8)
        )
        Issue.record("Expected an email delivery error.")
    } catch IDOSError.emailSendingFailed(let detail) {
        #expect(detail == "Invalid recipient. Try again.")
    } catch {
        Issue.record("Unexpected error: \(error).")
    }
}

@Test func connectionParserReadsPagingContextFromResultHtml() throws {
    let html = """
    <script>
    var connResult = new Conn.ConnResult(params, null, {
      "handle":123,
      "arrivalThere":"0001-01-01T00:00:00",
      "connData":[],
      "searchItem":{
        "oConn":{
          "oUserInput":{
            "dtSearchDate":"2026-06-21T12:00:00+02:00",
            "oFrom":{"sName":"Praha","sAdvancedName":"Praha"},
            "oTo":{"sName":"Brno","sAdvancedName":"Brno"}
          }
        }
      }
    });
    </script>
    """

    let context = try #require(IDOSConnectionParser.pagingContext(html: html))

    #expect(context.handle == 123)
    #expect(context.searchDate == "2026-06-21T12:00:00+02:00")
    #expect(context.arrivalThere == "0001-01-01T00:00:00")
    #expect(context.from == "Praha")
    #expect(context.to == "Brno")
    #expect(context.allowPrevious == true)
    #expect(context.allowNext == true)
}

@Test func connectionParserKeepsHtmlOutsideLineNames() {
    let html = """
    <div id="connectionBox-1122672429" class="box connection">
      <p class="reset total">Overall time <strong>38 min</strong></p>
      <h3 title="bus (Nove Dvory,Frydecka skladka >> Mistek,Riviera)" style="color: #0000FF;"><span>Bus 302</span></h3>
      <p class="reset time" title="">11:53</p><p class="station"><strong class="name ">Frýdek,Na Veselé</strong></p>
      <p class="reset time" title="">12:06</p><p class="station"><strong class="name ">Místek,Anenská</strong></p>
      <span class="operator"><span>Transdev Slezsko a.s.</span></span>
      <span class="delay-bubble">Currently no delay</span>
      <h3 title="local bus (Frenstat p.Radh.,,u skol >> Ostrava,Mor.Ostrava,Namesti Republiky)" style="color: #0000FF;"><span>Bus 980</span></h3>
      <p class="reset time" title="">12:13</p><p class="station"><strong class="name ">Frýdek-Místek,Místek,Anenská</strong></p>
      <p class="reset time" title="">12:31</p><p class="station"><strong class="name ">Ostrava,Hrabůvka,Benzina</strong></p>
    </div>
    """

    let connection = IDOSConnectionParser.parse(html: html).first
    let summary = connection?.summaryLine(number: 1)

    #expect(connection?.legs.map(\.name) == ["Bus 302", "Bus 980"])
    #expect(connection?.legs.map(\.color) == ["#0000FF", "#0000FF"])
    #expect(connection?.legs.map(\.transportMode) == [.bus, .bus])
    #expect(connection?.legs.first?.carrier == "Transdev Slezsko a.s.")
    #expect(connection?.legs.first?.delay == "Currently no delay")
    #expect(summary?.contains("🚌") == true)
    #expect(summary?.contains("\u{001B}[38;2;0;0;255mBus 302") == true)
    #expect(summary?.contains("\n   🚌 \u{001B}[38;2;0;0;255mBus 980") == true)
    #expect(summary?.contains("; 🚌") == false)
    #expect(summary?.contains("style=") == false)
    #expect(summary?.contains("Transdev Slezsko a.s.") == true)
    #expect(summary?.contains("Currently no delay") == true)
}

@Test func connectionParserReadsMultipleHeadingsInsideSingleLineItem() {
    let html = """
    <div id="connectionBox-1" class="box connection">
      <p class="reset total">Overall time <strong>16 min</strong></p>
      <div class="line-item">
        <h3 title="bus (Řepiště,,U kříže >> Místek,Riviéra)" style="color: #0000FF;"><span>Bus 311</span></h3>
        <p class="reset time " title="" >10:10</p><p class="station"><strong class="name ">Frýdek,Sportovní hala Polárka</strong></p>
        <p class="reset time " title="" >10:13</p><p class="station"><strong class="name ">Místek,poliklinika</strong></p>
        <h3 title="bus (Místek,poliklinika >> Místek,poliklinika)" style="color: #0000FF;"><span>Bus 310</span></h3>
        <p class="reset time " title="" >10:15</p><p class="station"><strong class="name ">Místek,poliklinika</strong></p>
        <p class="reset time " title="" >10:26</p><p class="station"><strong class="name ">Frýdek,magistrát</strong></p>
      </div>
    </div>
    """

    let connection = IDOSConnectionParser.parse(html: html).first
    let summary = connection?.summaryLine(number: 1)

    #expect(connection?.legs.map(\.name) == ["Bus 311", "Bus 310"])
    #expect(connection?.legs.map(\.fromStation) == ["Frýdek,Sportovní hala Polárka", "Místek,poliklinika"])
    #expect(connection?.legs.map(\.toStation) == ["Místek,poliklinika", "Frýdek,magistrát"])
    #expect(summary?.contains("Bus 311") == true)
    #expect(summary?.contains("Bus 310") == true)
}

@Test func connectionParserInfersTrainFromRailLinePrefix() {
    let html = """
    <div id="connectionBox-401439022" class="box connection">
      <p class="reset total">Overall time <strong>2 h 39 min</strong></p>
      <h3 title="" style="color: #008000;"><span>RJ 1045 RegioJet</span></h3>
      <p class="reset time" title="">15:01</p><p class="station"><strong class="name ">Praha hl.n.</strong></p>
      <p class="reset time" title="">17:40</p><p class="station"><strong class="name ">Brno hl.n.</strong></p>
    </div>
    """

    let connection = IDOSConnectionParser.parse(html: html).first

    #expect(connection?.legs.first?.transportMode == .train)
    #expect(connection?.summaryLine(number: 1).contains("🚆") == true)
}

@Test func connectionParserKeepsMetropolitanTrainAsTrain() {
    let html = """
    <div id="connectionBox-1" class="box connection">
      <p class="reset total">Overall time <strong>2 h 37 min</strong></p>
      <h3 title="Eurocity (Praha hl.n. >> Budapest-Nyugati pu)"><span>Ex3 (EC 281 Metropolitan)</span></h3>
      <p class="reset time" title="">13:37</p><p class="station"><strong class="name ">Praha hl.n.</strong></p>
      <p class="reset time" title="">16:14</p><p class="station"><strong class="name ">Brno hl.n.</strong></p>
    </div>
    """

    let connection = IDOSConnectionParser.parse(html: html).first

    #expect(connection?.legs.first?.transportMode == .train)
    #expect(connection?.summaryLine(number: 1).contains("🚆") == true)
}

@Test func departureParserReadsDeparturesTableRows() throws {
    let html = """
    <h2 class="depTitlePage">Departures from Fr&#253;dek,Sportovn&#237; hala Pol&#225;rka</h2>
    <tr class="dep-row dep-row-first" data-ttindex="1" data-train="4286" data-datetime="18.06.2026 16:03:00" data-stationname="Rožnov p.Radh.,,aut.st.">
      <td class="departures-table__cell departures-table__cell--height-collapse" title="Arrival station"><h3>Rožnov p.Radh.,,aut.st.</h3></td>
      <td class="departures-table__cell departures-table__cell--height-collapse">
        <span class="wwwtt tt-icon-dep" style="color:#0000FF">&#247;</span>
        <span class="desc"><span class="code"><h3 style="color:#0000FF; display:inline">Bus 980</h3>
          <span title="train also consists of 1st class coaches">1.2.</span>
          <span title="carriage with a wireless internet connection">Wi</span>
          <span title="carriage of registered luggage (until full capacity)">K</span>
          <span title="coach suitable for carriage of people on wheelchairs">NP</span>
        </span></span>
      </td>
      <td class="departures-table__cell"><h3>16:03</h3></td>
      <td class="departures-table__cell"><span title="tariff zone" class="color-lightgrey">70</span> <span title="platform" class="color-lightgrey">1</span></td>
    </tr>
    <tr class="dep-row dep-row-second" data-ttindex="1" data-train="4286" data-datetime="18.06.2026 16:03:00">
      <td class="departures-table__cell small"><span title="pass via" class="color-lightgrey">via Frýdek-Místek,Místek,Anenská</span></td>
      <td class="departures-table__cell small"><span title="dopravce" class="color-lightgrey">Transdev Slezsko a.s.</span></td>
      <td class="departures-table__cell cell-delay" colspan="2"><a href="javascript:;" class="delay-bubble">Currently no delay</a></td>
    </tr>
    """

    let departure = IDOSDepartureParser.parse(
        html: html,
        timetable: IDOSTimetable(slug: "odis", displayName: "ODIS")
    ).first

    #expect(departure?.id == "odis:1-4286-18.06.2026 16:03:00")
    #expect(departure?.stationName == "Frýdek,Sportovní hala Polárka")
    #expect(departure?.time == "16:03")
    #expect(departure?.lineName == "Bus 980")
    #expect(departure?.lineColor == "#0000FF")
    #expect(departure?.transportMode == .bus)
    #expect(departure?.destination == "Rožnov p.Radh.,,aut.st.")
    #expect(departure?.tariffZone == "70")
    #expect(departure?.platform == "1")
    #expect(departure?.via == "Frýdek-Místek,Místek,Anenská")
    #expect(departure?.carrier == "Transdev Slezsko a.s.")
    #expect(departure?.delay == "Currently no delay")
    #expect(departure?.serviceInformation.map(\.text) == [
        "train also consists of 1st class coaches",
        "carriage with a wireless internet connection",
        "carriage of registered luggage (until full capacity)",
        "coach suitable for carriage of people on wheelchairs",
    ])
    #expect(departure?.serviceInformation.map(\.category) == [
        .firstClassSeating,
        .wiFi,
        .bicycle,
        .wheelchair,
    ])
    #expect(departure?.summaryLine(number: 1).contains("🚌") == true)
    #expect(departure?.summaryLine(number: 1).contains("tariff zone 70 · platform 1") == true)
    let scheduledDate = try #require(departure.flatMap { IDOSDepartureParser.scheduledDate(for: $0) })
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledDate)
    #expect(components.year == 2026)
    #expect(components.month == 6)
    #expect(components.day == 18)
    #expect(components.hour == 16)
    #expect(components.minute == 3)
}

@Test func departureParserReadsCzechStationBoardText() throws {
    let html = """
    <h2 class="depTitlePage">Odjezdy z Ostrava-Kunčičky</h2>
    <tr class="dep-row dep-row-first" data-ttindex="0" data-train="173271" data-datetime="04.08.2026 18:24:00" data-stationname="Ostrava hl.n.">
      <td><h3>Ostrava hl.n.</h3></td>
      <td><span class="desc"><span class="code"><h3 style="color:#0000FF">S6 (Os 3133)</h3>
        <span title="přeprava spoluzavazadel (do vyčerpání kapacity)">K</span>
      </span></span></td>
      <td><h3>18:24</h3></td>
      <td><span title="kolej">2</span></td>
    </tr>
    <tr class="dep-row dep-row-second">
      <td><span title="projíždí přes">přes Ostrava střed, Ostrava-Stodolní</span></td>
      <td><span title="dopravce">České dráhy, a.s.</span></td>
    </tr>
    """

    let departure = try #require(IDOSDepartureParser.parse(html: html).first)

    #expect(departure.stationName == "Ostrava-Kunčičky")
    #expect(departure.platform == "2")
    #expect(departure.via == "Ostrava střed, Ostrava-Stodolní")
    #expect(departure.serviceInformation.map(\.category) == [.bicycle])
}

@Test func departureParserPadsSingleDigitHourForServiceDetailID() throws {
    let html = """
    <tr class="dep-row dep-row-first" data-ttindex="0" data-train="281" data-datetime="31.08.2026 9:53:00" data-stationname="Frýdek-Místek,Místek,Ostravská">
      <td><h3>Frýdek-Místek,Místek,Ostravská</h3></td>
      <td><h3>Bus 302</h3></td>
      <td><h3>9:53</h3></td>
    </tr>
    <tr class="dep-row dep-row-second"><td></td></tr>
    """
    let timetable = IDOSTimetable(slug: "frydekmistek", displayName: "Urban Public Transport Frýdek-Místek")

    let departure = try #require(IDOSDepartureParser.parse(html: html, timetable: timetable).first)
    let reference = try IDOSServiceReference(id: departure.id, fallbackTimetable: .defaultTimetable)

    #expect(departure.id == "frydekmistek:0-281-31.08.2026 09:53:00")
    #expect(reference.id == departure.id)
    #expect(reference.hour == 9)
    #expect(IDOSDepartureParser.scheduledDate(for: departure) != nil)
}

@Test func serviceDetailParserReadsCompleteRouteAndInformation() throws {
    let html = """
    <div id="train-detail-151" data-share-url="https://idos.cz/service">
      <p class="line-top-date print-only">Departure from the initial station <strong>18.6.2026</strong></p>
      <h1 title="fast train" style="color: #008000;"><span>RJ 1051 RegioJet</span></h1>
      <ul class="reset line-itinerary">
        <li class="item inactive" title="Traffic restrictions">
          <span class="arrival"><span class="label out"></span></span>
          <span class="departure"><span class="label out"></span>11:45</span>
          <strong class="name">Praha-Zahradn&#237; Město</strong>
          <span class="fixed-codes"><span title="track">3</span></span>
          <span class="distance"><span class="label out"></span>0 km</span>
        </li>
        <li class="item" title="Click to refresh the current service position.">
          <span class="arrival"><span class="label out"></span>11:53</span>
          <span class="departure"><span class="label out"></span>12:04</span>
          <strong class="name">Praha hl.n.</strong>
          <span title="transfer to the undeground">#</span>
          <button title="Click to update the vehicle position."></button>
          <span class="fixed-codes"><span title="tariff zone">P</span></span>
          <span class="distance"><span class="label out"></span>7 km</span>
        </li>
        <li class="item" title="">
          <span class="arrival"><span class="label out"></span>15:44</span>
          <span class="departure"><span class="label out"></span></span>
          <strong class="name">Brno hl.n.</strong>
          <span class="fixed-codes"><span title="platform/track">3/1</span></span>
          <span class="distance"><span class="label out"></span>262 km</span>
        </li>
      </ul>
      <ul class="reset messages">
        <li class="message-red"><h3>Important information</h3><ul>
          <li>There is a planned traffic restriction.</li>
          <li class="remarks-list__item">České dráhy, a.s.</li>
        </ul></li>
      </ul>
      <ul class="reset line-share"></ul>
    </div>
    """

    let detail = try #require(IDOSServiceDetailParser.parse(
        html: html,
        id: "vlaky:0-74552-18.06.2026 12:04:00",
        timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains")
    ))

    #expect(detail.name == "RJ 1051 RegioJet")
    #expect(detail.timetable.slug == "vlaky")
    #expect(detail.color == "#008000")
    #expect(detail.transportMode == .train)
    #expect(detail.date == "18.6.2026")
    #expect(detail.stops.count == 3)
    #expect(detail.stops[0].name == "Praha-Zahradní Město")
    #expect(detail.stops[0].track == "3")
    #expect(detail.stops[0].notes == ["Traffic restrictions"])
    #expect(detail.stops[1].arrivalTime == "11:53")
    #expect(detail.stops[1].departureTime == "12:04")
    #expect(detail.stops[1].tariffZone == "P")
    #expect(detail.stops[1].notes == ["transfer to the undeground"])
    #expect(detail.stops[2].platformTrack == "3/1")
    #expect(detail.stops[2].notes.isEmpty)
    #expect(detail.information == ["There is a planned traffic restriction.", "České dráhy, a.s."])
    #expect(detail.shareURL == "https://idos.cz/service")
}

@Test func serviceDetailKeepsOnlyTheRequestedVariantOfBilingualCarrierInformation() throws {
    let html = """
    <div id="train-detail-151">
      <h1 title="bus"><span>RJ 1030 RegioJet</span></h1>
      <ul class="reset line-itinerary">
        <li class="item" title="">
          <span class="departure"><span class="label out"></span>10:00</span>
          <strong class="name">Brno</strong>
        </li>
        <li class="item" title="">
          <span class="arrival"><span class="label out"></span>12:30</span>
          <strong class="name">Praha</strong>
        </li>
      </ul>
      <ul class="reset messages"><li class="message"><h3>Information</h3><ul>
        <li>Brno-Praha</li>
        <li>RegioJet/STUDENT AGENCY k.s.; Brno; 222 222 221</li>
        <li>All information on www.regiojet.com</li>
        <li>Na lince je povinná rezervace místa. Na lince platí jízdné v tarifu dopravce. Informace o tarifu jsou uveřejněny v autobusech.</li>
        <li>Veškeré informace dostupné na www.regiojet.cz</li>
        <li>Places reservation required on the line. There is a valid tariff set by the carrier. The information about the tariff are published in busses.</li>
      </ul></li></ul>
      <ul class="reset line-share"></ul>
    </div>
    """

    let czech = try #require(IDOSServiceDetailParser.parse(
        html: html,
        id: "autobusy:1-1030-20.07.2026 10:00:00",
        language: .czech
    ))
    let english = try #require(IDOSServiceDetailParser.parse(
        html: html,
        id: "autobusy:1-1030-20.07.2026 10:00:00",
        language: .english
    ))

    #expect(czech.information == [
        "Brno-Praha",
        "RegioJet/STUDENT AGENCY k.s.; Brno; 222 222 221",
        "Na lince je povinná rezervace místa. Na lince platí jízdné v tarifu dopravce. Informace o tarifu jsou uveřejněny v autobusech.",
        "Veškeré informace dostupné na www.regiojet.cz",
    ])
    #expect(english.information == [
        "Brno-Praha",
        "RegioJet/STUDENT AGENCY k.s.; Brno; 222 222 221",
        "All information on www.regiojet.com",
        "Places reservation required on the line. There is a valid tariff set by the carrier. The information about the tariff are published in busses.",
    ])
}

@Test func serviceReferenceUsesEmbeddedTimetableAndCanonicalizesLegacyIDs() throws {
    let fallback = IDOSTimetable(slug: "odis", displayName: "ODIS")
    let selfContained = try IDOSServiceReference(
        id: "vlaky:0-74552-18.06.2026 12:04:00",
        fallbackTimetable: fallback
    )
    let legacy = try IDOSServiceReference(
        id: "1-4286-18.06.2026 16:03:00",
        fallbackTimetable: fallback
    )

    #expect(selfContained.timetable.slug == "vlaky")
    #expect(selfContained.id == "vlaky:0-74552-18.06.2026 12:04:00")
    #expect(legacy.timetable.slug == "odis")
    #expect(legacy.id == "odis:1-4286-18.06.2026 16:03:00")
}

@Test func idosLanguageBuildsLocalizedEndpointPaths() {
    let timetable = IDOSTimetable(slug: "vlaky", displayName: "Trains")

    #expect(IDOSLanguage.english.path(
        timetable: timetable,
        endpoint: "Ajax/TrainDetail"
    ) == "/en/vlaky/Ajax/TrainDetail")
    #expect(IDOSLanguage.czech.path(
        timetable: timetable,
        endpoint: "Ajax/TrainDetail"
    ) == "/vlaky/Ajax/TrainDetail")
    #expect(IDOSLanguage.english.path(
        timetable: timetable,
        endpoint: "spojeni/kalendar"
    ) == "/en/vlaky/spojeni/kalendar")
    #expect(IDOSLanguage.czech.path(
        timetable: timetable,
        endpoint: "spojeni/kalendar"
    ) == "/vlaky/spojeni/kalendar")
}

@Test func timetableValidityParserReadsInclusiveIDOSSearchRange() throws {
    let html = """
    <script>
    var params = new Conn.ConnFormParams(new Date('12/14/2025'), new Date('12/12/2026'), '/vlaky/Ajax/');
    </script>
    """
    let validity = try #require(IDOSTimetableValidityParser.parse(html: html))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!

    #expect(calendar.dateComponents([.year, .month, .day], from: validity.validFrom) == DateComponents(
        year: 2025,
        month: 12,
        day: 14
    ))
    #expect(calendar.dateComponents([.year, .month, .day], from: validity.validThrough) == DateComponents(
        year: 2026,
        month: 12,
        day: 12
    ))
}

@Test func connectionFormParserReadsIDOSCombinationIdentifier() {
    let html = """
    <script>
    var params = new Conn.ConnFormParams(
        new Date('12/14/2025'), new Date('12/12/2026'), '/en/vlaky/Ajax/',
        {"advanced":{"maximumChanges":4}}, 50, '1', 'Vlak', 'VlakBusMHDVSECZ', false
    );
    </script>
    """

    #expect(IDOSConnectionFormParser.combinationID(in: html) == "Vlak")
    #expect(IDOSConnectionFormParser.combinationID(in: "<html></html>") == nil)
}

@Test func serviceDateLimitsParserReadsExactIDOSMonthStates() throws {
    let august = Array(repeating: 2, count: 26) + [1, 0, 1, 0, 1]
    let september = Array(repeating: 1, count: 30)
    let script = """
    this._startDay.setFullYear(2026,7,27);
    this._aiDateLim = new Array(
        new Array(\(august.map(String.init).joined(separator: ", "))),
        new Array(\(september.map(String.init).joined(separator: ", ")))
    );
    this._actMonthIndex = 0;
    """
    let limits = try #require(IDOSServiceDateLimitsParser.parse(script: script))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    let date: (Int, Int, Int) -> Date = { year, month, day in
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    #expect(calendar.dateComponents([.year, .month, .day], from: limits.referenceDate) == DateComponents(
        year: 2026,
        month: 8,
        day: 27
    ))
    #expect(limits.days.count == 61)
    #expect(limits.firstDate == date(2026, 8, 1))
    #expect(limits.lastDate == date(2026, 9, 30))
    #expect(limits.status(on: date(2026, 8, 26)) == .informationUnavailable)
    #expect(limits.status(on: date(2026, 8, 27)) == .runs)
    #expect(limits.status(on: date(2026, 8, 28)) == .doesNotRun)
    #expect(limits.status(on: date(2026, 9, 30)) == .runs)
    #expect(limits.status(on: date(2026, 10, 1)) == nil)
}

@Test func serviceDateLimitsParserRejectsIncompleteMonthsAndUnknownStates() {
    let incomplete = """
    this._startDay.setFullYear(2026,7,27);
    this._aiDateLim = new Array(new Array(1, 0));
    """
    let unknownState = """
    this._startDay.setFullYear(2026,8,1);
    this._aiDateLim = new Array(new Array(3, \(Array(repeating: 1, count: 29).map(String.init).joined(separator: ", "))));
    """

    #expect(IDOSServiceDateLimitsParser.parse(script: incomplete) == nil)
    #expect(IDOSServiceDateLimitsParser.parse(script: unknownState) == nil)
}

@Test func serviceDetailParserReadsCzechStopMetadata() throws {
    let html = """
    <div id="train-detail-151">
      <p class="line-top-date print-only">Odjezd z výchozí stanice <strong>18.6.2026</strong></p>
      <h1 title="vlak"><span>RJ 1051 RegioJet</span></h1>
      <ul class="reset line-itinerary">
        <li class="item" title="Omezen&#237; provozu">
          <span class="arrival"><span class="label out"></span>11:53</span>
          <span class="departure"><span class="label out"></span>12:04</span>
          <strong class="name">Praha hl.n.</strong>
          <span title="přestup na Metro">#</span>
          <button title="Kliknutím se aktualizuje poloha spoje."></button>
          <span class="fixed-codes">
            <span title="tar. pásmo">1,2</span>
            <span title="stanoviště">2</span>
            <span title="kolej">4</span>
            <span title="nástupiště/kolej">2/4</span>
          </span>
          <span class="distance"><span class="label out"></span>7 km</span>
        </li>
      </ul>
      <ul class="reset messages"></ul>
      <ul class="reset line-share"></ul>
    </div>
    """

    let detail = try #require(IDOSServiceDetailParser.parse(
        html: html,
        id: "vlaky:0-74552-18.06.2026 12:04:00",
        timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains")
    ))
    let stop = try #require(detail.stops.first)

    #expect(stop.tariffZone == "1,2")
    #expect(stop.platform == "2")
    #expect(stop.track == "4")
    #expect(stop.platformTrack == "2/4")
    #expect(stop.notes == ["Omezení provozu", "přestup na Metro"])
}

/// Keeps legacy output assertions deterministic regardless of the developer machine's locale.
private func englishCommandRunner(
    client: IDOSClienting = IDOSClient(),
    aliasFile: StopAliasFile = StopAliasFile(),
    calendarImporter: CalendarImporting = SystemCalendarImporter()
) -> CommandRunner {
    CommandRunner(
        client: client,
        aliasFile: aliasFile,
        calendarImporter: calendarImporter,
        preferredLanguageIdentifiers: ["en"],
        environment: [:]
    )
}

/// Supplies two provider catalogs with the same timetable identifier so CLI routing cannot pass by accident.
private struct CLIRoutingDataSource: TransitDataSource {
    let descriptor: TransitDataSourceDescriptor
    let defaultTimetable: TransitTimetable

    init(
        id: TransitDataSourceID,
        timetableName: String,
        capabilities: Set<TransitDataSourceCapability> = [.timetables],
        connectionOptions: Set<TransitConnectionOption> = []
    ) {
        descriptor = TransitDataSourceDescriptor(
            id: id,
            displayName: timetableName,
            capabilities: capabilities,
            connectionOptions: connectionOptions
        )
        defaultTimetable = TransitTimetable(
            dataSourceID: id,
            identifier: "shared",
            displayName: timetableName
        )
    }

    func findConnections(request: TransitConnectionRequest) async throws -> [TransitConnection] {
        []
    }
}

private func timetableName(in output: String) throws -> String? {
    let json = try jsonDictionary(output)
    let timetables = try #require(json["timetables"] as? [[String: Any]])
    return timetables.first?["displayName"] as? String
}

private struct MockIDOSClient: IDOSClienting {
    let descriptor = TransitDataSourceDescriptor.idos
    var expectedConnectionTimetable = "vlaky"
    var expectedFrom = "Praha"
    var expectedTo = "Brno"
    var expectedIsArrival = false
    var expectedOnlyDirect = false
    var expectedVia: [String] = []
    var expectedTransportModeFilters: [TransitConnectionTransportModeFilter]? = nil
    var expectedMaxTransfers: Int? = nil
    var expectedMinimumTransferTime: Int? = nil
    var expectedMaximumTransferTime: Int? = nil
    var expectedMaximumWalkingTime: Int? = nil
    var expectedMaximumCityWalkingTime: Int? = nil
    var expectedWalkToNearbyStops: Bool? = nil
    var expectedSameNameWalkingTransfersOnly: Bool? = nil
    var expectedWheelchairAccessibleConnectionsOnly: Bool? = nil
    var expectedLowFloorConnectionsOnly: Bool? = nil
    var expectedPreferTrainsOverBuses: Bool? = nil
    var expectedTrainConnectionsForWheelchairPassengers: Bool? = nil
    var expectedTrainConnectionsForPassengersWithChildren: Bool? = nil
    var expectedConnectionsForPassengersWithBicycles: Bool? = nil
    var expectedPreferBusyRoutes: Bool? = nil
    var expectedBedOrCouchettePreference: TransitBedOrCouchettePreference? = nil
    var expectedConnectionResultLimit: Int? = nil
    var validatesConnectionResultLimit = false
    var failConnectionsWithNetworkError = false
    var connectionResults: [IDOSConnection]? = nil
    var expectedDepartureTimetable = "odis"
    var expectedStation = "Ostrava,Hrabůvka,Benzina"
    var resolvedStationName: String? = nil
    var expectedDepartureIsArrival = false
    var departureResults: [IDOSDeparture]? = nil
    var suggestionResultsByPrefix: [String: [IDOSSuggestion]] = [:]
    var stationResultsByPrefix: [String: [IDOSSuggestion]] = [:]
    var expectedServiceTimetable = IDOSTimetable.defaultTimetable.slug
    var expectedServiceLanguage: IDOSLanguage = .english
    var expectedStationTimetable = "pid"
    var expectedStationTimetableMunicipality: IDOSStationTimetableMunicipality? = nil
    var expectedStationTimetableLine = "Bus 154"
    var expectedStationTimetableFrom = "Strašnická"
    var expectedStationTimetableTo = "Sídliště Libuš"
    var expectedStationTimetableLanguage: IDOSLanguage = .english
    var expectedCalendarLanguage: IDOSLanguage = .english

    func suggest(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion] {
        if let suggestions = suggestionResultsByPrefix[prefix] {
            return Array(suggestions.prefix(limit))
        }

        return prefix == "Praha" ? Array(stationSuggestions.prefix(limit)) : []
    }

    func searchStations(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion] {
        if let stations = stationResultsByPrefix[prefix] {
            return Array(stations.prefix(limit))
        }

        return prefix == "Praha" ? Array(stationSuggestions.prefix(limit)) : []
    }

    private var stationSuggestions: [IDOSSuggestion] {
        return [
            IDOSSuggestion(
                selectedText: "Praha hl.n.",
                text: "Praha hl.n.",
                description: "station, district Praha, trains, urban public transport",
                region: "district Praha",
                value: "100003",
                value2: "25948",
                iconId: 14,
                coorX: 50.082979,
                coorY: 14.43595
            )
        ]
    }

    func findConnections(request: IDOSConnectionRequest) async throws -> [IDOSConnection] {
        #expect(request.timetable.slug == expectedConnectionTimetable)
        #expect(request.from == expectedFrom)
        #expect(request.to == expectedTo)
        #expect(request.isArrival == expectedIsArrival)
        #expect(request.onlyDirect == expectedOnlyDirect)
        #expect(request.via == expectedVia)
        #expect(request.transportModeFilters == expectedTransportModeFilters)
        #expect(request.maxTransfers == expectedMaxTransfers)
        #expect(request.minimumTransferTime == expectedMinimumTransferTime)
        #expect(request.maximumTransferTime == expectedMaximumTransferTime)
        #expect(request.maximumWalkingTime == expectedMaximumWalkingTime)
        #expect(request.maximumCityWalkingTime == expectedMaximumCityWalkingTime)
        #expect(request.walkToNearbyStops == expectedWalkToNearbyStops)
        #expect(request.sameNameWalkingTransfersOnly == expectedSameNameWalkingTransfersOnly)
        #expect(
            request.wheelchairAccessibleConnectionsOnly
                == expectedWheelchairAccessibleConnectionsOnly
        )
        #expect(request.lowFloorConnectionsOnly == expectedLowFloorConnectionsOnly)
        #expect(request.preferTrainsOverBuses == expectedPreferTrainsOverBuses)
        #expect(
            request.trainConnectionsForWheelchairPassengers
                == expectedTrainConnectionsForWheelchairPassengers
        )
        #expect(
            request.trainConnectionsForPassengersWithChildren
                == expectedTrainConnectionsForPassengersWithChildren
        )
        #expect(
            request.connectionsForPassengersWithBicycles
                == expectedConnectionsForPassengersWithBicycles
        )
        #expect(request.preferBusyRoutes == expectedPreferBusyRoutes)
        #expect(request.bedOrCouchettePreference == expectedBedOrCouchettePreference)
        if validatesConnectionResultLimit {
            #expect(request.resultLimit == expectedConnectionResultLimit)
        }

        if failConnectionsWithNetworkError {
            throw IDOSError.networkUnavailable("")
        }

        if let connectionResults {
            return connectionResults
        }

        return [
            IDOSConnection(
                id: "396829589",
                departureTime: "12:04",
                departureStation: "Praha hl.n.",
                arrivalTime: "15:44",
                arrivalStation: "Brno hl.n.",
                duration: "3 hod 40 min",
                legs: [
                    IDOSConnectionLeg(
                        name: "R9 (R 981 Vysočina)",
                        id: "vlaky:0-74552-18.06.2026 12:04:00",
                        color: "#008000",
                        transportMode: .train,
                        departureTime: "12:04",
                        fromStation: "Praha hl.n.",
                        fromTariffZone: "P",
                        fromPlatform: "4",
                        arrivalTime: "15:44",
                        toStation: "Brno hl.n.",
                        toTariffZone: "100",
                        carrier: "České dráhy, a.s.",
                        delay: "Currently no delay"
                    )
                ],
                shareURL: "https://idos.cz/detail",
                calendarModel: #"{"jsConnData":{"connData":[],"searchItem":{},"permanentUrl":"https://idos.cz/detail"}}"#
            )
        ]
    }

    func connectionCalendar(for connection: IDOSConnection, timetable: IDOSTimetable) async throws -> String {
        calendar(for: connection, timetable: timetable, language: .english)
    }

    func connectionCalendar(
        for connection: IDOSConnection,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws -> String {
        calendar(for: connection, timetable: timetable, language: language)
    }

    private func calendar(
        for connection: IDOSConnection,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) -> String {
        #expect(timetable.slug == expectedConnectionTimetable)
        #expect(connection.id == "396829589")
        #expect(language == expectedCalendarLanguage)

        let summary = language == .czech
            ? "Spojení Praha hl.n. >> Brno hl.n."
            : "Connection Praha hl.n. >> Brno hl.n."

        return """
        BEGIN:VCALENDAR
        VERSION:2.0
        SUMMARY:\(summary)
        END:VCALENDAR
        """
    }

    func findDepartures(request: IDOSDeparturesRequest) async throws -> [IDOSDeparture] {
        #expect(request.timetable.slug == expectedDepartureTimetable)
        #expect(request.station == expectedStation)
        #expect(request.isArrival == expectedDepartureIsArrival)

        if let departureResults {
            return departureResults
        }

        return [
            IDOSDeparture(
                id: "odis:1-4286-18.06.2026 16:03:00",
                stationName: resolvedStationName,
                time: "16:03",
                lineName: "Bus 980",
                lineColor: "#0000FF",
                transportMode: .bus,
                destination: "Rožnov p.Radh.,,aut.st.",
                tariffZone: "70",
                platform: "1",
                via: "Frýdek-Místek,Místek,Anenská",
                carrier: "Transdev Slezsko a.s.",
                delay: "Currently no delay"
            )
        ]
    }

    func findStationTimetable(
        request: IDOSStationTimetableRequest,
        language: IDOSLanguage
    ) async throws -> IDOSStationTimetable {
        #expect(request.timetable.slug == expectedStationTimetable)
        #expect(request.municipality == expectedStationTimetableMunicipality)
        #expect(request.line == expectedStationTimetableLine)
        #expect(request.from == expectedStationTimetableFrom)
        #expect(request.to == expectedStationTimetableTo)
        #expect(request.date == "17.7.2026")
        #expect(request.wholeWeek)
        #expect(language == expectedStationTimetableLanguage)

        return IDOSStationTimetable(
            timetable: request.timetable,
            municipality: request.municipality,
            lineName: request.line,
            transportMode: .bus,
            fromStop: request.from,
            toStop: request.to,
            stops: [
                IDOSStationTimetableStop(
                    name: request.from,
                    minuteOffset: 0,
                    tariffZone: "0",
                    platform: "1",
                    isSelected: true,
                    notes: ["request stop"]
                ),
                IDOSStationTimetableStop(
                    name: "Na Hroudě",
                    minuteOffset: 1,
                    tariffZone: "B",
                    platform: "2",
                    notes: ["wheelchair accessible stop"]
                ),
            ],
            schedules: [
                IDOSStationTimetableSchedule(
                    label: "17.7.2026 Friday",
                    hours: [
                        IDOSStationTimetableHour(hour: "5", departures: ["13", "35A", "55"]),
                        IDOSStationTimetableHour(hour: "6", departures: []),
                    ]
                ),
            ],
            explanations: ["A: runs only to stop Háje"],
            notes: ["valid from 1.7.2026"],
            isLockout: true,
            shareURL: "https://idos.cz/en/pid/zjr/?l=154"
        )
    }

    func serviceDetail(id: String, timetable: IDOSTimetable) async throws -> IDOSServiceDetail {
        #expect(id == "vlaky:0-74552-18.06.2026 12:04:00")
        #expect(timetable.slug == expectedServiceTimetable)
        return mockServiceDetail(id: id)
    }

    func serviceDetail(
        id: String,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws -> IDOSServiceDetail {
        #expect(id == "vlaky:0-74552-18.06.2026 12:04:00")
        #expect(timetable.slug == expectedServiceTimetable)
        #expect(language == expectedServiceLanguage)
        return mockServiceDetail(id: id, language: language)
    }
}

private func mockServiceDetail(
    id: String,
    language: IDOSLanguage = .english
) -> IDOSServiceDetail {
    let isCzech = language == .czech
    return IDOSServiceDetail(
        id: id,
        timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains"),
        name: "RJ 1051 RegioJet",
        color: "#008000",
        transportMode: .train,
        date: "18.6.2026",
        stops: [
            IDOSServiceStop(
                name: "Praha-Zahradní Město",
                departureTime: "11:45",
                track: "3",
                distance: "0 km",
                notes: [isCzech ? "Omezení provozu" : "Traffic restrictions"]
            ),
            IDOSServiceStop(
                name: "Praha hl.n.",
                arrivalTime: "11:53",
                departureTime: "12:04",
                tariffZone: "P",
                distance: "7 km",
                notes: [isCzech ? "přestup na Metro" : "transfer to the undeground"]
            ),
            IDOSServiceStop(
                name: "Brno hl.n.",
                arrivalTime: "15:44",
                platformTrack: "3/1",
                distance: "262 km",
                notes: isCzech
                    ? [
                        "bezbariérově přístupná stanice",
                        "zastávka s možností přestupu na železniční dopravu",
                    ]
                    : ["wheelchair accessible station", "rail station"]
            ),
        ],
        information: [
            isCzech ? "Plánované omezení provozu" : "Planned traffic restriction",
            "České dráhy, a.s.",
        ],
        shareURL: "https://idos.cz/service"
    )
}

private struct MockCalendarImporter: CalendarImporting {
    var path: String

    func add(calendar: String, fileName: String) throws -> URL {
        #expect(calendar.contains("BEGIN:VCALENDAR"))
        #expect(fileName == "kastan-396829589.ics")

        return URL(fileURLWithPath: path)
    }
}

private func connectionResult(
    id: String,
    duration: String,
    legNames: [String],
    transportMode: IDOSTransportMode? = .train
) -> IDOSConnection {
    IDOSConnection(
        id: id,
        departureTime: "12:00",
        departureStation: "Praha hl.n.",
        arrivalTime: "16:00",
        arrivalStation: "Brno hl.n.",
        duration: duration,
        legs: legNames.enumerated().map { index, name in
            IDOSConnectionLeg(
                name: name,
                transportMode: transportMode,
                departureTime: "1\(index + 2):00",
                fromStation: index == 0 ? "Praha hl.n." : "Pardubice hl.n.",
                arrivalTime: "1\(index + 3):00",
                toStation: index == legNames.count - 1 ? "Brno hl.n." : "Pardubice hl.n."
            )
        }
    )
}

private func ambiguousPIDStationSuggestions() -> [IDOSSuggestion] {
    [
        IDOSSuggestion(
            selectedText: "Sídliště Petrovice",
            text: "Sídliště Petrovice",
            description: "stop (Praha)",
            value: "301003",
            value2: "6362",
            iconId: 4
        ),
        IDOSSuggestion(
            selectedText: "Sídliště Petřiny",
            text: "Sídliště Petřiny",
            description: "stop (Praha)",
            value: "301003",
            value2: "6363",
            iconId: 15
        ),
    ]
}

private func jsonDictionary(_ output: String) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(output.utf8))
    return try #require(object as? [String: Any])
}

private func temporaryAliasFile() -> StopAliasFile {
    StopAliasFile(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("kastan-tests-\(UUID().uuidString)")
        .appendingPathComponent("aliases.json"))
}
